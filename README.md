# GitHub Actions Docker 策略驗證場 — 沒有 dind 的 12 種姿勢 + dind 對照組 5 種

> Repo: https://github.com/s12ryt/gha-docker-no-dind-lab
> 所有 workflow 皆 `workflow_dispatch` 手動觸發、ubuntu-latest。

## 三大系列

- **主線 Part 1 (01-08 + 14-16, 共 11 個): 沒有 Docker-in-Docker 也能用 Docker + Docker 同類方案** — 原則: 絕不用 `docker:dind`;其中 14-16 更進一步在 **dockerd 停用** 狀態下實測 (buildah / skopeo / buildkit-daemonless),證明「沒有 docker 也能做 docker 的事」
- **主線 Part 4 (17, 總成): 自製 no-dind Ubuntu 工具箱** — `images/no-dind-ubuntu/Dockerfile` 打包 9 個工具 (docker CLI / podman / buildah / skopeo / nerdctl / buildctl / buildkitd / rootlesskit / slirp4netns),在**容器內**做完整 no-dind 實測,**全程不掛 host docker socket** (自給自足 daemonless)
- **對照組 Part 2 (09-13, 附錄): 就是要用 Docker-in-Docker 時的正確姿勢** — dind service / TLS / container job / rootless / DooD

## 為什麼優先不要 Docker-in-Docker?

- dind 需要 `--privileged`,安全性差、租用環境常被禁止
- GitHub-hosted runner **本來就有完整的 host Docker daemon**,直接用即可
- dind 有巢狀儲存層效能損耗、IPC/網路複雜、快取難共用等問題

## 什麼時候「真的」需要 dind? (對照組 Part 2 存在的意義)

- 需要**完全隔離的 daemon 狀態** (build 之間互相污染、副作用測試)
- 需要**測試 docker 本身**或編排 dind 叢集 (如 CI for docker tools)
- 需要**可控的 daemon 版本/組態** (host daemon 不允許變更)
- 非 root、不給 privileged 的環境 → **12 rootless dind** 是唯一解

## Part 1 策略總覽 (01-08 + 14-16, 不用 dind / Docker 同類)

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
| 14 | buildah-rootless | daemonless 建構+執行 | ❌ (實測停用) | ❌ | 無 dockerd 的 Dockerfile build/run,產 docker-archive |
| 15 | skopeo-daemonless | 鏡像複製/格式轉換 | ❌ (實測停用) | ❌ | pull/push/inspect,tar 互轉,連 build 都不需要 |
| 16 | buildkit-daemonless | 一次性 buildkitd | ❌ (實測停用) | ❌ | 零常駐: rootless buildkitd 起→build→收,產 OCI tar |

## Part 4 策略總覽 (17, 總成: no-dind Ubuntu 工具箱)

| # | Workflow | 模式 | 掛 host socket? | 容器內測試 | 適用場景 |
|---|----------|------|:---:|---|----------|
| 17 | no-dind-ubuntu-toolbox | 自製工具箱 image (9 工具) → 容器內實測 | ❌ (全程不掛) | skopeo / buildah / podman rootless / buildkit daemonless | 把整套 no-dind 工具鏈打包成可攜 image,進任何環境都能 build 不靠 dind |

## Part 2 策略總覽 (09-13, 對照組: 就是用 dind)

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

### 14 Buildah (Rootless, Daemonless)
`apt install buildah` 即得 Dockerfile 建構能力,無 daemon、無 root;`bud --isolation chroot` 在 runner 上最穩。本 workflow 實測**全程停用 dockerd** (`systemctl stop docker.service docker.socket` + `pgrep` 驗證),仍可 build → `buildah from`/`buildah run` 執行容器 → 匯出 `docker-archive:` tar 給 `docker load` 用。

### 15 Skopeo (Daemonless 鏡像操作)
不 build、只搬鏡像: `docker://` ↔ `dir:` ↔ `docker-archive:` ↔ `oci-archive:` 全格式互轉,全程無 daemon。實測在 dockerd 停用下直接從 registry 拉鏡像、inspect metadata、產出 `docker load` 可用的 tar。鏡像搬運/同步/離線分發的首選。

### 16 BuildKit Daemonless (一次性 buildkitd)
官方 buildkit tarball (`buildctl`+`buildkitd`) + apt 補 `rootlesskit`/`slirp4netns`,rootless 手動起 buildkitd → `buildctl build --output type=oci` → **trap 收掉 daemon,零常駐**。與 05 的差別: 05 依賴 host docker daemon 起 buildkitd 容器,16 完全不碰 docker。

### 17 No-DinD Ubuntu Toolbox (Part 4 總成)
自製 `images/no-dind-ubuntu/Dockerfile`: ubuntu:24.04 打包 docker CLI / podman / buildah / skopeo / nerdctl / buildctl / buildkitd / rootlesskit / slirp4netns 九件套,非 root 帳號 `toolbox` 為預設使用者。Workflow 在**容器內**做完整 no-dind 實測,**全程不掛 host docker socket**: skopeo 拉鏡像、buildah build+run、podman rootless build+run、一次性 rootless buildkitd 產 OCI tar。容器內 rootless 的地雷密度遠高於 host (單映射 user namespace),全部解法見踩坑 17。

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
| 12 | dind-rootless | ✅ (修6輪) | named AppArmor + /dev/net/tun + TCP/TLS 三重解 |
| 13 | dood-socket-mount | ✅ | 一次過 |
| 14 | buildah-rootless | ✅ | 一次過;dockerd 停用下 build+run+匯出 docker-archive |
| 15 | skopeo-daemonless | ✅ | 一次過;dockerd 停用下全格式轉換 |
| 16 | buildkit-daemonless | ✅ (修2輪) | asset 檔名點號 + tarball 不含 rootlesskit 要 apt 補 |
| 17 | no-dind-ubuntu-toolbox | ✅ (修15輪) | 容器內 rootless 單映射全解: sed 刪 subuid + scratch 樣本 + unshare 跑 buildkitd |

## 推薦

### Part 1 (不需要 dind)
- 一般 CI: **01**;要 DB: **01+02**;固定工具鏈: **03**
- 安全/合規要求無 root 無 daemon: **04 或 08**;無 dockerd 還要 build+run: **14**
- 大型多目標建構: **05**;受限環境建 image: **06**;零常駐一次性建構: **16**
- 只需搬鏡像/格式轉換 (連 build 都不用): **15**
- 要把整組工具鏈帶著走、進任何容器環境都能幹活: **17 (工具箱)**

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

### 16 buildkit-daemonless: 官方 tarball 的兩個安裝坑

**坑 1: BuildKit release asset 檔名用「點號」分隔,不是連字號**
- **症狀**: 從 `moby/buildkit` latest release 下載 `buildkit-vX.Y.Z-linux-amd64.tar.gz` (連字號) → 404
- **修法**: 正確檔名是 `buildkit-v0.33.0.linux-amd64.tar.gz` — version 與 os-arch 之間是**點號**

**坑 2: 官方 tarball 只含 buildctl/buildkitd,不含 rootlesskit/slirp4netns**
- **症狀**: `rootlesskit: command not found`
- **修法**: `sudo apt-get install -y rootlesskit slirp4netns` (Ubuntu 24.04 universe repo 有)。AppArmor profile 路徑要對準實際 binary: apt 裝的在 `/usr/bin/rootlesskit` → profile 名 `usr.bin.rootlesskit`;tarball 解到 `/usr/local/bin/buildkitd` → profile 名 `usr.local.bin.buildkitd`。socket 放 `$XDG_RUNTIME_DIR` 下、絕不 `--copy-up=/run` (同 08 坑 3)

### 17 no-dind-ubuntu-toolbox: 容器內 rootless 單映射生存指南 (15 輪修復的精華)

容器內 (非特權 docker 容器) 跑 rootless 容器工具,地雷密度遠高於 host 上。以下每個坑都是實測炸出來的:

**坑 1: `skopeo inspect dir:` 的輸出沒有 repo name**
- **症狀**: `skopeo copy docker://alpine:3.20 dir:/tmp/alpine` 成功,但 `skopeo inspect dir:/tmp/alpine | grep -qi alpine` 永遠失敗
- **根因**: `dir:` 來源的 inspect JSON 中 `Name` 為空、`RepoTags` 為 null — 輸出裡根本沒有 "alpine" 字樣
- **修法**: 改驗 JSON 結構欄位,如 `grep -q '"Os"'`

**坑 2: buildah `runroot must be set`**
- **症狀**: `buildah bud` 報 `failed to get container config: runroot must be set`
- **根因**: Dockerfile 裡用 printf 覆寫 `/etc/containers/storage.conf` 只寫了 `driver=vfs`,弄丟了 Ubuntu 預設配置的 `runroot`/`graphroot`
- **修法**: storage.conf 三行都要明寫: `driver = "vfs"` + `runroot = "..."` + `graphroot = "..."`

**坑 3: docker 預設 seccomp 擋 `unshare(CLONE_NEWUSER)`**
- **症狀**: 容器內 buildah (root+chroot) 報 `unshare: operation not permitted`;host 上同指令沒事
- **根因**: 容器無 CAP_SYS_ADMIN,docker 預設 seccomp profile 擋 user namespace 相關 syscall;host 的 AppArmor userns 限制 (同 08/12) 疊加
- **修法**: `docker run` 要同時給 `--security-opt seccomp=unconfined` **和** host 預載入的 named AppArmor profile (`--security-opt apparmor=no-dind-toolbox-userns`,內容 `userns,` + complain flag,同 12 踩坑)

**坑 4: Ubuntu `useradd` 會自動配 subuid/subgid — 光不手動 echo 沒用**
- **症狀**: Dockerfile 刪了 `echo 'toolbox:...' >> /etc/subuid`,容器內 `cat /etc/subuid` 仍見 `toolbox:165536:65536`
- **根因**: Ubuntu 的 useradd 依 `/etc/login.defs` (SUB_UID_MIN..MAX) **自動分配** subuid/subgid (基礎映像的 ubuntu 用戶先佔了 100000 起頭段)
- **修法**: `RUN useradd -m toolbox && sed -i '/^toolbox:/d' /etc/subuid /etc/subgid && ! grep -q '^toolbox:' /etc/subuid /etc/subgid`

**坑 5: newuidmap 多行映射 EPERM → 走「單映射模式」**
- **症狀**: `newuidmap: write to uid_map failed: Operation not permitted` (setuid bit 在、CapEff 有 CAP_SETUID、NoNewPrivs=0 都正常,仍被拒)
- **關鍵診斷**: `unshare -Ur true` (單行映射) 成功;newuidmap 寫**多行** subuid 映射失敗 — GHA 容器環境只放行 kernel 直接寫的單行映射
- **修法**: 就是坑 4 的 sed 刪條目 — podman/buildah 無 subuid 條目時自動 fallback 單映射 (`Using rootless single mapping into the namespace`)

**坑 6: 單映射下 pull/build 鏡像層 chown EINVAL — 根治 = scratch + 靜態 binary**
- **症狀**: `While applying layer: potentially insufficient UIDs or GIDs available in user namespace (requested 0:42 for /etc/shadow): lchown ... invalid argument`
- **根因**: 單映射只有一個 uid 可用,鏡像層內其他 uid/gid (如 alpine gid 42) 無法 chown。`ignore_chown_errors` 救不了: **vfs driver 根本不支援此選項** (直接報錯 `vfs driver does not support ignore_chown_errors`),且 TOML 值必須字串型 (裸 bool 會炸整份配置連帶其他測試陪葬)
- **修法**: 樣本改 `FROM scratch` + `COPY --chmod=755` 靜態 binary (`gcc -static` 編、輸出同訊息) — 無 base layer = 無 chown 問題,這是無 subuid 環境 (HPC/受限 CI) 的標準 build 姿勢

**坑 7: rootless storage.conf 必須指使用者可寫路徑**
- **症狀**: `mkdir /var/lib/containers: permission denied`
- **根因**: rootless podman 讀到配置裡**明確寫死**的 `graphroot=/var/lib/containers` 就不自動重定位到 `$HOME`
- **修法**: home 份 `/home/toolbox/.config/containers/storage.conf` 指定 `runroot = "/run/user/1000/containers"`、`graphroot = "/home/toolbox/.local/share/containers/storage"` (/etc 份保留給 root 用)

**坑 8: podman build 完 run 找不到鏡像**
- **症狀**: `short-name "hello-..." did not resolve ... no unqualified-search registries`
- **修法**: 鏡像名一律帶 `localhost/` 前綴 (podman build -t 的完整形式),run 就不會去 registry 撈

**坑 9: rootlesskit 硬性要求 /etc/subuid — 容器內棄用,改 unshare**
- **症狀**: `rootlesskit: failed to compute uid/gid map: No subuid ranges found for user 1001 ("toolbox")` — rootlesskit 沒有 podman 那種單映射 fallback (官方 README 明載 requires subuid,也無 --attach-userns/--uid-mapping 可用)
- **修法**: buildkitd rootless 的真正前提只是「**mapped root in a user namespace**」— `unshare --user --map-root-user --mount` 直接達成;配 `--oci-worker-snapshotter native` (純 userspace,免掛 overlay,避開容器內 nested overlay);scratch 樣本無需網路,slirp4netns 整組免了。一輪就綠

### 通用
- runner 的 `ubuntu-latest` (Ubuntu 24.04) 上,rootless 容器技術 (podman/nerdctl/rootlesskit) 全部都要先處理 AppArmor userns 限制,podman 是唯一內建處理好的 (04 直接過)
- **dind 系列的鐵律**: 「探測成功」只是瞬間狀態,probe 和實際操作必須包在同一個 retry 迴圈;service 容器隨時可能被 runner 重建 (09)、daemon socket 可能被 rootlesskit 藏進私有 ns (08/12)
- 14/15/16 的「停用 dockerd」step (`sudo systemctl stop docker.service docker.socket` + `pgrep dockerd` 確認已死) 是「**沒有 docker 也能做 docker 的事**」的鐵證模式,之後每個 step 都在無 daemon 狀態下完成,可直接抄
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
