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
RUN mkdir -p /etc/containers && printf '[storage]\ndriver = "vfs"\nrunroot = "/run/containers/storage"\ngraphroot = "/var/lib/containers/storage"\n' > /etc/containers/storage.conf

# rootless 專用非 root 帳號
# 刻意「不」設定 subuid/subgid: 實測 GHA 容器內 setuid newuidmap 寫多行映射
# 會被 kernel 拒絕 (EPERM,連 named AppArmor profile + seccomp/systempaths
# unconfined 都解不掉;單行映射的 unshare -Ur 則是通的)。
# rootless podman / rootlesskit 偵測不到 subuid 條目時,會自動 fallback
# 「單映射模式」(single uid mapping 0->1001),自行寫 uid_map 不需 newuidmap,
# 搭配 vfs storage 即可完整 build/run。
RUN useradd -m -s /bin/bash toolbox

# build 時期就把缺件擋下來
RUN for t in docker podman buildah skopeo nerdctl buildctl buildkitd rootlesskit slirp4netns; do \
      command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; \
    done && echo "no-dind toolbox 工具鏈完整"

USER toolbox
WORKDIR /home/toolbox
CMD ["/bin/bash"]
