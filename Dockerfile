# Instatic for Railway: the official image, pinned by version and digest.
# Bump both the tag and the digest together, and add a CHANGELOG.md entry.
FROM ghcr.io/corebunch/instatic:0.0.23@sha256:ca64fbd5928c652fb2b5fa21104d2f7bb451c81495f9b5d692e30e75e1037953

# The start script runs as root only long enough to give the Railway volume
# (mounted root-owned) to the image's `bun` user, then drops to `bun`.
USER root

ENV NODE_ENV=production \
    PORT=8080 \
    HOST=0.0.0.0 \
    STATIC_DIR=/app/dist \
    UPLOADS_DIR=/app/storage/uploads \
    MALLOC_ARENA_MAX=2

COPY --chmod=755 start.sh /usr/local/bin/instatic-railway-start
COPY --chmod=644 bootstrap.ts /opt/instatic-railway/bootstrap.ts

WORKDIR /app
ENTRYPOINT ["/usr/local/bin/instatic-railway-start"]
