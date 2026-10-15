FROM centos:7.9.2009
ARG KVER
COPY ci/CentOS-Vault.repo /etc/yum.repos.d/E610-Vault.repo
RUN test -n "$KVER" && \
    yum --disablerepo='*' --enablerepo=c7-base,c7-updates,c7-extras \
        --setopt=installonly_limit=0 -y install \
        gcc make binutils perl patch tar gzip xz kmod which \
        elfutils-libelf-devel "kernel-${KVER}" "kernel-devel-${KVER}" && \
    yum clean all
ENV KVER=${KVER}
WORKDIR /work
ADD https://github.com/intel/ethernet-linux-ixgbe/releases/download/v6.4.5/ixgbe-6.4.5.tar.gz /input/ixgbe-6.4.5.tar.gz
COPY patches /input/patches
COPY ci/build.sh /usr/local/bin/build-ixgbe
ENTRYPOINT ["/bin/bash", "/usr/local/bin/build-ixgbe"]
