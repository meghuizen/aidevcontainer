#!/usr/bin/env bash
# Best-effort teardown — `set -e` is intentionally OFF so a missing service
# doesn't short-circuit the rest of the cleanup.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

pkill -f sqlservr            2>/dev/null || true
# start-postgres.sh starts via bare pg_ctl against /var/lib/postgresql/18/main, not the
# Debian cluster registry, so pg_ctlcluster won't find it. Use pg_ctl with the matching dir.
sudo -u postgres /usr/lib/postgresql/18/bin/pg_ctl \
    -D /var/lib/postgresql/18/main stop -m fast 2>/dev/null || true
pkill -f azurite             2>/dev/null || true
# Azure DevOps agent foreground process: Agent.Listener
pkill -f "Agent.Listener"    2>/dev/null || true
# GitHub Actions runner foreground process: Runner.Listener
pkill -f "Runner.Listener"   2>/dev/null || true

echo "stop-all: done."
