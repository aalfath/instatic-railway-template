#!/bin/bash
# Railway start script for Instatic.
#  1. checks the generated settings and refuses to start without them;
#  2. gives the /app/storage volume to the `bun` user;
#  3. caps image-processing threads to the service's CPUs (Railway shows the
#     host's CPU count inside a 1 vCPU service);
#  4. creates the owner account from ADMIN_EMAIL / ADMIN_PASSWORD on a
#     loopback-only instance BEFORE the public port opens, so no visitor can
#     claim the site through the first-run setup page;
#  5. runs the Instatic server as `bun` (PID 1, exits non-zero on a crash).
set -euo pipefail

log() { echo "[instatic-railway] $*"; }
die() { echo "[instatic-railway] ERROR: $*" >&2; exit 1; }

STORAGE_DIR="${INSTATIC_STORAGE_DIR:-/app/storage}"
export UPLOADS_DIR="${UPLOADS_DIR:-$STORAGE_DIR/uploads}"
export SITE_NAME="${SITE_NAME:-My Instatic site}"
# Railway's edge reaches the service from these ranges; trusting them lets
# Instatic key login rate limits and audit logs on the real client IP.
export TRUSTED_PROXY_CIDRS="${TRUSTED_PROXY_CIDRS:-100.64.0.0/10,152.233.0.0/16}"

# --- 1. required settings ---------------------------------------------------
case "${DATABASE_URL:-}" in
  postgres://*|postgresql://*|sqlite:*|file:*) ;;
  "") die "DATABASE_URL is empty. It should reference the Postgres service: \${{Postgres.DATABASE_URL}}." ;;
  *) die "DATABASE_URL must be a postgres:// URL (or sqlite:/path)." ;;
esac
key_bytes=$(printf '%s' "${INSTATIC_SECRET_KEY:-}" | base64 -d 2>/dev/null | wc -c || true)
[ "$key_bytes" = "32" ] || die "INSTATIC_SECRET_KEY must be base64 for exactly 32 bytes (got ${key_bytes:-0}). Keep the template's generated value."

# Railway resolves https://${{RAILWAY_PUBLIC_DOMAIN}} to a bare "https://" when
# the service has no domain yet; drop such a value so Instatic falls back to
# RAILWAY_PUBLIC_DOMAIN instead of a broken origin.
if [ -n "${PUBLIC_ORIGIN:-}" ]; then
  case "$PUBLIC_ORIGIN" in
    http://?*|https://?*) ;;
    *) log "ignoring PUBLIC_ORIGIN='$PUBLIC_ORIGIN' (no host)"; unset PUBLIC_ORIGIN ;;
  esac
fi

# --- 2. volume ownership ----------------------------------------------------
mkdir -p "$STORAGE_DIR" "$UPLOADS_DIR"
if [ -n "$(find "$STORAGE_DIR" -xdev \( ! -user bun -o ! -group bun \) -print -quit 2>/dev/null)" ]; then
  log "giving $STORAGE_DIR to the bun user"
  chown -R bun:bun "$STORAGE_DIR"
fi

# --- 3. CPU-sized thread pools ----------------------------------------------
cpus=1
if [ -r /sys/fs/cgroup/cpu.max ]; then
  read -r quota period < /sys/fs/cgroup/cpu.max || true
  if [ "${quota:-max}" != "max" ] && [ "${period:-0}" -gt 0 ] 2>/dev/null; then
    cpus=$(( (quota + period - 1) / period ))
  else
    cpus=$(nproc 2>/dev/null || echo 2)
  fi
fi
[ "$cpus" -ge 1 ] 2>/dev/null || cpus=1
[ "$cpus" -le 4 ] || cpus=4
export VIPS_CONCURRENCY="${VIPS_CONCURRENCY:-$cpus}"
export UV_THREADPOOL_SIZE="${UV_THREADPOOL_SIZE:-$(( cpus < 2 ? 2 : cpus ))}"
export IMAGE_VARIANT_WORKER_POOL_SIZE="${IMAGE_VARIANT_WORKER_POOL_SIZE:-1}"
log "cpus=$cpus VIPS_CONCURRENCY=$VIPS_CONCURRENCY IMAGE_VARIANT_WORKER_POOL_SIZE=$IMAGE_VARIANT_WORKER_POOL_SIZE"

as_bun() { setpriv --reuid=bun --regid=bun --init-groups -- "$@"; }

# --- 4. owner account before the public port opens ---------------------------
cd /app
as_bun bun run /opt/instatic-railway/bootstrap.ts || die "first-boot owner setup failed; refusing to open the public port"

# --- 5. the server ----------------------------------------------------------
log "starting Instatic on ${HOST}:${PORT}"
exec setpriv --reuid=bun --regid=bun --init-groups -- bun run server/index.ts
