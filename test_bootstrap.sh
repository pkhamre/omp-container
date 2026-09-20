#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sh -n "$ROOT_DIR/bootstrap.sh" "$ROOT_DIR/bin/omp-container"
grep -F 'collect_ldd' "$ROOT_DIR/scripts/collect-runtime-deps.sh" >/dev/null
grep -F 'ANTHROPIC_API_KEY' "$ROOT_DIR/bootstrap.sh" >/dev/null
grep -F 'CLOUDFLARE_ACCOUNT_ID' "$ROOT_DIR/bootstrap.sh" >/dev/null
grep -F 'GOOGLE_APPLICATION_CREDENTIALS' "$ROOT_DIR/bootstrap.sh" >/dev/null
echo "bootstrap syntax and allowlist tests passed"
