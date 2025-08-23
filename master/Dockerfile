ARG MULTICHAIN_BASE_VERSION=2.3.3
ARG BUILD_DATE
ARG VCS_REF=""
# Optional: provide a digest for stronger pinning (uncomment and set)
# ARG MULTICHAIN_BASE_DIGEST="sha256:..."
FROM leodyversemilla07/multichain-base:${MULTICHAIN_BASE_VERSION}

# Re-declare build args scope after FROM
ARG MULTICHAIN_BASE_VERSION
ARG BUILD_DATE
ARG VCS_REF

LABEL maintainer="leodyversemilla07" \
	org.opencontainers.image.base.name="leodyversemilla07/multichain-base" \
	org.opencontainers.image.base.version="${MULTICHAIN_BASE_VERSION}" \
	org.opencontainers.image.title="multichain-master" \
	org.opencontainers.image.version="${MULTICHAIN_BASE_VERSION}" \
	org.opencontainers.image.description="Creator (master) node image (generates chain config, delegates startup to base entrypoint)" \
	org.opencontainers.image.source="https://github.com/leodyversemilla07/multichain-docker" \
	org.opencontainers.image.created="${BUILD_DATE}" \
	org.opencontainers.image.revision="${VCS_REF}" \
	org.opencontainers.image.vendor="leodyversemilla07" \
	org.opencontainers.image.documentation="https://github.com/leodyversemilla07/multichain-docker" \
	org.opencontainers.image.licenses="MIT"

# Runtime defaults (overridable at run time). CHAIN_NAME intentionally unset to force explicit choice unless provided at runtime.
# hadolint ignore=DL3045 (no secret material baked; RPC password generated at runtime)
ENV CHAIN_NAME="" \
	RPC_USER=multichainrpc \
	RPC_ALLOWIP=127.0.0.1 \
	RPC_PORT=8000 \
	AUTO_CREATE=1

# Preserve original base entrypoint then add master-specific wrapper.
# Need root to copy into /usr/local/bin because base image set USER multichain.
USER root
RUN cp /usr/local/bin/entrypoint.sh /usr/local/bin/entrypoint.base.sh \
	&& sha256sum /usr/local/bin/entrypoint.base.sh | awk '{print $1}' > /usr/local/bin/entrypoint.base.sh.sha256
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/entrypoint.base.sh \
	&& chown multichain:multichain /usr/local/bin/entrypoint.base.sh /usr/local/bin/entrypoint.base.sh.sha256 /usr/local/bin/entrypoint.sh

# Install lightweight tooling needed for runtime healthchecks (curl/jq). Keep image small and clean caches.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends curl jq \
	&& rm -rf /var/lib/apt/lists/*
USER multichain

# Provide hash as env for optional runtime verification
ENV BASE_ENTRYPOINT_SHA256_FILE=/usr/local/bin/entrypoint.base.sh.sha256

EXPOSE 7447 8000

# Use exec-form healthcheck for consistent behavior; no-op when CHAIN_NAME is empty
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
	CMD ["sh", "-c", "test -z \"$CHAIN_NAME\" || multichain-cli \"$CHAIN_NAME\" getinfo >/dev/null 2>&1 || exit 1"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
