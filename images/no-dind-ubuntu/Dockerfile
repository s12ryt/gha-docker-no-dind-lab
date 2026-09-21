# no-dind-ubuntu — 「不用 Docker-in-Docker」的 Ubuntu 工具箱
#
# 一個 image 打包所有 no-dind 的 Docker 同類工具鏈:
#   - docker CLI (僅作介面相容;本工具箱測試不掛 host socket,容器內絕不起 dockerd)
#   - podman / buildah (無 daemon 建構與執行)
#   - skopeo (無 daemon 鏡像複製/轉換)
#   - nerdctl-full (nerdctl + buildctl + buildkitd + rootlesskit + slirp4netns)
#
# 原則: 容器內「絕不」執行 dockerd (那就成了 dind)。
# 由 workflow 17 實測容器內全套 no-dind 操作。

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 一口氣裝齊 apt 可得的工具 (docker.io 只用它的 CLI;daemon 不會被啟動)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
      docker.io \
      podman buildah skopeo \
      uidmap fuse-overlayfs \
      rootlesskit slirp4netns \
    && rm -rf /var/lib/apt/lists/*

# nerdctl-full 官方 tarball (含 nerdctl/buildctl/buildkitd/rootlesskit/slirp4netns/containerd)
ARG NERDCTL_VER=1.7.7
RUN curl -fsSL "https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VER}/nerdctl-full-${NERDCTL_VER}-linux-amd64.tar.gz" -o /tmp/nerdctl.tgz \
    && tar -xzf /tmp/nerdctl.tgz -C /usr/local \
    && rm -f /tmp/nerdctl.tgz

# 容器內最穩的 storage driver (不依賴 overlay 上層或 /dev/fuse)
# runroot/graphroot 必須明寫: 覆蓋預設 storage.conf 後 buildah 會報 "runroot must be set"
# (rootless 用戶執行時,podman/buildah 會自動重定位到 $HOME 與 $XDG_RUNTIME_DIR,不受此設定影響)
# ignore_chown_errors: 單映射模式 (無 subuid) 下鏡像層內其他 uid/gid (如 gid 42)
# 無法 chown 會炸 "lchown invalid argument" — 這是無 subuid 環境的官方解法 (HPC/無 root 場景)
# 注意: 值必須用「裸布爾」 true — 帶引號的字串 "true" 在部分 containers/storage
# 版本的 TOML bool 欄位解不開,整份配置會被丟掉 fallback 預設 (實測踩過)
RUN mkdir -p /etc/containers && printf '[storage]\ndriver = "vfs"\nrunroot = "/run/containers/storage"\ngraphroot = "/var/lib/containers/storage"\n\n[storage.options]\nignore_chown_errors = true\n' > /etc/containers/storage.conf

# rootless 專用非 root 帳號
# 刻意「不」設定 subuid/subgid: 實測 GHA 容器內 setuid newuidmap 寫多行映射
# 會被 kernel 拒絕 (EPERM,連 named AppArmor profile + seccomp/systempaths
# unconfined 都解不掉;單行映射的 unshare -Ur 則是通的)。
# 注意: Ubuntu 的 useradd 會依 /etc/login.defs (SUB_UID_MIN..MAX) 「自動」
# 分配 subuid/subgid 條目 (實測被配到 165536:65536) — 光不手動 echo 沒用,
# 必須在 useradd 後 sed 刪除,否則 podman 偵測到條目就走 newuidmap 多行映射 → EPERM。
# 刪光條目後 rootless podman / rootlesskit 會自動 fallback「單映射模式」
# (single uid mapping 0->1001),自行寫 uid_map 不需 newuidmap,搭配 vfs
# storage 即可完整 build/run。
RUN useradd -m -s /bin/bash toolbox \
    && sed -i '/^toolbox:/d' /etc/subuid /etc/subgid \
    && ! grep -q '^toolbox:' /etc/subuid /etc/subgid \
    && mkdir -p /home/toolbox/.config/containers \
    && printf '[storage]\ndriver = "vfs"\nrunroot = "/run/containers/storage"\ngraphroot = "/var/lib/containers/storage"\n\n[storage.options]\nignore_chown_errors = true\n' > /home/toolbox/.config/containers/storage.conf \
    && chown -R toolbox:toolbox /home/toolbox/.config \
    && echo 'toolbox subuid/subgid entries removed (single-mapping mode)'

# build 時期就把缺件擋下來
RUN for t in docker podman buildah skopeo nerdctl buildctl buildkitd rootlesskit slirp4netns; do \
      command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; \
    done && echo "no-dind toolbox 工具鏈完整"

USER toolbox
WORKDIR /home/toolbox
CMD ["/bin/bash"]
