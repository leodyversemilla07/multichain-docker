ARG MULTICHAIN_NODE_VERSION=2.3.3
FROM leodyversemilla07/multichain-node:${MULTICHAIN_NODE_VERSION}

# Build-time arguments
ARG BUILD_DATE
ARG MULTICHAIN_EXPLORER_REF=master

# OCI / metadata labels
LABEL maintainer="leodyversemilla07" \
    org.opencontainers.image.title="multichain-explorer-2" \
    org.opencontainers.image.description="MultiChain Explorer (v2, Python 3 implementation)" \
    org.opencontainers.image.source="https://github.com/leodyversemilla07/multichain-docker" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.version="${MULTICHAIN_EXPLORER_REF}" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.documentation="https://github.com/MultiChain/multichain-explorer-2"

# Upstream node image sets USER to multichain; elevate to root for package installation.
USER root

# Use Python 3 and install the v2 explorer (multichain-explorer-2) via pip3.
# Install dependencies & explorer in one layer to reduce image size.
RUN set -eux; \
    mkdir -p /var/lib/apt/lists/partial; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3 python3-dev python3-pip sqlite3 libsqlite3-dev curl ca-certificates wget build-essential jq; \
    # Download the multichain-explorer-2 archive and install with pip3 so dependencies are resolved automatically
    cd /root; \
    wget -q "https://github.com/MultiChain/multichain-explorer-2/archive/${MULTICHAIN_EXPLORER_REF}.tar.gz" -O explorer.tar.gz; \
    tar -xzf explorer.tar.gz; \
    rm -f explorer.tar.gz; \
    mv /root/multichain-explorer-2-* /opt/multichain-explorer-2; \
    chown -R multichain:multichain /opt/multichain-explorer-2; \
    # Note: the upstream multichain-explorer-2 source bundle does not include
    # packaging metadata (setup.py / pyproject.toml) so it isn't pip-installable.
    # We keep the source under /opt and load it with PYTHONPATH at runtime.
    apt-get purge -y build-essential; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /root/.cache

# Configuration & service script
COPY ./run-services.sh /home/multichain/run-services.sh
# Ensure explorer source is available in the image at runtime
RUN mkdir -p /opt && chown multichain:multichain /opt || true
# Ensure executable permission and ownership (avoid /root which is 700 and inaccessible to user)
RUN chmod 0755 /home/multichain/run-services.sh \
    && chown multichain:multichain /home/multichain/run-services.sh

# Set a sensible working directory for the runtime image. Keep owned by the unprivileged user.
RUN mkdir -p /home/multichain && chown multichain:multichain /home/multichain || true
WORKDIR /home/multichain

# Runtime environment defaults (override at docker run / compose level)
ENV GENERATE_EXPLORER_CONF=1 \
    EXPLORER_PORT=2750 \
    EXPLORER_BIND=0.0.0.0 \
    START_FLAGS="-shrinkdebugfilesize" \
    COMMIT_BYTES=100000 \
    EXPLORE_FLAGS="" \
    RETRIES=60 \
    SLEEP_SECONDS=2 \
    RPC_PORT=8000 \
    PYTHONUNBUFFERED=1

EXPOSE 2750

HEALTHCHECK --interval=45s --timeout=5s --retries=5 CMD curl -fsS http://localhost:2750/ >/dev/null || exit 1

# Drop back to unprivileged user for runtime
USER multichain

# Override upstream ENTRYPOINT (connect-node.sh) to run explorer services directly as non-root.
ENTRYPOINT ["/bin/bash", "/home/multichain/run-services.sh"]