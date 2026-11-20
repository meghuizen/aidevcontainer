#!/usr/bin/env bash
# Install (build time) or verify (smoke test) the Chromium build of the
# Playwright MCP server — the only Playwright in the image.
#
# @playwright/mcp ships its own playwright-core (it tracks alpha builds), and
# each playwright-core version pins its own Chromium revision. Installing via
# the MCP's own playwright-core guarantees the revision matches.
#
# Also maintains /usr/local/bin/chromium -> that Chromium; the MCP registration
# (setup-agents.sh) passes it as --executable-path, so the MCP always drives the
# browser baked into the image and never downloads one.
#
# Usage: playwright-browsers.sh install|check
set -euo pipefail

MODE="${1:-check}"
PKG_DIR=/usr/local/lib/node_modules/@playwright/mcp
: "${PLAYWRIGHT_BROWSERS_PATH:?PLAYWRIGHT_BROWSERS_PATH must be set}"

[[ -d "$PKG_DIR" ]] || { echo "playwright-browsers: @playwright/mcp not installed" >&2; exit 1; }

# The playwright-core the MCP actually loads.
core="$(node -e '
  const path = require("path");
  console.log(path.dirname(require.resolve("playwright-core/package.json", { paths: [process.argv[1]] })));
' "$PKG_DIR")"
ver="$(node -p "require('$core/package.json').version")"

if [[ "$MODE" == install ]]; then
  node "$core/cli.js" install chromium
fi

# Launch headless and print version + executable — fails on a missing revision
# or a missing shared library. PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD guards against a
# silent fallback download during `check`.
out="$(PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 node -e '
  const { chromium } = require(process.argv[1]);
  chromium.launch()
    .then(async b => { console.log(b.version() + " " + chromium.executablePath()); await b.close(); })
    .catch(e => { console.error(e.message); process.exit(1); });
' "$core")"
exe="${out#* }"
echo "playwright-browsers: @playwright/mcp (playwright-core $ver) -> chromium ${out%% *}"

if [[ "$MODE" == install ]]; then
  sudo ln -sf "$exe" /usr/local/bin/chromium
fi
[[ "$(readlink -f /usr/local/bin/chromium)" == "$(readlink -f "$exe")" ]] \
  || { echo "playwright-browsers: /usr/local/bin/chromium does not point at the MCP's Chromium ($exe)" >&2; exit 1; }
