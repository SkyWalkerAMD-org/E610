FROM centos:7.9.2009
ARG KVER
COPY ci/CentOS-Vault.repo /etc/yum.repos.d/E610-Vault.repo
RUN test -n "$KVER" && \
    yum --disablerepo='*' --enablerepo=c7-base,c7-updates,c7-extras \
        --setopt=installonly_limit=0 -y install \
        "kernel-${KVER}" kmod dracut util-linux coreutils tar gzip xz cpio && \
    yum clean all
ENV KVER=${KVER}
ENTRYPOINT ["/bin/bash", "/media-test.sh"]
