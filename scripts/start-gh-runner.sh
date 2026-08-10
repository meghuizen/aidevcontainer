#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions self-hosted runner.
#
# This script runs the runner in the FOREGROUND via `exec ./run.sh` (final line).
# To background it instead, run: nohup bash scripts/start-gh-runner.sh > /tmp/gh-runner.log 2>&1 &
#
# Required env (NEVER bake into the image):
#   GH_RUNNER_URL    e.g. https://github.com/<org> or https://github.com/<org>/<repo>
#   GH_RUNNER_TOKEN  registration token from repo/org -> Settings -> Actions -> Runners
#   GH_RUNNER_NAME   runner name (default: aidev-$(hostname))
#   GH_RUNNER_LABELS comma-separated labels (default: self-hosted,linux,x64,aidev)

: "${GH_RUNNER_URL:?GH_RUNNER_URL is required}"
: "${GH_RUNNER_TOKEN:?GH_RUNNER_TOKEN is required}"
GH_RUNNER_NAME="${GH_RUNNER_NAME:-aidev-$(hostname)}"
GH_RUNNER_LABELS="${GH_RUNNER_LABELS:-self-hosted,linux,x64,aidev}"

cd /opt/gh-runner

if [[ ! -f .runner ]]; then
  echo "gh-runner: configuring '$GH_RUNNER_NAME' against '$GH_RUNNER_URL'..."
  ./config.sh \
    --unattended \
    --url "$GH_RUNNER_URL" \
    --token "$GH_RUNNER_TOKEN" \
    --name "$GH_RUNNER_NAME" \
    --labels "$GH_RUNNER_LABELS" \
    --replace
fi

echo "gh-runner: starting..."
exec ./run.sh
