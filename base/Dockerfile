## MultiChain base image (light, non-root, foreground run)
## Build: docker build --build-arg MULTICHAIN_VERSION=2.3.3 -t multichain-base:2.3.3 ./base
FROM ubuntu:22.04

# Build-time arguments
ARG MULTICHAIN_VERSION=2.3.3
ARG MULTICHAIN_SHA256=""        # Optional: provide official tarball hash to enforce integrity
ARG BUILD_DATE
ARG VCS_REF=""                  # Optional: git commit sha passed in by CI
ARG MULTICHAIN_UID=1000
ARG MULTICHAIN_GID=1000
ARG REQUIRE_HASH=1                # Integrity enforced by default (set to 0 ONLY for local dev)
ARG MULTICHAIN_DOWNLOAD_BASE="https://www.multichain.com/download" # Override for mirror/self-hosting

LABEL org.opencontainers.image.title="multichain-base" \
    org.opencontainers.image.version="${MULTICHAIN_VERSION}" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${VCS_REF}" \
    org.opencontainers.image.source="https://github.com/leodyversemilla07/multichain-docker" \
    org.opencontainers.image.vendor="leodyversemilla07" \
    org.opencontainers.image.description="MultiChain base image (binaries + non-root entrypoint, chain auto-create)" \
    maintainer="leodyversemilla07" \
    org.opencontainers.image.documentation="https://github.com/leodyversemilla07/multichain-docker" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.base.name="ubuntu:22.04"

# Runtime configuration
# CHAIN_NAME required unless a custom command is passed
ENV CHAIN_NAME="" \
    START_FLAGS="-printtoconsole -shrinkdebugfilesize" \
    HOME=/home/multichain

WORKDIR /tmp

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates wget tar; \
    # Require explicit SHA when REQUIRE_HASH=1 to avoid silent installs in CI
    if [ "${REQUIRE_HASH}" = "1" ] && [ -z "${MULTICHAIN_SHA256}" ]; then \
    echo "[FATAL] MULTICHAIN_SHA256 required but not provided (set REQUIRE_HASH=0 to bypass)" >&2; exit 2; \
    fi; \
    wget -q "${MULTICHAIN_DOWNLOAD_BASE}/multichain-${MULTICHAIN_VERSION}.tar.gz"; \
    if [ -n "${MULTICHAIN_SHA256}" ]; then \
    echo "${MULTICHAIN_SHA256}  multichain-${MULTICHAIN_VERSION}.tar.gz" | sha256sum -c -; \
    else \
    echo "[INFO] Skipping SHA256 verification (MULTICHAIN_SHA256 empty)"; \
    fi; \
    tar -xzf multichain-${MULTICHAIN_VERSION}.tar.gz; \
    install -m 0755 multichain-${MULTICHAIN_VERSION}/multichaind /usr/local/bin/multichaind; \
    install -m 0755 multichain-${MULTICHAIN_VERSION}/multichain-cli /usr/local/bin/multichain-cli; \
    install -m 0755 multichain-${MULTICHAIN_VERSION}/multichain-util /usr/local/bin/multichain-util; \
    rm -rf multichain-${MULTICHAIN_VERSION} multichain-${MULTICHAIN_VERSION}.tar.gz; \
    groupadd -g ${MULTICHAIN_GID} multichain; \
    useradd -m -u ${MULTICHAIN_UID} -g ${MULTICHAIN_GID} -s /usr/sbin/nologin multichain; \
    mkdir -p /home/multichain/.multichain; \
    chown -R ${MULTICHAIN_UID}:${MULTICHAIN_GID} /home/multichain; \
    # Make root's multichain dir a symlink to the service account (idempotent)
    ln -sf /home/multichain/.multichain /root/.multichain; \
    # Purge only wget (leave tar: required by dpkg, removing causes dependency breakage)
    apt-get purge -y --auto-remove wget; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /

VOLUME ["/home/multichain/.multichain"]

EXPOSE 7447 8000

# Use exec form to avoid shell-specific differences; keep behavior: skip when CHAIN_NAME unset
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ["sh", "-c", "test -z \"$CHAIN_NAME\" || multichain-cli \"$CHAIN_NAME\" getinfo >/dev/null 2>&1 || exit 1"]

COPY mc-common.sh /usr/local/bin/mc-common.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/mc-common.sh \
    && chown multichain:multichain /usr/local/bin/entrypoint.sh /usr/local/bin/mc-common.sh

USER multichain
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# Allow passing ad-hoc args (e.g., docker run image multichain-cli <chain> getinfo)
CMD []
