ARG MULTICHAIN_BASE_VERSION=2.3.3
ARG BUILD_DATE
ARG VCS_REF=""

FROM leodyversemilla07/multichain-base:${MULTICHAIN_BASE_VERSION}

# Re-declare build args for use in subsequent instructions (Docker resets scope after FROM)
ARG MULTICHAIN_BASE_VERSION
ARG BUILD_DATE
ARG VCS_REF

LABEL maintainer="leodyversemilla07" \
	org.opencontainers.image.created="${BUILD_DATE}" \
	org.opencontainers.image.base.name="leodyversemilla07/multichain-base" \
	org.opencontainers.image.base.version="${MULTICHAIN_BASE_VERSION}" \
	org.opencontainers.image.title="multichain-node" \
	org.opencontainers.image.version="${MULTICHAIN_BASE_VERSION}" \
	org.opencontainers.image.description="Runtime node that joins an existing MultiChain network." \
	org.opencontainers.image.source="https://github.com/leodyversemilla07/multichain-docker" \
	org.opencontainers.image.revision="${VCS_REF}" \
	org.opencontainers.image.vendor="leodyversemilla07" \
	org.opencontainers.image.documentation="https://github.com/leodyversemilla07/multichain-docker" \
	org.opencontainers.image.licenses="MIT"

# Base image already creates unprivileged user & symlink; no need to duplicate.

# Environment defaults (can be overridden at runtime)
ENV CHAIN_NAME=dockerchain \
	MASTER_HOST=masternode \
	MASTER_PORT=7447 \
	START_FLAGS="-printtoconsole -shrinkdebugfilesize" \
	RETRIES=30 \
	SLEEP_SECONDS=2

# Copy connection script (build context root -> node/connect-node.sh)
# Need root to modify /usr/local/bin permissions, then drop back to multichain.
USER root
COPY connect-node.sh /usr/local/bin/connect-node.sh
RUN chmod 0755 /usr/local/bin/connect-node.sh \
	&& chown multichain:multichain /usr/local/bin/connect-node.sh
USER multichain

EXPOSE 7447 8000

# Align with base/master healthcheck style & timing (no-op if CHAIN_NAME empty)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD test -z "$CHAIN_NAME" || multichain-cli "$CHAIN_NAME" getinfo > /dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/connect-node.sh"]