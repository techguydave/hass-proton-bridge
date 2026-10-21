ARG BUILD_FROM
FROM ${BUILD_FROM}

RUN apt-get update \
    && apt-get install -y --no-install-recommends tmux ttyd nginx expect jq curl \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /root \
    && ln -s /data/home /root

COPY rootfs /
RUN chmod +x /usr/local/bin/*.sh /usr/local/bin/login.exp

ENTRYPOINT ["bash", "/usr/local/bin/run.sh"]
