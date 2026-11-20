#!/usr/bin/env bash
# Dev Container postCreateCommand (wired via the image's devcontainer.metadata
# label, so every devcontainer.json variant runs it). Runs as `vscode` with the
# workspace folder as CWD. Idempotent.
set -uo pipefail

WORKSPACE="$PWD"
AIDEV=/opt/aidev

# Every repo under the bind-mounted data folder is owned by the host user — let
# git trust them all (this is a single-user dev container).
git config --global --get-all safe.directory | grep -qxF '*' \
  || git config --global --add safe.directory '*' || true
git config --global init.defaultBranch main || true

# Global gitignore for files agents/tools drop into any repo (Playwright MCP
# writes snapshots/screenshots/PDFs to ./.playwright-mcp by default).
GITIGNORE="$HOME/.config/git/ignore"
mkdir -p "$(dirname "$GITIGNORE")"
for pattern in .playwright-mcp/ .codegraph/; do
  grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null || echo "$pattern" >> "$GITIGNORE"
done

# Re-run the docker-socket fixup in case the socket is mounted at create time.
sudo /usr/local/bin/fix-docker-perms || true

# Register MCP servers (fff, codegraph, Playwright, Microsoft Learn) and the
# container guidance with Claude Code, Codex, Copilot CLI and OpenCode.
bash "$AIDEV/scripts/setup-agents.sh" || true

cat <<'EOF'
============================================================
ai-dev container ready.

On-demand services (scripts live in /opt/aidev/scripts):
  start-azurite.sh     Azurite -> 10000/10001/10002
  start-azp-agent.sh   Azure DevOps agent (needs AZP_URL / AZP_TOKEN)
  start-gh-runner.sh   GitHub runner      (needs GH_RUNNER_URL / GH_RUNNER_TOKEN)
  gpu-check.sh         Verify --gpus passthrough
  stop-all.sh          Stop everything
  setup-agents         Re-register MCP servers with the agent CLIs

Smoke test: bash /opt/aidev/tests/smoke.sh
============================================================
EOF
