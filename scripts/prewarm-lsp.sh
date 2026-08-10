#!/usr/bin/env bash
# Pre-warm LSP / analyzer caches so first navigation is instant.
# Run at image build time and re-runnable post-build.
# `set -e` is intentionally OFF — a missing tool (e.g. gopls when Go isn't installed)
# must skip its arm, not abort the rest of the warm-up.
set -uo pipefail

WARM=/tmp/aidev-prewarm
rm -rf "$WARM"
mkdir -p "$WARM"

# --- .NET / Roslyn / NuGet ---
if command -v dotnet >/dev/null 2>&1; then
  ( cd "$WARM" \
      && dotnet new console -o csprime --no-restore \
      && cd csprime \
      && dotnet restore \
      && dotnet build -c Release -nologo ) || echo "prewarm: dotnet warm failed (non-fatal)"
  # Trust the ASP.NET Core dev HTTPS cert so `dotnet run` in templates doesn't emit
  # "the SSL certificate is not trusted" warnings. On Linux this writes the cert into
  # ~/.aspnet/dev-certs/https/ and (if libnss3-tools present) into the user's NSS store
  # used by Firefox/Chrome. Idempotent — silent if already trusted.
  dotnet dev-certs https --trust >/dev/null 2>&1 || \
    echo "prewarm: dev-certs trust skipped (non-fatal)"
fi

# --- Python / pyright ---
if command -v pyright >/dev/null 2>&1; then
  echo "x: int = 1" > "$WARM/empty.py"
  pyright "$WARM/empty.py" >/dev/null 2>&1 || true
fi
if command -v ruff >/dev/null 2>&1; then
  ruff check "$WARM/empty.py" >/dev/null 2>&1 || true
fi

# --- TypeScript / tsserver ---
if command -v typescript-language-server >/dev/null 2>&1; then
  typescript-language-server --version >/dev/null 2>&1 || true
fi
if command -v node >/dev/null 2>&1; then
  node -e "require('typescript')" 2>/dev/null || true
fi

# --- Go / gopls ---
if command -v gopls >/dev/null 2>&1; then
  gopls version >/dev/null 2>&1 || true
fi

# --- Rust / rust-analyzer ---
if command -v rust-analyzer >/dev/null 2>&1; then
  rust-analyzer --version >/dev/null 2>&1 || true
fi

# --- ast-grep / tree-sitter ---
if command -v sg >/dev/null 2>&1; then
  sg --version >/dev/null 2>&1 || true
fi
if command -v tree-sitter >/dev/null 2>&1; then
  tree-sitter --version >/dev/null 2>&1 || true
fi

rm -rf "$WARM"
echo "prewarm-lsp: done."
