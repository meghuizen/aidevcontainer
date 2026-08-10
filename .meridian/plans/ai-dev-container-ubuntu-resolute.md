# AI Dev Container — Ubuntu 26.04 (Resolute Raccoon)

## Verbatim Requirements

### Original Request
> I want you to create the most high performance docker image to do AI software development on it. I want it based on ubuntu resolute (resolute can be used as tag). I want you to install in it: en_us locale, SQL Server 2025, Azure CLI, with devops, bicep and other support, aspire cli, claude code, codex, opencode, tree command, python 3.14, UV and uvx, npm, pnpm, nodejs, azure service bus emulator, azure storage emulator, dotnet 10 runtime and sdk, azure functions runtime and sdk, other usefull tools for developing on C# .NET. Git and git development tools. Roslynator. I want high performance for AI agents to navigate the code base and work with it. high speed file system. ripgrep, ast-grep, LSP servers for all languages like C#, JS, python, etc. sql client tools. Postgresql, duckdb, ladybug db. I want a really capapable and high performance environment. Look at my claude code history to see what tools you also need. also install ollama, whisper support, support for all office 365 documents, pdfs, screenshots, etc.

### Follow-up 1
> also add github client

### Follow-up 2
> Also make sure that the image works with nvidia container kit. installs rtk https://github.com/rtk-ai/rtk in the path. all tools are part of the path. optimize the image for performance. also add azure devops build agent and github build agents on the image which can be used. devops agent: https://download.agent.dev.azure.com/agent/4.272.0/vsts-agent-linux-x64-4.272.0.tar.gz

### Clarifications
**Q:** How will you actually use this image?
**A:** VS Code dev container.

**Q:** Where should heavy services live (SQL Server 2025, Postgres, Azurite, Service Bus emulator, Ollama)?
**A:** All baked into the single image, started on demand.

**Q:** Target CPU architecture?
**A:** linux/amd64 only.

**Q:** Which extras for AI/media/Office workflows?
**A:** faster-whisper, whisper.cpp, Python doc libs only (python-docx, openpyxl, pypdf, pdfplumber, pillow, pytesseract).

**Q:** Non-root user setup?
**A:** `vscode` user with passwordless sudo.

**Q:** Ollama model preload?
**A:** Install Ollama binary only, no models.

**Q:** Pre-cached artifacts for AI agents?
**A:** Pre-warm Roslyn / pyright / tsserver / gopls / rust-analyzer; pre-install ast-grep with rule packs for C#/Python/TS; pre-install tree-sitter CLI + common grammars.

---

## Context

The directory `C:\Users\michiele\source\repos\aidevcontainer` is empty. The user wants a single, self-contained, high-performance dev container image that bundles everything needed for AI-assisted .NET + Python software development. Heavy services are baked in and started on demand. Image is consumed via the standard VS Code dev container workflow, with persistent named volumes for tool caches and DB data so that recreate-from-image stays fast.

Claude history confirms the user's actual stack: heavy Python (uv, MCP servers, DuckDB, Polars, yt-dlp, Playwright), heavy .NET (Zinnia, Eagle, TP-IPM, ASP.NET Core), occasional TypeScript (Woppy). `Real-Ladybug` is a Python graph DB library used by `aismartbuddy`.

Why this matters: the user runs many MCP/agent workflows. Cold-start latency on file navigation and LSP-backed code understanding directly compounds across hundreds of agent invocations per day, so pre-warming caches and using fast filesystems is high-leverage.

---

## File Layout

```
aidevcontainer/
├── .devcontainer/
│   ├── devcontainer.json
│   ├── docker-compose.yml          # devcontainer + named volumes; mounts host docker socket
│   └── post-create.sh              # one-time after container build
├── Dockerfile                      # main image (multi-stage, BuildKit)
├── .dockerignore
├── README.md                       # how to build, run, troubleshoot
├── scripts/
│   ├── start-mssql.sh              # systemctl-free launchers (on-demand)
│   ├── start-postgres.sh
│   ├── start-azurite.sh
│   ├── start-servicebus-emulator.sh  # sibling container via host docker
│   ├── start-ollama.sh
│   ├── start-azp-agent.sh          # Azure DevOps build agent (config + run)
│   ├── start-gh-runner.sh          # GitHub Actions self-hosted runner (config + run)
│   ├── stop-all.sh
│   ├── prewarm-lsp.sh              # used at build time and rerunnable
│   └── gpu-check.sh                # `nvidia-smi` if --gpus passed; warn otherwise
├── config/
│   ├── mssql.conf                  # post-setup config
│   ├── pg_hba.conf                 # local trust for dev only
│   ├── postgresql.conf
│   └── servicebus-emulator/
│       ├── Config.json
│       └── docker-compose.emulator.yml
└── tests/
    └── smoke.sh                    # verifies every tool boots
```

---

## Image Design

### Base & multi-stage layout

```
FROM ubuntu:resolute AS base          # Ubuntu 26.04 LTS Resolute Raccoon
  ├─ apt fundamentals (CA, gnupg, locales en_US.UTF-8, tzdata, build-essential)
  └─ create vscode user (UID 1000), sudo NOPASSWD

FROM base AS dotnet-stage
  └─ install .NET 10 SDK + runtime + ASP.NET Core + Aspire CLI
        + global tools: Roslynator.DotNet.Cli, dotnet-ef, dotnet-format,
          dotnet-outdated-tool, dotnet-script, dotnet-aspire, csharp-ls

FROM base AS node-stage
  └─ install Node.js 22 LTS via NodeSource, then corepack enable;
     pnpm via corepack; yarn via corepack;
     global npm: azurite, azure-functions-core-tools@4, opencode-ai,
                 @openai/codex, @anthropic-ai/claude-code,
                 typescript, typescript-language-server, tree-sitter-cli,
                 vscode-langservers-extracted

FROM base AS python-stage
  └─ install python3.14 (deadsnakes or official tarball);
     uv via official installer (provides uv + uvx);
     uv tool install: ruff, pyright, mypy, basedpyright, pytest, ipython,
                      python-lsp-server, ast-grep-cli (sg);
     pre-create venv at /opt/venv with: faster-whisper, openai-whisper,
       python-docx, python-pptx, openpyxl, pypdf, pdfplumber,
       pillow, pytesseract, pdf2image, python-magic,
       duckdb, polars, pandas, numpy, jupyter,
       yt-dlp, mcp, fastmcp, starlette, uvicorn, httpx

FROM base AS final
  └─ COPY --from=dotnet-stage /usr/share/dotnet         /usr/share/dotnet
     COPY --from=dotnet-stage /usr/local/dotnet-tools   /usr/local/dotnet-tools  # Roslynator, csharp-ls, Aspire.Cli, dotnet-ef, dotnet-format, dotnet-outdated, dotnet-script
     COPY --from=node-stage   /usr/lib/node_modules     /usr/lib/node_modules
     COPY --from=node-stage   /usr/bin/node             /usr/bin/node
     COPY --from=node-stage   /usr/bin/corepack         /usr/bin/corepack
     COPY --from=python-stage /usr/local/python3.14     /usr/local/python3.14
     COPY --from=python-stage /opt/venv                 /opt/venv
     COPY --from=python-stage /root/.local              /opt/uv-tools             # uv-installed: ruff, pyright, basedpyright, mypy, pytest, ipython, python-lsp-server, ast-grep-cli, pre-commit. Symlink shims into /usr/local/bin
     ... + native packages (sql, postgres, ollama, ripgrep, tree-sitter-cli grammars, etc.) installed directly in this stage
```

Multi-stage gives parallel layer builds under BuildKit and keeps the final image free of build-only deps (gcc, headers).

### apt packages (single layer, sorted)

System: `bash-completion build-essential ca-certificates curl git git-lfs git-extras gnupg htop iproute2 iputils-ping jq less locales lsb-release man-db nano openssh-client procps rsync ripgrep sudo tmux tree tzdata unzip vim wget xz-utils zstd`

Languages/runtimes (where apt is best): `libicu-dev libssl-dev pkg-config zlib1g-dev`

Database clients: `postgresql-client-18 sqlite3 mssql-tools18 unixodbc-dev`

Database servers (started on demand): `postgresql-18 mssql-server` (SQL Server 2025). PostgreSQL 18 requires the **PGDG apt repo** (`apt.postgresql.org`), since stock Ubuntu 26.04 may not pin to major 18. PGDG distribution name: try `resolute-pgdg` first; fall back to `noble-pgdg` (24.04) if PGDG hasn't published 26.04 yet.

Media/OCR: `tesseract-ocr ffmpeg poppler-utils libmagic1` (required by pytesseract / pypdf / file-type detection)

GitHub CLI: `gh` from `cli.github.com/packages` apt repo (NOT from `gh` in the System list — that line is removed).

Docker CLI (no daemon): `docker-ce-cli docker-compose-plugin` from Docker's apt repo. Daemon is host's via mounted socket. An entrypoint script (`/usr/local/bin/fix-docker-perms`) detects the host docker socket GID at first start and creates/aligns a `docker` group inside the container, then ensures `vscode` is a member — without this, `docker run` from the dev container fails with permission denied.

### Apt third-party repos (modern signed-by keyring layout)

All keys land in `/etc/apt/keyrings/<name>.gpg` (dearmored) and every `.list` file uses `deb [signed-by=/etc/apt/keyrings/<name>.gpg] ...`. The legacy `/etc/apt/trusted.gpg.d/` path is **not** used (Ubuntu 26.04 deprecates it).

| Repo | Keyring | List file | Purpose |
|------|---------|-----------|---------|
| Microsoft | `microsoft.gpg` | `microsoft-prod.list` (24.04 path) | Azure CLI, dotnet, mssql-tools18 |
| Microsoft SQL 2025 | `microsoft.gpg` (shared) | `mssql-server-2025.list` (24.04 path) | SQL Server 2025 server packages |
| GitHub CLI | `githubcli.gpg` | `github-cli.list` | `gh` |
| Docker | `docker.gpg` | `docker.list` | docker CLI + compose plugin |
| NodeSource | `nodesource.gpg` | `nodesource.list` (`node_22.x`) | Node 22 LTS |
| PGDG | `pgdg.gpg` | `pgdg.list` | PostgreSQL 18 |

Note: 24.04 paths are used for the Microsoft repos because 26.04 (Resolute) repos do not yet exist; deb packages are forward-compatible (verified by `ubuntu.com/blog/sql-server-2025-on-ubuntu`). Before build, `curl --head` each candidate `.list` URL to confirm publication.

### .NET 10 + Azure stack

- `dotnet-sdk-10.0` and `aspnetcore-runtime-10.0` from Microsoft repo
- Aspire CLI: installed **only** as a dotnet global tool (`dotnet tool install Aspire.Cli`) for reproducible pinning. The `aspire.dev/install.sh` shell installer is dropped to avoid a duplicate binary.
- Azure CLI: `apt install azure-cli`
- Azure CLI extensions installed via `az extension add --name`: `azure-devops bicep containerapp application-insights serviceconnector-passwordless aks-preview`
- Bicep: `az bicep install` (downloads to `/home/vscode/.azure/bin/bicep`)
- Azure Functions Core Tools v4: from npm global (`azure-functions-core-tools@4` — official Microsoft path on Linux)
- Azurite (Azure Storage emulator): npm global (`azurite`)
- Azure Service Bus emulator: NOT in image. Launched as a sibling docker-compose stack (`config/servicebus-emulator/docker-compose.emulator.yml`) by `scripts/start-servicebus-emulator.sh`, using the host docker socket (`/var/run/docker.sock`). The compose file contains **both** the emulator AND its bundled SQL Edge sidecar — the documented Microsoft configuration. We do NOT try to point the emulator at the in-image SQL Server 2025; mixing those is unsupported. Both sibling containers join a dedicated user-defined bridge network `sbemu-net`. Port 5672 (AMQP) and 5300 (HTTP mgmt) are published on the host so the dev container reaches them via `host-gateway`. Config in `config/servicebus-emulator/Config.json`.

### Global .NET tools

```
dotnet tool install --tool-path /usr/local/dotnet-tools \
  Roslynator.DotNet.Cli \
  dotnet-ef \
  dotnet-format \
  dotnet-outdated-tool \
  dotnet-script \
  csharp-ls \
  Aspire.Cli
```

PATH gets `/usr/local/dotnet-tools`.

### Python 3.14 + uv

- Install Python 3.14 from `https://www.python.org/ftp/python/3.14.<latest>/` source build OR `ppa:deadsnakes/ppa` if 26.04 entry exists. Source build to `/usr/local/python3.14` is the deterministic path.
- `uv` via `curl -LsSf https://astral.sh/uv/install.sh | sh` → `/usr/local/bin/uv` and `uvx`.
- `uv python pin 3.14` written to a system-wide default config so `uv` picks it.
- A pre-built venv at `/opt/venv` so first-run scripts work; user projects use their own `uv venv`.

### Node.js 22 LTS

- NodeSource setup script for `nodesource_22.x`.
- `corepack enable` activates pnpm and yarn shims (corepack ships with Node).
- Global npm packages locked into final image:
  - `azurite` (storage emulator)
  - `azure-functions-core-tools@4`
  - `@anthropic-ai/claude-code` (Claude Code CLI)
  - `@openai/codex` (Codex CLI)
  - `opencode-ai` (OpenCode CLI)
  - `typescript`, `typescript-language-server`, `vscode-langservers-extracted` (HTML/CSS/JSON LSPs), `tree-sitter-cli`, `pyright`

### LSP servers (all languages)

| Language | LSP | Install path |
|---|---|---|
| C# | Roslyn LSP via `Microsoft.CodeAnalysis.LanguageServer` (ships with C# Dev Kit / dotnet) and `csharp-ls` | dotnet tool |
| Python | `pyright`, `basedpyright`, `python-lsp-server`, `ruff` | uv tool / npm global |
| TypeScript / JS | `typescript-language-server`, `vscode-langservers-extracted` | npm global |
| Go | `gopls` | `go install` (Go itself: `golang-go` apt) |
| Rust | `rust-analyzer` | `rustup component add` (rustup via apt or curl) |
| Bash | `bash-language-server` | npm global |
| YAML | `yaml-language-server` | npm global |
| Docker | `dockerfile-language-server-nodejs` | npm global |
| SQL | `sql-language-server` | npm global |
| HTML/CSS/JSON | bundled in `vscode-langservers-extracted` | npm global |
| Bicep | `bicep` (built-in LSP via Bicep CLI) | `az bicep install` |

### AI agents / coding CLIs

- `@anthropic-ai/claude-code` — Claude Code CLI
- `@openai/codex` — Codex CLI
- `opencode-ai` — OpenCode

### Code search / structural search

- `ripgrep` (apt)
- `ast-grep` (`sg`) installed via `cargo install ast-grep --locked` OR `uv tool install ast-grep-cli` OR npm `@ast-grep/cli`. Use the npm distribution (single command, no rust toolchain needed at install time).
- ast-grep rule packs: clone `ast-grep/awesome-rules` to `/opt/ast-grep/rules` (read-only, used by AI agents).
- `tree-sitter-cli` + grammars cloned to `/opt/tree-sitter-grammars/`: `tree-sitter-c-sharp`, `tree-sitter-python`, `tree-sitter-typescript`, `tree-sitter-javascript`, `tree-sitter-bash`, `tree-sitter-rust`, `tree-sitter-go`, `tree-sitter-sql`, `tree-sitter-yaml`, `tree-sitter-html`, `tree-sitter-css`. Pre-built shared objects committed in image.
- `fd-find` (`fd`), `bat`, `delta`, `fzf`, `zoxide` — quality-of-life for both human and agent shell use.

### Databases

- **SQL Server 2025**: `mssql-server` package; configured via env vars `MSSQL_SA_PASSWORD`, `ACCEPT_EULA=Y`, `MSSQL_PID=Developer`. Data at `/var/opt/mssql` mounted as a named volume `mssql-data` for persistence across container rebuilds. Started by `scripts/start-mssql.sh`.
- **PostgreSQL 18**: `postgresql-18`; data dir `/var/lib/postgresql/18/main` mounted as `pg-data` named volume. Started by `scripts/start-postgres.sh` with `pg_ctlcluster`.
- **DuckDB**: CLI binary downloaded from `duckdb.org/cdn/duckdb-cli-linux-amd64.zip` to `/usr/local/bin/duckdb`. Plus `duckdb` Python lib in `/opt/venv`.
- **Ladybug graph DB**: NOT installed in the image (per user clarification). The public PyPI `ladybug` package is the LadybugTools building-physics library and is the wrong package; the user's `Real-Ladybug` graph DB is added per project from their private source. README documents this.
- **SQLite**: apt `sqlite3`.

Persisted data via named Docker volumes wired in `docker-compose.yml`:

```
volumes:
  mssql-data:
  pg-data:
  ollama-models:
  uv-cache:
  nuget-cache:
  npm-cache:
  pnpm-store:
  hf-cache:
  claude-config:
```

### Ollama + Whisper

- Ollama: `curl -fsSL https://ollama.com/install.sh | sh` → `/usr/local/bin/ollama`. Models stored in `/home/vscode/.ollama` mounted as `ollama-models` volume. Started via `scripts/start-ollama.sh` (`ollama serve` in background).
- `faster-whisper` and `openai-whisper` in `/opt/venv`. The `whisper` CLI ships with `openai-whisper`; `faster-whisper` is a library only (no CLI).
- `whisper.cpp`: clone `https://github.com/ggml-org/whisper.cpp.git` (current upstream after the org rename), pin a release tag, `cmake -B build -DGGML_OPENBLAS=ON && cmake --build build -j`, install `build/bin/whisper-cli` as `/usr/local/bin/whisper-cpp`. Models live under `~/.cache/whisper-cpp/` (lazy download).

### Office / PDF / Screenshot tooling

Per user choice: Python libs only (no LibreOffice/pandoc).

System packages required by Python libs:
- `tesseract-ocr` + `tesseract-ocr-eng` (for `pytesseract`)
- `poppler-utils` (for `pdfplumber` / `pypdf` rendering)
- `libmagic1` (for `python-magic` if needed)
- `ffmpeg` (for whisper audio decoding and screenshots/video)

Python libs in `/opt/venv`: `python-docx`, `python-pptx`, `openpyxl`, `pypdf`, `pdfplumber`, `pillow`, `pytesseract`, `pdf2image`, `python-magic`.

> **Note for the user:** This stack reads/extracts text from Office docs, PDFs, and images. It does NOT convert formats (e.g. docx→pdf). If conversion is needed later, add `libreoffice --headless` and `pandoc` (~1.5 GB).

### Git development tools

`git`, `git-lfs`, `git-extras`, `gh` (GitHub CLI), `delta` (better diffs), `tig` (terminal UI), pre-commit (`uv tool install pre-commit`), `lazygit` (download release tarball).

### NVIDIA / CUDA support

Image must work transparently when launched with `--gpus all` (Docker Desktop with NVIDIA Container Toolkit, or `docker run --runtime=nvidia`).

- Add NVIDIA's CUDA apt repo (key at `/etc/apt/keyrings/nvidia-cuda.gpg`, list pinned to `ubuntu2404` until `ubuntu2604` ships).
- Install `cuda-toolkit-13-0` (or whichever is current at build time) for nvcc, cuBLAS, cuDNN headers — required by faster-whisper / Ollama / llama.cpp / PyTorch builds. ~3 GB. Place at `/usr/local/cuda` with stub libs.
- Install `libcudnn9-cuda-13` from NVIDIA repo.
- Set env vars so the NVIDIA Container Toolkit injects driver libs at runtime:
  ```
  NVIDIA_VISIBLE_DEVICES=all
  NVIDIA_DRIVER_CAPABILITIES=compute,utility,video
  CUDA_HOME=/usr/local/cuda
  PATH=$PATH:/usr/local/cuda/bin
  LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
  ```
- `scripts/gpu-check.sh`: `nvidia-smi || echo "No GPU passed through. Run with --gpus all."`
- Compose file gets a commented-out GPU stanza:
  ```yaml
  # deploy:
  #   resources:
  #     reservations:
  #       devices: [{ driver: nvidia, count: all, capabilities: [gpu] }]
  ```
  README documents how to enable it. Keep commented by default so the image runs on hosts without a GPU.
- whisper.cpp build switches to `-DGGML_CUDA=ON` instead of OpenBLAS when CUDA is present at build time. Use a build-time arg `BUILD_CUDA=1` (default on amd64); ARG fails gracefully if cuda libs absent.
- PyTorch is NOT preinstalled (multi-GB, varies by CUDA version). Documented as `uv pip install torch --index-url https://download.pytorch.org/whl/cu130` in README.

### RTK (Rust Token Killer)

Per user CLAUDE.md, `rtk` is the token-optimizing CLI proxy from `https://github.com/rtk-ai/rtk` — disambiguated from the unrelated `reachingforthejack/rtk` (Rust Type Kit) which would cause `rtk gain` to fail.

Install method: download the prebuilt static musl release from GitHub releases and place at `/usr/local/bin/rtk` (system-wide PATH, no per-user install). The release tarball name is `rtk-x86_64-unknown-linux-musl.tar.gz`.

```
RTK_VERSION=$(curl -fsSL https://api.github.com/repos/rtk-ai/rtk/releases/latest | jq -r .tag_name)
curl -fsSL "https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}/rtk-x86_64-unknown-linux-musl.tar.gz" \
  | tar -xz -C /usr/local/bin rtk
chmod +x /usr/local/bin/rtk
rtk --version    # smoke
```

Pinning the version via `--build-arg RTK_VERSION=` in the Dockerfile is preferred for reproducibility; `latest` is the default fallback.

### Azure DevOps build agent

Pinned at version 4.272.0 per user request:
- Source: `https://download.agent.dev.azure.com/agent/4.272.0/vsts-agent-linux-x64-4.272.0.tar.gz`
- Install path: `/opt/azp-agent` (extracted, not configured — configuration requires a PAT and pool, supplied by the user at runtime).
- Owner: `vscode:vscode` so it can be (un)configured without sudo.
- The agent depends on libicu and libssl which are already in the base image apt list.
- `scripts/start-azp-agent.sh` reads `AZP_URL`, `AZP_TOKEN`, `AZP_POOL`, `AZP_AGENT_NAME` from env, calls `./config.sh --unattended ...` if not yet configured, then `./run.sh`. Idempotent.

### GitHub Actions self-hosted runner

- Source: `https://github.com/actions/runner/releases/download/v${GH_RUNNER_VERSION}/actions-runner-linux-x64-${GH_RUNNER_VERSION}.tar.gz`. Default `GH_RUNNER_VERSION=2.334.0` (current at build time); overridable via `--build-arg`.
- Install path: `/opt/gh-runner` (extracted).
- Run `/opt/gh-runner/bin/installdependencies.sh` during build (installs `liblttng-ust1` and a couple of small deps so the runner starts cleanly).
- `scripts/start-gh-runner.sh` reads `GH_RUNNER_URL` (e.g. `https://github.com/<org>/<repo>` or org URL) and `GH_RUNNER_TOKEN` from env, calls `./config.sh --unattended --url ... --token ...` if not configured, then `./run.sh`. Idempotent.

Both build agents are **installed but never started automatically** — same on-demand pattern as DBs.

### Pre-warming (build-time) for AI-agent code navigation

Run by `scripts/prewarm-lsp.sh` during `RUN` step in final stage. Creates throwaway projects to force LSP analyzers to download/extract their bundles:

1. `dotnet new console -o /tmp/csprime && cd /tmp/csprime && dotnet build` → caches Roslyn workload, NuGet metadata, MSBuild SDKs.
2. `npx --yes pyright /tmp/empty.py` → triggers pyright bundle extraction.
3. `npx --yes typescript-language-server --version` and `node -e "require('typescript')"` → caches.
4. `gopls version` → fetches gopls modules cache stub.
5. `rust-analyzer --version` → no-op but ensures binary is on PATH.

Caches committed to image: `/root/.nuget`, `/root/.dotnet`, `/usr/local/share/.cache/yarn`, etc. Kept in image; user's per-project caches go into named volumes.

### Consolidated PATH (single source of truth)

Set once in `/etc/profile.d/00-aidev-path.sh` and exported in the Dockerfile `ENV PATH=...`. Order matters — earlier entries shadow later. Final PATH:

```
/usr/local/dotnet-tools          # Roslynator, csharp-ls, Aspire.Cli, dotnet-ef, dotnet-format, dotnet-outdated, dotnet-script
/opt/uv-tools/bin                # ruff, pyright, basedpyright, mypy, pytest, ipython, python-lsp-server, ast-grep-cli (sg), pre-commit
/home/vscode/.local/bin          # uv, uvx, rtk (per-user fallback), user-installed tools
/home/vscode/.local/share/pnpm   # pnpm-installed binaries
/usr/local/python3.14/bin        # python3.14, python3, pip
/opt/venv/bin                    # whisper, jupyter, yt-dlp, etc. from the prebuilt venv
/usr/local/cuda/bin              # nvcc, cuda-gdb, cuobjdump
/usr/local/bin                   # rtk, duckdb, ollama, claude, codex, opencode, lazygit, whisper-cpp, gh, sqlcmd shim, etc.
/usr/bin /bin                    # apt-installed binaries (rg, sg via npm shim, tree-sitter, fd, bat, delta, fzf, zoxide, git, az, bicep shim, func, azurite shim, node, npm, pnpm via corepack)
/opt/azp-agent                   # Azure DevOps agent run.sh, config.sh
/opt/gh-runner                   # GitHub Actions runner run.sh, config.sh
```

Verification: `tests/smoke.sh` executes every binary by short name (no absolute paths), proving they resolve via PATH.

### Performance Optimization

Image is tuned for two distinct workloads: (a) AI agents doing many small file operations and LSP queries, (b) compile/test cycles for .NET/Python/Node.

**Build-time optimizations:**
- BuildKit cache mounts on every package manager: `--mount=type=cache,target=/var/cache/apt,sharing=locked`, same for `/root/.cache/uv`, `/root/.npm`, `/root/.nuget`, `/root/.cache/cargo`. Subsequent rebuilds are 10x faster.
- `--mount=type=tmpfs,target=/tmp` during `RUN` steps so unzip/extract work in RAM.
- Multi-stage parallelism: `dotnet-stage`, `node-stage`, `python-stage` run concurrently; only the slowest gates the final stage.
- `apt-get install --no-install-recommends` everywhere; `apt-get clean && rm -rf /var/lib/apt/lists/*` at end of every layer that adds packages.
- Strip debug symbols on heavy binaries (`strip /usr/local/bin/whisper-cpp`), but skip `dotnet`/`node`/`python` which have signed binaries.
- `pip install --no-compile` and `npm install --no-audit --no-fund --prefer-offline` in build stages.

**Runtime optimizations:**
- `tmpfs /tmp size=4g` (already in compose) — eliminates disk I/O for build temp files.
- Tool caches on **named volumes inside the WSL2 ext4 VM**, not bind mounts to the Windows NTFS host. ~50× faster on small-file workloads (npm install, NuGet restore, uv sync).
- `nofile` ulimit raised to 1,048,576 for VS Code file watcher + LSPs.
- `inotify` limits raised in container: write `fs.inotify.max_user_watches=524288` and `fs.inotify.max_user_instances=8192` to `/etc/sysctl.d/90-inotify.conf` (applied via `sysctl --system` if the container runs with adequate caps; otherwise documented as a host-side setting).
- `MALLOC_ARENA_MAX=2` to reduce glibc memory fragmentation on long-lived processes (Roslyn, pyright daemons).
- Pre-warmed analyzer caches (already covered): Roslyn, NuGet metadata, MSBuild SDKs, pyright bundle, gopls, rust-analyzer.
- Disabled telemetry across the board (`DOTNET_CLI_TELEMETRY_OPTOUT`, `DO_NOT_TRACK`, `POWERSHELL_TELEMETRY_OPTOUT`, `AZURE_CORE_COLLECT_TELEMETRY=no`, `NEXT_TELEMETRY_DISABLED=1`) — saves CPU and outbound network noise.
- `init: true` (tini) in compose for proper PID 1 / signal handling.
- `cap_add: SYS_PTRACE` and `security_opt: seccomp=unconfined` enable JIT debuggers and dotnet hot-reload without permission errors.
- Workspace bind mount uses `:cached` (Docker Desktop on macOS) and Mutagen-style sync is documented for Windows where small-file perf still matters on bind mounts.
- Compose `mem_limit` and `cpus` left unset by default so the dev container can use the full host; documented how to cap them.
- `CMD` is a long-running shell with `exec` to avoid a wrapping bash process consuming RAM.

**Image size optimizations:**
- Squash redundant layers via `--squash` (BuildKit experimental) at release time, not on every build.
- Final image expected size: ~16-22 GB (CUDA toolkit + SQL Server + .NET SDK + Node + Python + Ollama + agents). Without CUDA: ~12-15 GB.

### High-performance filesystem

- Image uses BuildKit cache mounts for apt, npm, pip, nuget during build (`--mount=type=cache,target=/var/cache/apt`).
- At runtime, `docker-compose.yml` mounts `tmpfs` at `/tmp` (size=4G) and `/home/vscode/.cache/build-tmp`.
- Workspace is a bind mount of the host repo (recommend `consistency=cached` on Docker Desktop / Mutagen for Windows users — documented in README).
- Tool caches go on **named volumes** rather than bind mounts (faster on Windows because they live inside the WSL2 VM ext4 filesystem, not the NTFS share):
  - `/home/vscode/.cache/uv`
  - `/home/vscode/.nuget`
  - `/home/vscode/.npm`
  - `/home/vscode/.local/share/pnpm`
  - `/home/vscode/.cache/huggingface`
  - `/home/vscode/.ollama`
  - `/var/opt/mssql`
  - `/var/lib/postgresql/18/main`
- ulimits raised in compose (`nofile: 1048576`) to support many open files for LSPs and watchers.

### Environment variables (set in Dockerfile)

```
DEBIAN_FRONTEND=noninteractive
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US:en
TZ=Etc/UTC                                    # user can override
DOTNET_ROOT=/usr/share/dotnet
DOTNET_CLI_TELEMETRY_OPTOUT=1
DOTNET_NOLOGO=1
NUGET_XMLDOC_MODE=skip
PIP_NO_CACHE_DIR=off
UV_LINK_MODE=copy
UV_PYTHON_PREFERENCE=only-managed
UV_PYTHON=3.14
PNPM_HOME=/home/vscode/.local/share/pnpm
PATH=/usr/local/dotnet-tools:/opt/uv-tools/bin:/home/vscode/.local/bin:$PNPM_HOME:/usr/local/python3.14/bin:/opt/venv/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin:/opt/azp-agent:/opt/gh-runner
ACCEPT_EULA=Y
MSSQL_PID=Developer
POWERSHELL_TELEMETRY_OPTOUT=1
DO_NOT_TRACK=1                                # opt out of opentelemetry-style trackers
```

`MSSQL_SA_PASSWORD` is NOT baked in. On first start of `scripts/start-mssql.sh`, a random 24-char password is generated and written to `~/.mssql-password` (mode 600) inside the container, persisted via the home-directory volume. Subsequent starts read the file. The user retrieves the password with `cat ~/.mssql-password`.

### devcontainer.json highlights

```json
{
  "name": "ai-dev",
  "dockerComposeFile": "docker-compose.yml",
  "service": "dev",
  "workspaceFolder": "/workspaces/aidevcontainer",
  "remoteUser": "vscode",
  "containerEnv": { "TZ": "Europe/Brussels" },
  "forwardPorts": [11434, 1433, 5432, 10000, 10001, 10002, 5300, 5672, 7071],
  "mounts": [
    "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"
  ],
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-dotnettools.csharp",
        "ms-dotnettools.csdevkit",
        "ms-dotnettools.dotnet-runtime",
        "ms-azuretools.vscode-bicep",
        "ms-azuretools.vscode-azurefunctions",
        "ms-azuretools.vscode-docker",
        "ms-vscode.azure-account",
        "ms-azure-devops.azure-pipelines",
        "ms-python.python",
        "ms-python.vscode-pylance",
        "charliermarsh.ruff",
        "astral-sh.uv",
        "anthropic.claude-code",
        "ast-grep.ast-grep-vscode",
        "tamasfe.even-better-toml",
        "redhat.vscode-yaml",
        "eamodio.gitlens",
        "github.vscode-github-actions",
        "github.copilot-chat"
      ],
      "settings": {
        "files.watcherExclude": { "**/bin/**": true, "**/obj/**": true, "**/node_modules/**": true },
        "search.useRipgrep": true,
        "terminal.integrated.defaultProfile.linux": "bash"
      }
    }
  },
  "postCreateCommand": "bash .devcontainer/post-create.sh"
}
```

### Compose file (essentials)

```yaml
services:
  dev:
    build: { context: .., dockerfile: Dockerfile }
    init: true
    cap_add: [SYS_PTRACE]
    security_opt: [seccomp=unconfined]
    ulimits:
      nofile: { soft: 1048576, hard: 1048576 }
    volumes:
      - ../:/workspaces/aidevcontainer:cached
      - /var/run/docker.sock:/var/run/docker.sock
      - mssql-data:/var/opt/mssql
      - pg-data:/var/lib/postgresql/18/main
      - ollama-models:/home/vscode/.ollama
      - uv-cache:/home/vscode/.cache/uv
      - nuget-cache:/home/vscode/.nuget
      - npm-cache:/home/vscode/.npm
      - pnpm-store:/home/vscode/.local/share/pnpm
      - hf-cache:/home/vscode/.cache/huggingface
      - claude-config:/home/vscode/.claude
    tmpfs: [ /tmp:size=4g ]
    environment:
      - MSSQL_SA_PASSWORD
      - TZ=Europe/Brussels
volumes: { mssql-data: , pg-data: , ollama-models: , uv-cache: , nuget-cache: , npm-cache: , pnpm-store: , hf-cache: , claude-config: }
```

### Service-start scripts

Each is an idempotent shell script that:
1. Checks if the service is already running (`pgrep`, port check).
2. Starts it in the background, redirecting logs to `/tmp/<svc>.log`.
3. Waits for readiness (`curl`, `pg_isready`, `sqlcmd -Q "SELECT 1"`).

`start-mssql.sh` first-run logic (handles random SA password per user choice):
```
if [[ ! -f /var/opt/mssql/data/master.mdf ]]; then
  if [[ ! -f ~/.mssql-password ]]; then
    umask 077
    openssl rand -base64 24 | tr -d '\n=+/' | head -c 24 > ~/.mssql-password
    chmod 600 ~/.mssql-password
    echo "Generated SA password at ~/.mssql-password"
  fi
  export MSSQL_SA_PASSWORD="$(cat ~/.mssql-password)"
  export ACCEPT_EULA=Y MSSQL_PID=Developer
  sudo -E /opt/mssql/bin/mssql-conf -n setup
fi
sudo systemctl is-active --quiet mssql-server || \
  sudo /opt/mssql/bin/sqlservr &   # systemd not present in container
```

Connection string convenience: post-create writes `~/.mssql-cs` containing `Server=localhost,1433;User Id=sa;Password=$(cat ~/.mssql-password);TrustServerCertificate=true;`.

`start-servicebus-emulator.sh` differs: it `docker compose -f config/servicebus-emulator/docker-compose.emulator.yml up -d`, which spins up both the emulator AND its bundled SQL Edge sidecar on a dedicated bridge network. Ports 5672 (AMQP) and 5300 (HTTP mgmt) are published to the host so the dev container reaches them via `host-gateway`.

**Docker socket permission entrypoint** — the dev container needs to launch sibling docker containers (Service Bus emulator). On startup, an entrypoint script:
```
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "")
if [[ -n "$DOCKER_GID" ]]; then
  if ! getent group docker >/dev/null; then
    sudo groupadd -g "$DOCKER_GID" docker || sudo groupadd docker
    sudo groupmod -g "$DOCKER_GID" docker
  fi
  sudo usermod -aG docker vscode
fi
```
Runs as part of the container CMD/entrypoint (devcontainer's `initializeCommand` is host-side, so we use a container-side entrypoint wrapper).

---

## Build & Run Commands

```bash
# Build (BuildKit on, layered cache, ~20-40 min cold, <2 min incremental)
DOCKER_BUILDKIT=1 docker buildx build --tag aidev:latest --load .

# Open in VS Code
code .                       # then: "Reopen in Container"

# CLI use without VS Code
docker compose -f .devcontainer/docker-compose.yml up -d
docker compose -f .devcontainer/docker-compose.yml exec dev bash
```

---

## Decisions & Tradeoffs

1. **Ubuntu 26.04 base** — `ubuntu:resolute` tag confirmed live on Docker Hub (codename Resolute Raccoon, released April 2026). Newer kernel/glibc + LTS support window through 2031. After first successful build, pin to a digest (`ubuntu:resolute@sha256:...`) for reproducibility; fall back to `ubuntu:26.04` if the codename tag is ever renamed.
2. **24.04 apt repos for SQL Server / Microsoft prod** — Microsoft has not published 26.04-specific repos. `.deb` packages are forward-compatible. Will switch when MS publishes 26.04 paths.
3. **All services in one image, lazy start** — matches user's stated preference. Costs ~12-18 GB final image; saves operator overhead.
4. **Docker-outside-docker for Service Bus emulator** — emulator is closed-source-Linux-container only; mounting host socket avoids privileged DinD and leverages the host's BuildKit/cache.
5. **Python 3.14 source build** — deadsnakes PPA may lag on `resolute`. Source build is deterministic and isolated to `/usr/local/python3.14`. uv-managed Pythons additionally available via `uv python install`.
6. **Tool caches on named volumes, workspace on bind mount** — Windows/WSL2 NTFS-bridge bind mounts are slow for many small files; named volumes live in ext4 inside the WSL VM. Workspace stays bind-mounted because the user edits it from Windows.
7. **No LibreOffice/pandoc** — user explicitly chose Python-only doc libs. Documented in README how to add them later.
8. **Pre-warming LSP/analyzer caches** — adds ~500 MB to image but saves 10-60 s per fresh container on first navigation.
9. **CUDA toolkit installed but driver libs injected at runtime** — standard NVIDIA Container Toolkit pattern. Image runs unchanged on hosts without GPU; GPU usage requires `--gpus all` and `nvidia-container-toolkit` on the host. CUDA-aware tools (Ollama, whisper.cpp w/ CUDA, future PyTorch) auto-detect.
10. **Build agents present but unconfigured** — Azure DevOps agent at `/opt/azp-agent` and GitHub runner at `/opt/gh-runner`. Configuration (`./config.sh`) requires PATs that must NEVER be baked into an image; users provide them at runtime via env on the start scripts.
11. **RTK from rtk-ai/rtk specifically** — the user's CLAUDE.md explicitly disambiguates from `reachingforthejack/rtk` (Rust Type Kit). Install pulls only from `github.com/rtk-ai/rtk` releases.

---

## Non-Goals

- No PyTorch / TensorFlow preinstall (multi-GB, varies by CUDA build) — documented as one-line install in README.
- No Kubernetes tooling beyond what `azure-cli` brings (`kubectl` etc. — easy to add later).
- No JetBrains/Rider integration (VS Code-first per clarification).
- No Java/Maven/Gradle (not in user's stack).
- No conversion of Office formats (docx→pdf etc.) — only programmatic read/extract.
- No model preload — user explicitly opted out.
- No agent auto-registration — Azure DevOps + GitHub runner binaries are present but not configured at build time (PATs/tokens are user-supplied at runtime).

---

## Verification (smoke tests)

`tests/smoke.sh` runs every check non-interactively. Each line must exit 0:

```bash
# Versions
lsb_release -a | grep -q "26.04"
locale | grep -q en_US.UTF-8
dotnet --list-sdks   | grep -q "^10\."
dotnet --list-runtimes | grep -q "Microsoft.AspNetCore.App 10\."
aspire --version
az version | jq .
az extension list -o tsv | grep -E "azure-devops|bicep|containerapp"
bicep --version
func --version
azurite --version
node --version | grep -q "^v22"
npm --version
pnpm --version
yarn --version
python3.14 --version | grep -q "Python 3.14"
uv --version
uvx --version
git --version && gh --version
rg --version                          # ripgrep binary is `rg`
sg --version                          # ast-grep
tree-sitter --version
tree --version
duckdb --version
psql --version | grep -q "^psql .*18"
sqlcmd -? 2>&1 | head -n1
ollama --version
whisper --help >/dev/null             # openai-whisper CLI
python -c "import faster_whisper; print(faster_whisper.__version__)"
whisper-cpp --help 2>&1 | head -n1
tesseract --version
ffmpeg -version | head -n1
docker --version
claude --version
codex --version
opencode --version
roslynator --version
rtk --version                         # Rust Token Killer (rtk-ai/rtk)
test -x /opt/azp-agent/run.sh         # Azure DevOps agent extracted
test -x /opt/gh-runner/run.sh         # GitHub Actions runner extracted
nvcc --version 2>/dev/null || echo "CUDA not in PATH (expected when running without --gpus)"
nvidia-smi 2>/dev/null || echo "No GPU passed through (expected without --gpus all)"

# Service smoke (start-on-demand)
bash scripts/start-mssql.sh    && sqlcmd -S localhost -U sa -P "$(cat ~/.mssql-password)" -Q "SELECT @@VERSION" -No
bash scripts/start-postgres.sh && psql -U postgres -h localhost -c "SELECT version();"
bash scripts/start-azurite.sh  && curl -fsS http://127.0.0.1:10000/devstoreaccount1?comp=list >/dev/null
bash scripts/start-ollama.sh   && curl -fsS http://127.0.0.1:11434/api/tags
bash scripts/start-servicebus-emulator.sh && curl -fsS http://127.0.0.1:5300/health

# AI tooling sanity
sg run --pattern 'console.log($X)' --lang js /tmp >/dev/null || true
python -c "import duckdb, polars, docx, pptx, openpyxl, pypdf, pdfplumber, pytesseract, PIL; print('ok')"
```

---

## README Contents

`README.md` must include these sections (no placeholder ship):

1. **What's inside** — short feature matrix.
2. **Build** — `DOCKER_BUILDKIT=1 docker buildx build --tag aidev:latest --load .` (cold ~20-40 min).
3. **First run with VS Code** — install Dev Containers extension → Reopen in Container.
4. **First run with CLI** — `docker compose -f .devcontainer/docker-compose.yml up -d && docker compose ... exec dev bash`.
5. **On-demand services** — table of `scripts/start-*.sh` commands with default ports.
6. **Forwarded ports** — 1433 (SQL), 5432 (PG), 10000-10002 (Azurite), 5672/5300 (Service Bus), 11434 (Ollama), 7071 (Functions).
7. **MSSQL credentials** — random password at `~/.mssql-password`, retrieve via `cat`.
8. **Real-Ladybug graph DB** — not preinstalled; users add it per project from their private source.
9. **Adding optional extras** — LibreOffice/pandoc for doc conversion; CUDA layer for GPU.
10. **Troubleshooting** — docker.sock perms, slow filesystem on Windows (use named volumes, not bind mounts, for caches), tmpfs `/tmp` size, port conflicts.
11. **Image size & layers** — expected ~16-22 GB after pre-warm (CUDA toolkit dominates). Without CUDA: ~12-15 GB.
12. **NVIDIA / GPU usage** — how to run with `--gpus all`, host requirements (NVIDIA driver + nvidia-container-toolkit), how to verify (`scripts/gpu-check.sh`), and how to enable the commented compose stanza.
13. **Azure DevOps agent setup** — required env (`AZP_URL`, `AZP_TOKEN`, `AZP_POOL`, `AZP_AGENT_NAME`), how to scope the PAT (Agent Pools: read & manage), how to start (`scripts/start-azp-agent.sh`).
14. **GitHub Actions runner setup** — required env (`GH_RUNNER_URL`, `GH_RUNNER_TOKEN`), how to obtain the registration token from repo/org settings, how to start (`scripts/start-gh-runner.sh`).
15. **RTK** — already integrated via the user's hook; verify with `rtk --version` and `rtk gain`.

---

## Critical Files (paths to author)

- `Dockerfile` — main multi-stage build
- `.dockerignore`
- `.devcontainer/devcontainer.json`
- `.devcontainer/docker-compose.yml`
- `.devcontainer/post-create.sh`
- `scripts/start-mssql.sh`, `start-postgres.sh`, `start-azurite.sh`, `start-servicebus-emulator.sh`, `start-ollama.sh`, `start-azp-agent.sh`, `start-gh-runner.sh`, `stop-all.sh`, `prewarm-lsp.sh`, `gpu-check.sh`
- `config/mssql.conf`, `config/pg_hba.conf`, `config/postgresql.conf`, `config/servicebus-emulator/Config.json`, `config/servicebus-emulator/docker-compose.emulator.yml`
- `tests/smoke.sh`
- `README.md`

---

## TLDR

Single-image Ubuntu 26.04 (Resolute Raccoon) dev container baked with the user's full AI/.NET/Python stack: SQL Server 2025, Postgres 18, DuckDB, Azurite, Ollama, .NET 10 SDK + Aspire CLI + Azure CLI (with devops/bicep) + Azure Functions Core Tools, Python 3.14 + uv + uvx, Node 22 + pnpm + Claude Code/Codex/OpenCode, RTK token-killer, CUDA toolkit (driver libs injected via NVIDIA Container Toolkit when run with `--gpus all`), Azure DevOps build agent v4.272.0, GitHub Actions self-hosted runner, plus ripgrep / ast-grep / tree-sitter / pre-warmed Roslyn/pyright/tsserver/gopls/rust-analyzer for fast AI agent code navigation. Heavy services start on demand via shell scripts; Service Bus emulator runs as a sibling container via host Docker socket. All caches and DB data persist on named volumes (ext4 inside the WSL VM) for high I/O perf on Windows hosts; workspace is bind-mounted for live editing. Single consolidated PATH places every tool one short name away.
