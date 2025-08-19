ARG MULTICHAIN_NODE_VERSION=2.3.3
FROM leodyversemilla07/multichain-node:${MULTICHAIN_NODE_VERSION}

# Build-time arguments
ARG BUILD_DATE
ARG MULTICHAIN_EXPLORER_REF=master

# OCI / metadata labels
LABEL maintainer="leodyversemilla07" \
    org.opencontainers.image.title="multichain-explorer" \
    org.opencontainers.image.description="MultiChain Explorer (legacy Python implementation)" \
    org.opencontainers.image.source="https://github.com/leodyversemilla07/multichain-docker" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.version="${MULTICHAIN_EXPLORER_REF}" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.documentation="https://github.com/MultiChain/multichain-explorer"

# Upstream node image sets USER to multichain; elevate to root for package installation.
USER root

# NOTE: This still uses legacy Python 2 packages from upstream image; migration to Python 3 recommended.
# Install dependencies & explorer in one layer to reduce image size.
RUN set -eux; \
    mkdir -p /var/lib/apt/lists/partial; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python2 python2-dev sqlite3 libsqlite3-dev curl ca-certificates wget build-essential; \
    ln -sf /usr/bin/python2 /usr/bin/python; \
    wget -q https://bootstrap.pypa.io/pip/2.7/get-pip.py -O /tmp/get-pip.py; \
    python2 /tmp/get-pip.py; \
    # ubjson==0.16.1 no longer published for Python 2; omit (explorer does not require it). \
    pip install --no-cache-dir pycrypto; \
    # Install ubjson from source archive (PyPI wheel removed for Python 2) \
    pip install --no-cache-dir https://github.com/Iotic-Labs/py-ubjson/archive/refs/tags/v0.16.1.tar.gz; \
    cd /root; \
    wget -q "https://github.com/MultiChain/multichain-explorer/archive/${MULTICHAIN_EXPLORER_REF}.tar.gz" -O explorer.tar.gz; \
    tar -xzf explorer.tar.gz; \
    rm -f explorer.tar.gz; \
    cd /root/multichain-explorer-*; \
    python2 setup.py install; \
    apt-get purge -y build-essential; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /root/.cache /tmp/get-pip.py

# Configuration & service script
COPY ./explorer.conf /home/multichain/explorer.conf
COPY ./run-services.sh /home/multichain/run-services.sh
# Ensure executable permission and ownership (avoid /root which is 700 and inaccessible to user)
RUN chmod 0755 /home/multichain/run-services.sh \
    && chown multichain:multichain /home/multichain/run-services.sh /home/multichain/explorer.conf

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