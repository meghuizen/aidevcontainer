#!/usr/bin/env bash
# Register the container's MCP servers and guidance with every agent CLI in the
# image, for the CURRENT user. Idempotent — run from post-create and safe to
# re-run by hand (`setup-agents`).
#
#   fff              fff-mcp: default file finder + content index of the data
#                    folder ($AIDEV_DATA_DIR, /data — all source code)
#   codegraph        CodeGraph: symbol/call-graph queries (projects with .codegraph/)
#   playwright       Playwright MCP: drives the image's own headless Chromium
#                    (/usr/local/bin/chromium, see playwright-browsers.sh) — no download.
#                    All capabilities on (vision = coordinate mouse tools, pdf,
#                    devtools = tracing/video/recording); --ignore-https-errors so
#                    ASP.NET Core / Aspire dev-cert HTTPS works; --no-sandbox because
#                    Chromium's user-namespace sandbox is unavailable in a
#                    (rootless) container.
#   microsoft-learn  Microsoft Learn docs (.NET, ASP.NET Core, Aspire, Azure) — remote HTTP
#   aismartbuddy     Thinking graph, SQL/graph analysis sessions, web crawl
#                    (github.com/meghuizen/aismartbuddy, via uvx from GitHub)
#
# Agents: Claude Code, Codex, GitHub Copilot CLI, OpenCode.
#
# Claude Code additionally gets config/claude-settings.json merged in
# (permission allow-list + codegraph prompt hook) and the csharp-lsp,
# typescript-lsp and pyright-lsp plugins.
#
# Why at create time and not in the image: agent config lives in the user's
# home and most of it is on named volumes (see docker-compose.yml) — anything
# baked into the image there would be hidden by the volume. Existing user config
# is merged into, never overwritten; a server the user already has under the
# same name is left alone.
#
# `set -e` is intentionally OFF: one agent failing must not stop the others.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
INSTRUCTIONS="$SCRIPT_DIR/../config/agent-instructions.md"
BEGIN="<!-- aidev:begin"
END="<!-- aidev:end -->"

# fff indexes the data folder (all source code), not just the agent's CWD.
# Falls back to CWD when the data folder is not mounted (plain `docker run`).
DATA_DIR="${AIDEV_DATA_DIR:-/data}"
FFF_ROOT=""
[[ -d "$DATA_DIR" ]] && FFF_ROOT=" $DATA_DIR"

# name | kind (stdio/http) | command + args, or URL
SERVERS=(
  "fff|stdio|fff-mcp --no-update-check${FFF_ROOT}"
  "codegraph|stdio|codegraph serve --mcp"
  "playwright|stdio|playwright-mcp --headless --isolated --no-sandbox --ignore-https-errors --caps vision,pdf,devtools --browser chromium --executable-path /usr/local/bin/chromium"
  "microsoft-learn|http|https://learn.microsoft.com/api/mcp"
  "aismartbuddy|stdio|uvx --from git+https://github.com/meghuizen/aismartbuddy aismartbuddy"
)

log() { echo "setup-agents: $*"; }

# Codex refuses to start when CODEX_HOME points at a missing directory.
mkdir -p "${CODEX_HOME:-$HOME/.codex}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# install_instructions <file> — add or refresh the managed guidance block.
install_instructions() {
  local file="$1" tmp
  [[ -f "$INSTRUCTIONS" ]] || return 0
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp)"
  # Drop any previous managed block, then append the current one.
  awk -v b="$BEGIN" -v e="$END" '
    index($0, b) == 1 { skip = 1; next }
    skip && index($0, e) == 1 { skip = 0; next }
    !skip { print }
  ' "$file" > "$tmp"
  # Trim trailing blank lines so repeated runs do not grow the file.
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
  { [[ -s "$tmp" ]] && echo; cat "$INSTRUCTIONS"; } >> "$tmp"
  if cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$file" && log "guidance updated in $file"
  fi
}

# jq_merge <file> <jq filter> [jq args...] — edit a JSON config in place.
jq_merge() {
  local file="$1" filter="$2" tmp; shift 2
  mkdir -p "$(dirname "$file")"
  [[ -s "$file" ]] || echo '{}' > "$file"
  tmp="$(mktemp)"
  if jq "$@" "$filter" "$file" > "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    log "$file is not valid JSON — left untouched" >&2
    return 1
  fi
}

for entry in "${SERVERS[@]}"; do
  IFS='|' read -r name kind target <<< "$entry"
  if [[ "$kind" == stdio ]]; then
    read -r -a argv <<< "$target"
    if ! command -v "${argv[0]}" >/dev/null 2>&1; then
      log "$name: ${argv[0]} not on PATH — skipped"
      continue
    fi
  fi

  # --- Claude Code (user scope → $CLAUDE_CONFIG_DIR/.claude.json) ---
  if command -v claude >/dev/null 2>&1 && ! claude mcp get "$name" >/dev/null 2>&1; then
    if [[ "$kind" == stdio ]]; then
      claude mcp add --scope user "$name" -- "${argv[@]}" >/dev/null
    else
      claude mcp add --scope user --transport http "$name" "$target" >/dev/null
    fi && log "claude: $name registered" || log "claude: $name failed (non-fatal)" >&2
  fi

  # --- Codex ($CODEX_HOME/config.toml) ---
  if command -v codex >/dev/null 2>&1 && ! codex mcp get "$name" >/dev/null 2>&1; then
    if [[ "$kind" == stdio ]]; then
      codex mcp add "$name" -- "${argv[@]}" >/dev/null 2>&1
    else
      codex mcp add "$name" --url "$target" >/dev/null 2>&1
    fi && log "codex: $name registered" || log "codex: $name failed (non-fatal)" >&2
  fi

  # --- GitHub Copilot CLI (~/.copilot/mcp-config.json) ---
  if command -v copilot >/dev/null 2>&1; then
    cfg="$HOME/.copilot/mcp-config.json"
    if ! jq -e --arg n "$name" '.mcpServers[$n]' "$cfg" >/dev/null 2>&1; then
      if [[ "$kind" == stdio ]]; then
        jq_merge "$cfg" '.mcpServers[$n] = {type: "local", command: $a[0], args: $a[1:], tools: ["*"]}' \
          --arg n "$name" --argjson a "$(printf '%s\n' "${argv[@]}" | jq -R . | jq -s .)"
      else
        jq_merge "$cfg" '.mcpServers[$n] = {type: "http", url: $u, tools: ["*"]}' \
          --arg n "$name" --arg u "$target"
      fi && log "copilot: $name registered"
    fi
  fi

  # --- OpenCode (~/.config/opencode/opencode.json) ---
  if command -v opencode >/dev/null 2>&1; then
    cfg="$HOME/.config/opencode/opencode.json"
    [[ -s "$cfg" ]] || { mkdir -p "$(dirname "$cfg")"; echo '{"$schema":"https://opencode.ai/config.json"}' > "$cfg"; }
    if ! jq -e --arg n "$name" '.mcp[$n]' "$cfg" >/dev/null 2>&1; then
      if [[ "$kind" == stdio ]]; then
        jq_merge "$cfg" '.mcp[$n] = {type: "local", command: $a, enabled: true}' \
          --arg n "$name" --argjson a "$(printf '%s\n' "${argv[@]}" | jq -R . | jq -s .)"
      else
        jq_merge "$cfg" '.mcp[$n] = {type: "remote", url: $u, enabled: true}' \
          --arg n "$name" --arg u "$target"
      fi && log "opencode: $name registered"
    fi
  fi
done

# --- Claude Code settings + LSP plugins (mirrors the tuned host setup) ---
# Merge config/claude-settings.json into the user's settings.json: permission
# allow-list is unioned, the codegraph prompt hook is added once, nothing the
# user set is removed or overridden.
if command -v claude >/dev/null 2>&1; then
  CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  DEFAULTS="$SCRIPT_DIR/../config/claude-settings.json"
  if [[ -f "$DEFAULTS" ]]; then
    before="$(cat "$CLAUDE_DIR/settings.json" 2>/dev/null)"
    jq_merge "$CLAUDE_DIR/settings.json" '
      ($d[0]) as $def
      | .permissions.allow = (((.permissions.allow // []) + $def.permissions.allow) | unique)
      | .hooks.UserPromptSubmit = (
          (.hooks.UserPromptSubmit // []) as $cur
          | if ([$cur[].hooks[]?.command] | index("codegraph prompt-hook")) then $cur
            else $cur + $def.hooks.UserPromptSubmit end)
    ' --slurpfile d "$DEFAULTS" \
      && [[ "$(cat "$CLAUDE_DIR/settings.json")" != "$before" ]] \
      && log "claude: settings.json merged (permissions, codegraph hook)"
  fi

  # Code-intelligence plugins: C# (csharp-ls), TypeScript/Angular
  # (typescript-language-server), Python (pyright) — all servers are in the image.
  # Needs network on first run; skipped silently once installed. A fresh config
  # only knows the built-in directory, so add the official marketplace first.
  if ! jq -e '."claude-plugins-official"' "$CLAUDE_DIR/plugins/known_marketplaces.json" >/dev/null 2>&1; then
    claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 \
      && log "claude: marketplace claude-plugins-official added"
  fi
  for plugin in csharp-lsp typescript-lsp pyright-lsp; do
    if ! jq -e --arg p "$plugin@claude-plugins-official" '.plugins[$p]' \
         "$CLAUDE_DIR/plugins/installed_plugins.json" >/dev/null 2>&1; then
      claude plugin install "$plugin@claude-plugins-official" >/dev/null 2>&1 \
        && log "claude: plugin $plugin installed" \
        || log "claude: plugin $plugin not installed (offline? retry with setup-agents)" >&2
    fi
  done
fi

command -v claude   >/dev/null 2>&1 && install_instructions "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md"
command -v codex    >/dev/null 2>&1 && install_instructions "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
command -v copilot  >/dev/null 2>&1 && install_instructions "$HOME/.copilot/copilot-instructions.md"
command -v opencode >/dev/null 2>&1 && install_instructions "$HOME/.config/opencode/AGENTS.md"

exit 0
