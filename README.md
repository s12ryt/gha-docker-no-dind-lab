# Docker-in-Docker 策略驗證場 — 不用 dind 的 8 種姿勢 + 要用 dind 的 5 種姿勢

> Repo: https://github.com/s12ryt/gha-docker-no-dind-lab
> 所有 workflow 皆 `workflow_dispatch` 手動觸發、ubuntu-latest。

## 兩大系列

- **Part 1 (01-08): 不用 Docker-in-Docker 也能用 Docker** — 原則: 絕不用 `docker:dind`
- **Part 2 (09-13): 就是要用 Docker-in-Docker 時的正確姿勢** — dind service / TLS / container job / rootless / DooD

## 為什麼優先不要 Docker-in-Docker?

- dind 需要 `--privileged`,安全性差、租用環境常被禁止
- GitHub-hosted runner **本來就有完整的 host Docker daemon**,直接用即可
- dind 有巢狀儲存層效能損耗、IPC/網路複雜、快取難共用等問題

## 什麼時候「真的」需要 dind? (Part 2 存在的意義)

- 需要**完全隔離的 daemon 狀態** (build 之間互相污染、副作用測試)
- 需要**測試 docker 本身**或編排 dind 叢集 (如 CI for docker tools)
- 需要**可控的 daemon 版本/組態** (host daemon 不允許變更)
- 非 root、不給 privileged 的環境 → **12 rootless dind** 是唯一解

## Part 1 策略總覽 (01-08, 不用 dind)

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

## Part 2 策略總覽 (09-13, 就是用 dind)

| # | Workflow | 模式 | privileged? | TLS? | 隔離度 | 適用場景 |
|---|----------|------|:---:|:---:|:---:|----------|
| 09 | dind-service-notls | dind 當 `services:` sidecar | ✅ | ❌ (2375) | daemon 完全隔離 | 最經典的 dind 用法,job 環境不受污染 |
| 10 | dind-manual-tls | 手動 `docker run` dind + TLS | ✅ | ✅ (2376) | daemon 完全隔離 | 安全要求高,連線加密 |
| 11 | dind-job-container | job 跑在 `docker:cli` 容器 + dind service | ✅ | ❌ | job+daemon 都隔離 | GitLab 風格,工具鏈鎖死 |
| 12 | dind-rootless | `docker:dind-rootless` | ❌ | ✅ (2376) | daemon 完全隔離 + 無 root | **無法給 privileged 時的唯一 dind 解** |
| 13 | dood-socket-mount | DooD: 掛 host socket 建 sibling | ❌ | ❌ | ❌ (共用 host daemon) | 假 dind (Docker-outside-of-Docker),其實是 Part 1 思維 |

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

### 09 DinD Service (No TLS)
dind 當 `services:` sidecar,`DOCKER_TLS_CERTDIR: ''` 讓它聽 2375 無 TLS。job step 用 `DOCKER_HOST=tcp://127.0.0.1:2375` 操作「裡面的 docker」。**build 務必帶 retry** (原因見踩坑)。

### 10 DinD Manual + TLS
手動 `docker run --privileged -p 2376:2376 -v /tmp/dind-certs:/certs -e DOCKER_TLS_CERTDIR=/certs docker:dind`,客戶端用 `DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH=/tmp/dind-certs/client` 連線。憑證由 dind 自動生成,`docker` SAN 已含 localhost。

### 11 DinD Job Container
GitLab 風格:job 跑在 `docker:cli` 容器,dind 當 service,`DOCKER_HOST=tcp://docker:2375` (service 名即 hostname)。注意容器是 alpine,不能用 `actions/checkout` (無 node),Dockerfile 用 heredoc 現場生成。

### 12 DinD Rootless
`docker:dind-rootless` 免 `--privileged`,靠 rootlesskit 在 user namespace 內跑非 root dockerd。連線**必須走 TCP 2376 + TLS**,unix socket 被藏進 rootlesskit 私有 mount ns (詳見踩坑)。

### 13 DooD Socket Mount
「Docker-outside-of-Docker」:容器內掛 host 的 `/var/run/docker.sock`,build 出的是 **sibling** 不是 child。不需要任何特權,但完全沒隔離 — 語義上其實是 Part 1 的變體。

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
| 09 | dind-service-notls | ✅ (修3輪) | service 容器會被 runner 重建 + dockerd 無 TLS 減速啟動 |
| 10 | dind-manual-tls | ✅ | 一次過 |
| 11 | dind-job-container | ✅ | 一次過 (GitLab 風格) |
| 12 | dind-rootless | ✅ (修5輪) | named AppArmor + /dev/net/tun + TCP/TLS 三重解 |
| 13 | dood-socket-mount | ✅ | 一次過 |

## 推薦

### Part 1 (不需要 dind)
- 一般 CI: **01**;要 DB: **01+02**;固定工具鏈: **03**
- 安全/合規要求無 root 無 daemon: **04 或 08**
- 大型多目標建構: **05**;受限環境建 image: **06**

### Part 2 (就是要 dind)
- 預設: **09** (宣告式,簡單);要加密: **10**
- 工具鏈也要鎖死: **11**
- **拿不到 privileged: 只能 12**
- 只是想「在容器裡跑 docker 指令」: 其實你要的是 **13 (DooD)** 或 Part 1

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

### 09 dind-service-notls: 「等到 ready」不等於「一直 ready」

**坑 1: GHA runner 會在 job 執行中途重建 service 容器**
- **症狀**: wait step 探測 `docker -H tcp://127.0.0.1:2375 info` 成功,緊接著的 build step 卻 `connection reset by peer`
- **根因**: 診斷時 `docker ps -a` 顯示 dind 容器 `Up 1 second / Created 1 second ago` — runner 中途重建了 service 容器,wait 等到的是**上一個實例**,build 連的已是新實例 (還沒就緒)
- **修法**: 不能「先等完再 build」,要把 probe+build 包進同一個 retry 迴圈 (10 次 × sleep 6): 每輪 `collect_candidates()` (127.0.0.1:2375 + `docker inspect` 取容器 bridge IP) → probe → 成功 build 才 break,並把 `DIND_HOST` 寫入 `$GITHUB_ENV` 供後續 step 用

**坑 2: 新版 dockerd 對無 TLS TCP binding 故意減速啟動**
- **症狀**: dind 日誌出現 `Binding to an IP address without --tlsverify is deprecated...Startup is intentionally being slowed down`,2375 要等好幾秒才開始聽
- **根因**: docker 官方對 `tcp://0.0.0.0:2375` 無加密端點的懲罰性延遲,逼你用 TLS
- **修法**: 同上靠 retry 吸收;要根治就改用 10 號的 TLS 模式 (2376)

**坑 3: `localhost` 在 GHA 會解析成 IPv6 `::1`**
- **症狀**: `Get "http://localhost:2375/_ping"` 連線錯誤,換 `127.0.0.1` 即通 — GHA 官方文件也建議 service 一律用 IPv4

### 12 dind-rootless: 五輪修復的完整打怪路線 (與 08 同源的深坑)

**坑 1: rootlesskit 起不来 — `fork/exec /proc/self/exe: operation not permitted`**
- **根因**: Ubuntu 24.04 `apparmor_restrict_unprivileged_userns=1`,容器內程式想建 user namespace 被 kernel 擋;`--security-opt apparmor=unconfined` 都不夠 (unconfined 也受 restrict 規則管轄)
- **修法**: 在 **host** 上寫 named AppArmor profile (`/etc/apparmor.d/dind-rootless-userns`,內容 `userns,`) 給容器 `--security-opt apparmor=dind-rootless-userns` 套用;再加 `seccomp=unconfined`、`systempaths=unconfined`

**坑 2: enforcement profile 反而擋住 exec**
- **症狀**: daemon 明明 ready (`API listen on /run/user/1000/docker.sock`),`docker exec` 進去卻 `/proc/net/ip_tables_names: Permission denied`、`docker version` 只印 Client 段
- **根因**: named profile 的空類別規則 (只寫 `userns,`) 在 enforcement 模式下等於「其他全不允許」
- **修法**: profile 加 `complain` flag (記錄不阻擋),規則只需 `userns,`

**坑 3: slirp4netns 要 `/dev/net/tun`**
- **症狀**: `failed to setup network ... ip tuntap add name tap0 ... exit status 1`
- **修法**: runner 沒這 device 就 `sudo mknod /dev/net/tun c 10 200` 自己造一個,`docker run` 帶 `--device /dev/net/tun`

**坑 4 (真因): rootlesskit `--copy-up=/run` 把 daemon socket 藏進私有 mount namespace**
- **症狀**: daemon 日誌顯示 listen 成功,容器內 `docker exec` 卻永遠連不上 `unix:///run/user/1000/docker.sock` — 與 08 坑 3 完全同構
- **根因**: docker:dind-rootless 官方 entrypoint 用 `--copy-up=/run`,socket 建在 rootlesskit child 的私有 mount ns;`docker exec` 的 process 掛在 parent ns,永遠看不到
- **修法**: **改走 TCP 2376 + TLS** — rootlesskit 的 port mapping 在 parent ns 聽 2376,憑證在 `/certs` (overlay 共享層)。`docker exec` 內 `export DOCKER_HOST=tcp://localhost:2376 DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH=/certs/client`,第 2 次探測即通。驗 rootless 證據改用 `id` + `docker info --format '{{.SecurityOptions}}'` (顯示 `rootless`、`cgroupns`)

### 通用
- runner 的 `ubuntu-latest` (Ubuntu 24.04) 上,rootless 容器技術 (podman/nerdctl/rootlesskit) 全部都要先處理 AppArmor userns 限制,podman 是唯一內建處理好的 (04 直接過)
- **dind 系列的鐵律**: 「探測成功」只是瞬間狀態,probe 和實際操作必須包在同一個 retry 迴圈;service 容器隨時可能被 runner 重建 (09)、daemon socket 可能被 rootlesskit 藏進私有 ns (08/12)
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
