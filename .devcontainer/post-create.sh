#!/usr/bin/env bash
set -uo pipefail

REPO="/workspaces/aidevcontainer"
chmod +x "$REPO"/scripts/*.sh "$REPO"/tests/*.sh 2>/dev/null || true

# Align git config inside the container with what's mounted (no global writes from image)
git config --global --add safe.directory "$REPO" || true
git config --global init.defaultBranch main || true

# Re-run the docker-socket fixup in case the user mounts /var/run/docker.sock at create time
sudo /usr/local/bin/fix-docker-perms || true

# Friendly first-launch banner
cat <<'EOF'
============================================================
ai-dev container ready.

On-demand services:
  bash scripts/start-mssql.sh                # SQL Server 2025  -> 1433 (pw in ~/.mssql-password)
  bash scripts/start-postgres.sh             # PostgreSQL 18    -> 5432
  bash scripts/start-azurite.sh              # Azurite          -> 10000/10001/10002
  bash scripts/start-azp-agent.sh            # Azure DevOps agent (needs AZP_URL / AZP_TOKEN)
  bash scripts/start-gh-runner.sh            # GitHub runner    (needs GH_RUNNER_URL / GH_RUNNER_TOKEN)
  bash scripts/gpu-check.sh                  # Verify --gpus passthrough
  bash scripts/stop-all.sh                   # Stop everything

Run smoke tests with:
  bash tests/smoke.sh
============================================================
EOF
