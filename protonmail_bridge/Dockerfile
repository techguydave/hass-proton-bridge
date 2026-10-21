FROM dancwilliams/protonmail-bridge:v3.27.1-4

ARG BUILD_ARCH
ARG TTYD_VERSION=1.7.7

# ttyd is not packaged in Debian bookworm; use the pinned upstream static binary.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tmux nginx expect jq curl \
    && rm -rf /var/lib/apt/lists/* \
    && case "${BUILD_ARCH}" in \
         amd64)   T=x86_64;  SUM=8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55 ;; \
         aarch64) T=aarch64; SUM=b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165 ;; \
         *) echo "unsupported arch: ${BUILD_ARCH}" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /usr/local/bin/ttyd \
         "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${T}" \
    && echo "${SUM}  /usr/local/bin/ttyd" | sha256sum -c - \
    && chmod +x /usr/local/bin/ttyd \
    && rm -rf /root \
    && ln -s /data/home /root

COPY rootfs /
RUN chmod +x /usr/local/bin/*.sh /usr/local/bin/login.exp

ENTRYPOINT ["bash", "/usr/local/bin/run.sh"]
