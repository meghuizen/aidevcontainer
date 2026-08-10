#!/usr/bin/env bash
set -euo pipefail

# Azure DevOps self-hosted build agent.
#
# This script runs the agent in the FOREGROUND via `exec ./run.sh` (final line).
# To background it instead, run:  nohup bash scripts/start-azp-agent.sh > /tmp/azp.log 2>&1 &
#
# Required env (NEVER bake into the image):
#   AZP_URL          e.g. https://dev.azure.com/<org>
#   AZP_TOKEN        PAT with "Agent Pools (read & manage)" scope
#   AZP_POOL         agent pool name (default: Default)
#   AZP_AGENT_NAME   agent display name (default: aidev-$(hostname))
#   AZP_WORK         work folder (default: _work)

: "${AZP_URL:?AZP_URL is required (https://dev.azure.com/<org>)}"
: "${AZP_TOKEN:?AZP_TOKEN is required (PAT with Agent Pools rw)}"
AZP_POOL="${AZP_POOL:-Default}"
AZP_AGENT_NAME="${AZP_AGENT_NAME:-aidev-$(hostname)}"
AZP_WORK="${AZP_WORK:-_work}"

cd /opt/azp-agent

if [[ ! -f .agent ]]; then
  echo "azp-agent: configuring '$AZP_AGENT_NAME' on pool '$AZP_POOL'..."
  ./config.sh \
    --unattended \
    --acceptTeeEula \
    --url "$AZP_URL" \
    --auth pat \
    --token "$AZP_TOKEN" \
    --pool "$AZP_POOL" \
    --agent "$AZP_AGENT_NAME" \
    --work "$AZP_WORK" \
    --replace
fi

echo "azp-agent: starting..."
exec ./run.sh
