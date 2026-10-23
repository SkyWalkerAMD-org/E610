ARG IMAGE=ubuntu:22.04
FROM ${IMAGE}
ENV DEBIAN_FRONTEND=noninteractive
RUN if command -v apt-get; then \
      apt-get update && apt-get install -y --no-install-recommends initramfs-tools kmod zstd mokutil util-linux ca-certificates && rm -rf /var/lib/apt/lists/*; \
    else \
      dnf install -y dracut kmod mokutil util-linux tar gzip xz cpio findutils diffutils && dnf clean all; \
    fi
ENTRYPOINT ["bash"]
