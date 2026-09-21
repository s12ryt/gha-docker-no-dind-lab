FROM alpine:3.20

LABEL org.opencontainers.image.title="hello-dind"

COPY hello.sh /usr/local/bin/hello.sh
RUN chmod +x /usr/local/bin/hello.sh

ENTRYPOINT ["/usr/local/bin/hello.sh"]
