#!/usr/bin/env bash
# Smoke test: every tool resolves on PATH and reports a version.
# Each line that exits non-zero is reported. Service-start checks are optional
# (skipped unless AIDEV_SMOKE_FULL=1 is set, since they take time).

set -uo pipefail

PASS=0
FAIL=0
FAILED=()

check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1))
    printf '  \e[32mok\e[0m   %s\n' "$name"
  else
    FAIL=$((FAIL+1))
    FAILED+=("$name")
    printf '  \e[31mFAIL\e[0m %s\n' "$name"
  fi
}

echo "--- system ---"
check "ubuntu 26.10"           bash -c 'lsb_release -a 2>/dev/null | grep -q "26.10"'
check "en_US locale"           bash -c 'locale | grep -q en_US.UTF-8'
# amd64v3 is optional (ENABLE_AMD64V3=0 is a supported build), so only assert the
# CPU baseline when the image was actually built against the v3 package set.
if apt-config dump 2>/dev/null | grep -qi "architecture-variants.*amd64v3"; then
  # `ld.so` is not on PATH on Ubuntu — ask the dynamic loader directly.
  check "cpu supports x86-64-v3" bash -c \
    'L="$(command -v ld.so || echo /lib64/ld-linux-x86-64.so.2)"; "$L" --help 2>/dev/null | grep -q "x86-64-v3.*supported"'
else
  echo "  skip amd64v3 (built with ENABLE_AMD64V3=0)"
fi
check "nofile ulimit >= 1M"    bash -c '[[ "$(ulimit -Hn)" -ge 1048576 ]]'
check "core dumps disabled"    bash -c '[[ "$(ulimit -Hc)" == "0" ]]'
check "limits.d installed"     test -f /etc/security/limits.d/90-aidev.conf

echo "--- .NET ---"
check "dotnet sdk 10"           bash -c 'dotnet --list-sdks | grep -q "^10\."'
check "dotnet sdk 11"           bash -c 'dotnet --list-sdks | grep -q "^11\."'
check "dotnet aspnetcore 10"    bash -c 'dotnet --list-runtimes | grep -q "Microsoft.AspNetCore.App 10\."'
check "dotnet aspnetcore 11"    bash -c 'dotnet --list-runtimes | grep -q "Microsoft.AspNetCore.App 11\."'
check "aspire cli"              aspire --version
check "roslynator"              roslynator --version
check "dotnet-ef"               dotnet-ef --version
check "dotnet format (sdk)"     dotnet format --version
check "csharp-ls"               csharp-ls --version
check "csharpier"               csharpier --version
check "dotnet-dump"             dotnet-dump --version
check "dotnet-trace"            dotnet-trace --version
check "dotnet-counters"         dotnet-counters --version
check "dotnet-gcdump"           dotnet-gcdump --version
check "dotnet-stack"            dotnet-stack --version
check "dotnet-coverage"         dotnet-coverage --version
check "reportgenerator"         bash -c 'reportgenerator -h 2>&1 | grep -qi reportgenerator'
check "ilspycmd"                ilspycmd --version
check "docfx"                   docfx --version
check "sqlpackage"              bash -c 'sqlpackage /version 2>&1 | grep -qE "[0-9]+\."'
check "netcoredbg"              netcoredbg --version
check "lldb + SOS"              bash -c 'lldb --version && test -f ~/.lldbinit'
check "pwsh"                    pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'


echo "--- Azure ---"
check "az cli"                  az version
check "az ext azure-devops"     bash -c 'az extension list -o tsv 2>/dev/null | grep -q azure-devops'
check "az ext containerapp"     bash -c 'az extension list -o tsv 2>/dev/null | grep -q containerapp'
check "az bicep"                bash -c 'az bicep version 2>&1 | grep -qi bicep || az bicep install'
check "func core tools"         func --version
check "azurite"                 azurite --version

echo "--- Node ---"
check "node 26.x"               bash -c 'node --version | grep -qE "^v26\."'
check "npm"                     npm --version
check "pnpm (default pm)"       pnpm --version
check "yarn"                    yarn --version
check "playwright-mcp"          bash -c 'playwright-mcp --help'
check "playwright mcp chromium" bash /opt/aidev/scripts/playwright-browsers.sh check
check "playwright mcp -> chromium" bash -c 'claude mcp get playwright | grep -q -- "--caps vision,pdf,devtools.*--executable-path /usr/local/bin/chromium"'
check "angular cli (ng)"        ng version
check "angular language server" bash -c 'command -v ngserver'
check "markdownlint-cli2"       bash -c 'markdownlint-cli2 --help'

check "tsc"                     tsc --version
check "typescript-language-srv" typescript-language-server --version

echo "--- Python ---"
check "system python3 (apt)"    bash -c 'python3 --version | grep -qE "^Python 3\.[0-9]+"'
check "venv uses system python" bash -c '[[ "$(/opt/venv/bin/python --version)" == "$(/usr/bin/python3 --version)" ]]'
check "only one python"         bash -c '! ls /usr/local/bin/python3.* >/dev/null 2>&1 && [[ -z "$(ls -A "$HOME/.local/share/uv/python" 2>/dev/null)" ]]'
check "uv"                      uv --version
check "uvx"                     uvx --version
check "ruff"                    ruff --version
check "pyright"                 pyright --version
check "mypy"                    mypy --version

echo "--- Search & nav ---"
check "fff-mcp"                 fff-mcp --version
check "fff indexes /data"       bash -c 'claude mcp get fff | grep -q -- "--no-update-check /data"'
check "/data mounted"           test -d /data
check "codegraph"               codegraph --version
check "aismartbuddy (uvx)"      bash -c 'uvx --from git+https://github.com/meghuizen/aismartbuddy aismartbuddy --help'
for s in fff codegraph playwright microsoft-learn aismartbuddy; do
  check "claude mcp: $s"        claude mcp get "$s"
done
check "ripgrep (rg)"            rg --version
check "ast-grep (sg)"           sg --version
check "tree-sitter"             tree-sitter --version
check "tree"                    tree --version
check "fd"                      fd --version
check "bat"                     bat --version
check "fzf"                     fzf --version
check "zoxide"                  zoxide --version
check "delta"                   delta --version

echo "--- Git ---"
check "git"                     git --version
check "gh"                      gh --version
check "git-lfs"                 git-lfs --version
check "lazygit"                 lazygit --version
check "repo (Android)"          bash -c 'command -v repo'
check "zip"                     zip -v
check "rsync"                   rsync --version
# yarn (classic CLI) is provided by corepack — `yarn --version` already verified
# under "--- Node ---". The apt `yarnpkg` package is intentionally NOT installed because
# it pulls in Debian's nodejs and ~150 node-* packages that NodeSource Node 26 then
# removes, defeating the install.

echo "--- DB clients ---"
check "sqlcmd (go-sqlcmd)"      sqlcmd --version
check "psql"                    psql --version
check "mysql client"            mysql --version
check "duckdb"                  duckdb --version
check "sqlite3"                 sqlite3 --version

echo "--- AI / media ---"
check "huggingface-cli"         huggingface-cli --help
check "yt-dlp"                  yt-dlp --version
check "yt-dlp js runtime=node"  grep -q -- "--js-runtimes node" /etc/yt-dlp.conf
check "tesseract"               tesseract --version
check "markitdown"              markitdown --help
check "pandoc"                  pandoc --version
check "graphviz (dot)"          dot -V
check "ffmpeg"                  ffmpeg -version
# Note: faster-whisper and whisper.cpp are NOT preinstalled. Install on demand:
#   /opt/venv/bin/pip install faster-whisper
#   git clone https://github.com/ggml-org/whisper.cpp && cd whisper.cpp && cmake -B build && cmake --build build

echo "--- AI agents ---"
check "claude code"             claude --version
check "codex"                   codex --version
check "opencode"                opencode --version
check "rtk"                     rtk --version
check "hermes (NousResearch)"   bash -c 'hermes --version 2>/dev/null || hermes -v 2>/dev/null || command -v hermes'
check "happy (engineering)"     bash -c 'happy --version 2>/dev/null || happy --help 2>/dev/null || command -v happy'
check "copilot cli"             copilot --version
check "claude config on volume" bash -c '[[ "$CLAUDE_CONFIG_DIR" == "$HOME/.claude" ]]'

echo "--- Build agents (binaries present, not configured) ---"
check "azp-agent run.sh"        test -x /opt/azp-agent/run.sh
check "azp-agent config.sh"     test -x /opt/azp-agent/config.sh
check "gh-runner run.sh"        test -x /opt/gh-runner/run.sh
check "gh-runner config.sh"     test -x /opt/gh-runner/config.sh

echo "--- Analysis / lint ---"
check "shellcheck"              shellcheck --version
check "hadolint"                hadolint --version
check "semgrep"                 semgrep --version
check "gitleaks"                gitleaks version
check "yq"                      yq --version
check "hyperfine"               hyperfine --version

echo "--- Container / GPU ---"
check "docker cli"              docker --version
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  check "nvidia-smi"              nvidia-smi -L
else
  echo "  skip nvidia-smi (no GPU passthrough; expected without --gpus all)"
fi
# nvcc is NOT in the image — CUDA toolkit was dropped to save ~5 GB. Driver libs are
# injected at runtime by the NVIDIA Container Toolkit when --gpus all is passed.

echo "--- Python doc libs (in /opt/venv) ---"
check "py docx/openpyxl/pdf*"   /opt/venv/bin/python -c "import docx, pptx, openpyxl, pypdf, pdfplumber, pytesseract, PIL, duckdb, polars"

if [[ "${AIDEV_SMOKE_FULL:-0}" == "1" ]]; then
  echo "--- Services (full mode) ---"
  bash /opt/aidev/scripts/start-azurite.sh
  check "azurite blob"          curl -fsS "http://127.0.0.1:10000/devstoreaccount1?comp=list"
fi

echo
echo "passed: $PASS    failed: $FAIL"
if (( FAIL > 0 )); then
  printf '\nfailing checks:\n'
  for f in "${FAILED[@]}"; do echo "  - $f"; done
  exit 1
fi
