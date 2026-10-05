#!/bin/sh
set -eu

# Next.js standalone binds to $HOSTNAME. Kubernetes sets HOSTNAME to the pod
# name, so bind explicitly (override with BIND_HOST if needed).
export HOSTNAME="${BIND_HOST:-0.0.0.0}"

cmd="${1:-serve}"

case "$cmd" in
  serve)
    case "${MIGRATE_ON_START:-true}" in
      true | 1 | yes) node /app/docker/migrate.mjs ;;
    esac
    exec node /app/server.js
    ;;
  migrate)
    exec node /app/docker/migrate.mjs
    ;;
  *)
    exec "$@"
    ;;
esac
