# scratch + 靜態 binary:無 base layer = 無鏡像層 chown 問題。
# 這是無 subuid 環境 (HPC / 受限 CI / 單映射 rootless) 的標準 build 姿勢。
# 注意: scratch 無 shell,不能 RUN;用 COPY --chmod 免 chmod 步驟。
FROM scratch
LABEL org.opencontainers.image.title="hello-no-dind-scratch"
COPY --chmod=755 hello /hello
ENTRYPOINT ["/hello"]
