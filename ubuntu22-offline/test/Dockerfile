FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    initramfs-tools kmod zstd mokutil util-linux ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY ubuntu22-offline/test/run.sh /run-tests.sh
ENTRYPOINT ["bash", "/run-tests.sh"]
