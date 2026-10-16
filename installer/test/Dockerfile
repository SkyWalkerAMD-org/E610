FROM centos:7.9.2009
ARG KVER
COPY ci/CentOS-Vault.repo /etc/yum.repos.d/E610-Vault.repo
RUN test -n "$KVER" && \
    yum --disablerepo='*' --enablerepo=c7-base,c7-updates,c7-extras \
        --setopt=installonly_limit=0 -y install \
        "kernel-${KVER}" kmod dracut util-linux coreutils tar gzip xz cpio && \
    yum clean all
ENV KVER=${KVER}
ADD https://github.com/skywalkeramd-org/E610/releases/download/v6.4.5-centos7.9-r1/E610-CentOS7.9-adaptation.tar.gz /fixture.tar.gz
COPY installer /input/installer
COPY installer/test/run.sh /input/test-installer.sh
ENTRYPOINT ["/bin/bash", "/input/test-installer.sh"]
