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
Docker 相容 CLI 直連 containerd。rootful 用系統 containerd (`sudo nerdctl`);rootless 需 `uidmap`+`containerd-rootless-setuptool.sh install`。

## 推薦

- 一般 CI: **01**;要 DB: **01+02**;固定工具鏈: **03**
- 安全/合規要求無 root 無 daemon: **04 或 08**
- 大型多目標建構: **05**;受限環境建 image: **06**

## 踩坑紀錄

(實測後更新)

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
