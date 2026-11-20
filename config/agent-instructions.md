<!-- aidev:begin — managed by /opt/aidev/scripts/setup-agents.sh; edits inside this block are overwritten -->
## ai-dev container

You are running inside the ai-dev dev container (Ubuntu 26.10, user `vscode`, passwordless sudo). Everything below is already installed and on PATH — do not install it again.

**`/data` is the data folder**: all source code and the working environment (every repo side by side). The current project is a folder under it.

### Finding and understanding code
- **Search:** use the **fff** MCP tools (`find_files`, `grep`, `multi_grep`) for finding files and searching contents — a frecency-ranked in-memory index of all of `/data`, faster than `find`/`grep`/`rg`. Scope a search to the current repo with a directory constraint (e.g. `myrepo/`) when cross-repo hits are noise. Fall back to `rg`/`fd` only when fff cannot express the query.
- **Structure:** in a repo with a `.codegraph/` directory, use the **codegraph** MCP (`codegraph_explore`) before reading files. Indexing (`codegraph init`) is the user's decision — do not run it unasked.
- **Syntax-aware search/rewrite:** `ast-grep` (`sg`). **Docs for .NET / ASP.NET Core / Aspire / Azure:** the **microsoft-learn** MCP, not memory.

### .NET
- SDK 10 and 11 side-by-side; respect `global.json`. Format with `dotnet csharpier format .` when the repo uses CSharpier, otherwise `dotnet format`. Run the relevant tests (`dotnet test --no-restore`), not the whole solution.
- Diagnostics: `dotnet-counters`, `dotnet-trace`, `dotnet-dump` (analyze with `dotnet-dump analyze`), `dotnet-gcdump`, `dotnet-stack`. Native + managed debugging: `lldb` (SOS preloaded). Scriptable debugger: `netcoredbg` (CLI / MI / DAP). Decompile: `ilspycmd`. Coverage: `dotnet-coverage` + `reportgenerator`. Docs: `docfx`. DB projects: `sqlpackage`.
- Aspire: `aspire run` / `aspire new`. Resources start as sibling containers through the host's container engine (`docker` CLI → mounted socket).

### Frontend
- Angular CLI (`ng`) and Node 26 LTS. **pnpm** is the package manager — never `npm install`/`yarn` in a pnpm repo; respect `pnpm-lock.yaml`.
- Browser work: the **playwright** MCP. It uses the Chromium baked into the image (`/usr/local/bin/chromium`, headless) — never run `playwright install` for it. The MCP has every capability on: snapshots, screenshots, PDF (`browser_pdf_save`), coordinate mouse tools, network/console inspection, tracing and video; HTTPS errors (dev certs) are ignored. Its output lands in `./.playwright-mcp/` (globally git-ignored). For a dev server started in this container, browse `http://localhost:<port>`. For .NET Playwright projects `pwsh bin/Debug/<tfm>/playwright.ps1 install` works (`pwsh` is installed).

### Reasoning and analysis
- **aismartbuddy** MCP: use its thinking graph (`think_*`, `sequentialthinking`, `holon_*`) for non-trivial design decisions, trade-offs and reviews; `sql_*` / `graph_*` sessions for analysing data and relationships; `web_crawl` / `get_youtube_information` to pull external docs into Markdown. One thought or research unit at a time — split independent parts over subagents.

### Data, docs and analysis
- DB clients: `sqlcmd` (go-sqlcmd), `psql`, `mysql`, `duckdb`, `sqlite3`. There are **no DB servers** in this container — they run as separate containers.
- Documents → Markdown: `markitdown <file>` (docx/pptx/xlsx/pdf/html). Also `pandoc`, `pdftotext`, `tesseract`. Diagrams: `dot` (graphviz).
- Lint/security: `shellcheck`, `hadolint`, `markdownlint-cli2`, `semgrep`, `gitleaks`, `yq`/`jq`. Benchmark CLIs with `hyperfine`.
<!-- aidev:end -->
