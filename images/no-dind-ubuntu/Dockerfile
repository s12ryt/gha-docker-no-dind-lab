# no-dind-ubuntu — 「不用 Docker-in-Docker」的 Ubuntu 工具箱
#
# 一個 image 打包所有 no-dind 的 Docker 同類工具鏈:
#   - docker CLI (供 DooD: 掛 host socket 操作外部 daemon,容器內絕不起 dockerd)
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
RUN mkdir -p /etc/containers && printf '[storage]\ndriver = "vfs"\n' > /etc/containers/storage.conf

# rootless 專用非 root 帳號 (subuid/subgid 供 user namespace 映射)
RUN useradd -m -s /bin/bash toolbox \
    && echo 'toolbox:100000:65536' >> /etc/subuid \
    && echo 'toolbox:100000:65536' >> /etc/subgid

# build 時期就把缺件擋下來
RUN for t in docker podman buildah skopeo nerdctl buildctl buildkitd rootlesskit slirp4netns; do \
      command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; \
    done && echo "no-dind toolbox 工具鏈完整"

USER toolbox
WORKDIR /home/toolbox
CMD ["/bin/bash"]
