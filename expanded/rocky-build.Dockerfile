ARG MAJOR=9
FROM rockylinux/rockylinux:${MAJOR}
RUN dnf install -y gcc make elfutils-libelf-devel openssl-devel openssl kmod cpio rpm-build diffutils findutils \
    && dnf clean all
