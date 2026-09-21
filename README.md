# 不用 Docker-in-Docker 也能用 Docker — GitHub Actions 策略驗證場

> Repo: https://github.com/s12ryt/gha-docker-no-dind-lab (Private)
> 原則: **絕不用 `docker:dind`**。所有 workflow 皆 `workflow_dispatch` 手動觸發、ubuntu-latest。

## 為什麼不要 Docker-in-Docker?

- dind 需要 `--privileged`,安全性差、租用環境常被禁止
- GitHub-hosted runner **本來就有完整的 host Docker daemon**,直接用即可
- dind 有巢狀儲存層效能損耗、IPC/網路複雜、快取難共用等問題

## 策略總覽

| # | Workflow | 模式 | 需要 dockerd? | 需要 root? | 適用場景 |
|---|----------|------|:---:|:---:|----------|
| 01 | host-daemon | 直接用 runner 預裝 Docker | ✅ (host 提供) | runner 本身 root | 99% 的情況,預設首選 |
| 02 | service-container | `services:` sidecar | ✅ (host 管理) | 不需 | 整合測試要 DB/Redis/HTTP mock |
| 03 | container-job | job 跑在 container | ❌ | ❌ | 固定工具鏈環境,完全不需要 docker |
| 04 | rootless-podman | Podman 無 daemon | ❌ | ❌ | 想要無 root、無 dockerd 的 build/run |
| 05 | buildx-bake | buildx + bake | ✅ (host) | runner root | 多目標/多平台建構、快取匯出 |
| 06 | kaniko | 使用者空間建構 | 建構時 ❌ | ❌ | 受限環境建 image (只產 tar) |
| 07 | nerdctl-rootful | containerd CLI | ❌ (用 containerd) | ✅ (sudo) | Docker 相容 CLI 直連 containerd |
| 08 | nerdctl-rootless | rootless containerd | ❌ | ❌ | 最嚴格: 無 root 無 dockerd 全功能 |

## 各策略要點

### 01 Host Daemon
Runner 預裝 Docker 24+。`docker build/run/pull` 直接可用。

### 02 Service Container
`services:` 由 host daemon 起 sidecar,port 映射到 localhost。健康檢查 `options:` 要寫,否則 job 開始時服務可能沒就緒。

### 03 Container Job
`container: node:22` 讓每個 step 都在容器內執行,工具鏈固定,而且**完全不需要 docker**。

### 04 Rootless Podman
`apt install podman` 即得無 daemon、無 root 的 Docker 相容 CLI。

### 05 Buildx Bake
`setup-buildx-action` 的 `docker-container` driver 會起一個 buildkitd 容器(**不是 dind**,只負責 build)。`bake-action` 多目標 + `cache-to: gha` 是 CI 建構最佳實踐。

### 06 Kaniko
Kaniko 在容器內以使用者空間執行 Dockerfile 指令,不打包 daemon。`--no-push --tarPath` 產 tar,再由 host `docker load` 驗證。適合無法跑 dockerd 的叢集內建構。

### 07/08 Nerdctl
Docker 相容 CLI 直連 containerd。rootful 用系統 containerd (`sudo nerdctl`);rootless 需 `uidmap`+手動起 `containerd-rootless.sh` 與 rootlesskit 包的 `buildkitd` (Ubuntu 24.04 要先解 AppArmor,詳見踩坑紀錄)。

## 實測結果 (2026-09-21, ubuntu-latest / Ubuntu 24.04)

| # | Workflow | 結果 | 備註 |
|---|----------|:---:|------|
| 01 | host-daemon | ✅ | 直接用,零配置 |
| 02 | service-container | ✅ | redis + nginx sidecar |
| 03 | container-job | ✅ | node:22-bookworm-slim |
| 04 | rootless-podman | ✅ | apt 裝完直接用 |
| 05 | buildx-bake | ✅ | gha cache 生效 |
| 06 | kaniko | ✅ | --no-push 產 tar + docker load 驗證 |
| 07 | nerdctl-rootful | ✅ (修1輪) | 需手動啟動 buildkitd |
| 08 | nerdctl-rootless | ✅ (修4輪) | AppArmor + rootlesskit + socket 路徑三重坑 |

## 推薦

- 一般 CI: **01**;要 DB: **01+02**;固定工具鏈: **03**
- 安全/合規要求無 root 無 daemon: **04 或 08**
- 大型多目標建構: **05**;受限環境建 image: **06**

## 踩坑紀錄 (全部實測驗證)

### 07 nerdctl-rootful: buildkitd 不會自己起
- **症狀**: `nerdctl run` 正常,`nerdctl build` 報 `no buildkit host available`
- **根因**: GitHub runner 的系統 containerd 沒帶 buildkitd;nerdctl-full tarball 解開後 `buildkitd` 在 `/usr/local/bin` 但沒人啟動它
- **修法**: `sudo nohup buildkitd --addr unix:///run/buildkit/buildkitd.sock &` 手動起一個,健康檢查用 `buildctl --addr ... debug workers`,就緒後 `nerdctl build` 即可直連 (nerdctl 預設會找 `/run/buildkit/buildkitd.sock`)

### 08 nerdctl-rootless: 三層地獄,一次搞懂 rootless 的正確姿勢

**坑 1: Ubuntu 24.04 的 AppArmor 擋 unprivileged userns**
- **症狀**: `containerd-rootless-setuptool.sh install` 直接失敗,rootlesskit 起不來
- **根因**: runner 的 `kernel.apparmor_restrict_unprivileged_userns=1`,任何非 root 程式想建 user namespace 都被擋
- **修法**: 為 `rootlesskit` 與 `buildkitd` 各寫一個 unconfined profile 到 `/etc/apparmor.d/usr.local.bin.<bin>` (內容含 `userns,`),再 `systemctl restart apparmor`

**坑 2: buildkitd rootless 不能裸跑**
- **症狀**: `nohup buildkitd &` 直接退出,日誌寫「rootless mode requires to be executed as the mapped root in a user namespace; you may use RootlessKit」
- **修法**: 必須用 `rootlesskit` 包一層跑 (`--net=slirp4netns --copy-up=/etc`)

**坑 3: `--copy-up=/run` 會把 socket 關進小黑屋 (最隱蔽,花了兩輪才定位)**
- **症狀**: buildkitd 日誌明明顯示 `running server on /run/buildkit/buildkitd.sock`、worker 也註冊成功,但 host 端 `buildctl` 連線就是 timeout;socket 檔案在 host 上 `ls` 不到
- **根因**: `--copy-up=/run` 讓 rootlesskit 在**私有 mount namespace** 掛 tmpfs 蓋住 `/run`,buildkitd 把 socket 建在 namespace 裡,host (buildctl/nerdctl) 自然看不到。而 containerd-rootless.sh 能通,正是因為它的 socket 在 host 真實路徑 `$XDG_RUNTIME_DIR` 下
- **修法**: 拿掉 `--copy-up=/run`;socket 改放 `$XDG_RUNTIME_DIR/buildkit-default/buildkitd.sock` — 這是 nerdctl rootless 的預設 `BUILDKIT_HOST` 路徑,放這裡 `nerdctl build` 零配置自動接上。保險起見在 build step 再明確 `export BUILDKIT_HOST`

### 通用
- runner 的 `ubuntu-latest` (Ubuntu 24.04) 上,rootless 容器技術 (podman/nerdctl/rootlesskit) 全部都要先處理 AppArmor userns 限制,podman 是唯一內建處理好的 (04 直接過)
- `actions/checkout@v4` 有 Node 20 deprecation 警告 (2026-09 起),純警告不影響執行

## 本地驗證

```powershell
# 下載工具 + 全量驗證
pwsh scripts/Invoke-Validate.ps1

# 只跑 actionlint
pwsh scripts/Invoke-Validate.ps1 -SkipYamllint
```

## 觸發全部 workflow

```powershell
pwsh scripts/Invoke-DispatchAll.ps1          # 觸發並等到全部結束
pwsh scripts/Invoke-DispatchAll.ps1 -Watch   # 只輪詢不觸發
```
