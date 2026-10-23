FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    initramfs-tools kmod zstd mokutil util-linux ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY ubuntu24-e610/test/run.sh /run-tests.sh
ENTRYPOINT ["bash", "/run-tests.sh"]
