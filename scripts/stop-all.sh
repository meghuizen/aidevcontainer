#!/usr/bin/env bash
# Best-effort teardown — `set -e` is intentionally OFF so a missing service
# doesn't short-circuit the rest of the cleanup.
set -uo pipefail

pkill -f azurite             2>/dev/null || true
# Azure DevOps agent foreground process: Agent.Listener
pkill -f "Agent.Listener"    2>/dev/null || true
# GitHub Actions runner foreground process: Runner.Listener
pkill -f "Runner.Listener"   2>/dev/null || true

echo "stop-all: done."
