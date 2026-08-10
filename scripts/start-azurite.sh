#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

aidev_must_be_in_container "$(command -v azurite || echo /usr/lib/node_modules/azurite)"
aidev_already_running azurite pgrep -f azurite && exit 0

DATA="${HOME}/.azurite"
mkdir -p "$DATA"

echo "azurite: starting (blob:10000 queue:10001 table:10002)..."
nohup azurite \
  --silent \
  --location "$DATA" \
  --debug "$DATA/debug.log" \
  --blobHost 0.0.0.0 --blobPort 10000 \
  --queueHost 0.0.0.0 --queuePort 10001 \
  --tableHost 0.0.0.0 --tablePort 10002 \
  >/tmp/azurite.log 2>&1 &

aidev_wait_until azurite 20 1 \
  curl -fsS "http://127.0.0.1:10000/devstoreaccount1?comp=list"
