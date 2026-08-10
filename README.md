# ai-dev — high-performance dev container for AI software development

Single-image Ubuntu 26.04 LTS (Resolute Raccoon) dev container that bundles the full AI / .NET / Python / Node stack used for agentic software development.

## What's inside

| Category | Tools |
|---|---|
| **OS** | Ubuntu 26.04 LTS, `en_US.UTF-8`, `vscode` user (UID 1000, passwordless sudo) |
| **.NET** | SDK 10 (apt) + SDK 11 preview (via dotnet-install.sh, side-by-side), ASP.NET Core 10 + 11 runtimes, Aspire CLI, Roslynator, dotnet-ef, dotnet-format, dotnet-script, csharp-ls, dotnet-outdated. Workloads pre-updated; HTTPS dev cert trusted for the `vscode` user via prewarm. Telemetry disabled (`DOTNET_CLI_TELEMETRY_OPTOUT=1`). |
| **Azure** | Azure CLI (apt) + extensions (azure-devops, serviceconnector-passwordless, containerapp [preview], application-insights [preview], aks-preview), `az bicep` built-in, Azure Functions Core Tools v4, Azurite |
| **Python** | Ubuntu's apt `python3` (whatever 26.04 ships, currently 3.13.x), `python-is-python3`, plus uv-managed **Python 3.11** and **3.14** on PATH as `python3.11` / `python3.14`. `uv` + `uvx`. uv-managed dev tools: ruff, pyright, basedpyright, mypy, pytest, ipython, python-lsp-server, pre-commit. Prebuilt venv at `/opt/venv` (huggingface_hub + `huggingface-cli`, python-docx, python-pptx, openpyxl, pypdf, pdfplumber, pillow, pytesseract, pdf2image, python-magic, duckdb, polars, pandas, numpy, jupyter, yt-dlp, mcp, fastmcp, starlette, uvicorn, httpx). |
| **Node** | v25.9.0 pinned (NodeSource), **pnpm is the default package manager** (corepack-managed); npm and yarn also available. TypeScript, ts-language-server, tree-sitter-cli, Playwright CLI (browsers downloaded on demand with `playwright install`) |
| **AI agents** | Claude Code (`@anthropic-ai/claude-code`), Codex (`@openai/codex`), OpenCode (`opencode-ai`), Hermes (NousResearch), Happy (happy.engineering — `happy`), **rtk** (Rust Token Killer) — all preinstalled |
| **AI/ML runtime** | Hugging Face Hub client (`huggingface-cli`). CUDA Toolkit + cuDNN are NOT preinstalled (saved ~5 GB); torch / faster-whisper / whisper.cpp / Ollama removed (saved ~2.5 GB). Driver libs are injected at runtime by NVIDIA Container Toolkit when `--gpus all` is used. Install on demand inside the container — see GPU section below. |
| **DBs (servers)** | SQL Server 2025, PostgreSQL 18, DuckDB |
| **DB clients** | sqlcmd (mssql-tools18), psql 18, sqlite3 |
| **Search & nav** | ripgrep (`rg`), ast-grep (`sg`), tree-sitter, tree, fd, bat, fzf, zoxide, delta |
| **Git** | git, git-lfs, git-extras, GitHub CLI (`gh`), tig, lazygit, pre-commit, `repo` (Android multi-repo tool) |
| **Archive / sync** | zip, unzip, xz-utils, zstd, rsync |
| **Yarn** | `yarn` provided by **corepack** (already in the Node row above). The apt `yarnpkg` package is NOT installed — it would pull in Debian's nodejs + ~150 node-* packages that NodeSource Node 25 then removes. |
| **Build agents** | Azure DevOps agent v4.272.0 (`/opt/azp-agent`), GitHub Actions runner v2.334.0 (`/opt/gh-runner`) |
| **OCR / media** | tesseract, ffmpeg, poppler-utils |

All tools are on `PATH` — call them by short name.

## Build

**Prerequisites:** Docker Desktop (Windows / Mac) or Docker Engine 25+ with `buildx` (Linux). On Windows, Docker Desktop with WSL2 backend is recommended.

**bash / zsh / Linux:**

```bash
DOCKER_BUILDKIT=1 docker buildx build --tag aidev:latest --load .
```

**PowerShell (Windows):**

```powershell
$env:DOCKER_BUILDKIT=1
docker buildx build --tag aidev:latest --load .
```

Cold build: ~30–50 min depending on network. Incremental: ~2 min — BuildKit cache mounts keep the apt / npm / NuGet / uv caches warm across rebuilds.

**Follow the build log live (PowerShell):**

```powershell
docker buildx build --progress=plain --tag aidev:latest --load . 2>&1 | Tee-Object -FilePath aidev-build.log
```

**Build args** (all optional, override with `--build-arg`):

| Arg | Default | Purpose |
|---|---|---|
| `UBUNTU_TAG` | `26.04` | Ubuntu base tag |
| `NODE_MAJOR` | `25` | NodeSource major repo |
| `NODE_VERSION` | `25.9.0` | Pinned Node patch version |
| `GH_RUNNER_VERSION` | `2.334.0` | GitHub Actions runner version |
| `AZP_AGENT_VERSION` | `4.272.0` | Azure DevOps agent version |
| `RTK_VERSION` | *(empty → latest)* | Pin RTK release tag |

## Run via VS Code (recommended)

1. Install the **Dev Containers** extension.
2. Open this repo folder in VS Code.
3. **F1** → *Dev Containers: Reopen in Container*. VS Code uses `.devcontainer/devcontainer.json` and `.devcontainer/docker-compose.yml`.

The first reopen builds the image (or reuses `aidev:latest` if you already built it). Subsequent opens are instant — only the container starts.

## Run via Docker Compose

```bash
# Start (detached)
docker compose -f .devcontainer/docker-compose.yml up -d

# Exec a shell as the vscode user
docker compose -f .devcontainer/docker-compose.yml exec dev bash

# Stop and keep volumes (DB data preserved)
docker compose -f .devcontainer/docker-compose.yml down

# Stop AND wipe volumes (fresh DBs next time)
docker compose -f .devcontainer/docker-compose.yml down -v
```

## Run via plain `docker run` (no compose)

```bash
docker run -it --rm \
  -v "$(pwd)":/workspaces/aidevcontainer \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w /workspaces/aidevcontainer \
  aidev:latest bash
```

Add `--gpus all` for GPU passthrough (requires `nvidia-container-toolkit` on the host).

## Verify the build

After the container is up:

```bash
bash tests/smoke.sh                    # checks every CLI on PATH
AIDEV_SMOKE_FULL=1 bash tests/smoke.sh # also starts DBs + Azurite and connects
```

## On-demand services

Heavy services do not auto-start. Launch them when you need them:

| Command | Service | Default port(s) |
|---|---|---|
| `bash scripts/start-mssql.sh` | SQL Server 2025 | 1433 |
| `bash scripts/start-postgres.sh` | PostgreSQL 18 | 5432 |
| `bash scripts/start-azurite.sh` | Azurite (Blob/Queue/Table) | 10000 / 10001 / 10002 |
| `bash scripts/start-azp-agent.sh` | Azure DevOps build agent | — |
| `bash scripts/start-gh-runner.sh` | GitHub Actions runner | — |
| `bash scripts/gpu-check.sh` | Report GPU presence | — |
| `bash scripts/stop-all.sh` | Stop everything | — |

## Forwarded ports

`1433` (SQL), `5432` (PG), `10000-10002` (Azurite), `7071` (Azure Functions).

## SQL Server credentials

A random 24-char SA password is generated on first run of `start-mssql.sh` and written to `~/.mssql-password` (mode 600). The DB data itself persists on the `mssql-data` volume across container recreates. Retrieve the password and connect:

```bash
cat ~/.mssql-password
sqlcmd -S localhost,1433 -U sa -P "$(cat ~/.mssql-password)" -No -Q "SELECT @@VERSION"
```

> **Caveat:** `~/.mssql-password` itself is not on a named volume in the default compose, so it survives container *runs* but is regenerated on `down -v`. The actual DB password baked into SQL Server lives in `mssql-data`; if you lose `~/.mssql-password` after first-run init, run `down -v` to wipe both, or copy the file out before recreating the container.

## Azure DevOps build agent

Required env (do not commit):

```bash
export AZP_URL=https://dev.azure.com/<org>
export AZP_TOKEN=<PAT with "Agent Pools (read & manage)">
export AZP_POOL=Default                  # optional
export AZP_AGENT_NAME=aidev-$(hostname)  # optional
bash scripts/start-azp-agent.sh
```

## GitHub Actions self-hosted runner

Required env:

```bash
export GH_RUNNER_URL=https://github.com/<org>      # or .../<org>/<repo>
export GH_RUNNER_TOKEN=<registration token from repo/org Settings -> Actions -> Runners>
bash scripts/start-gh-runner.sh
```

## NVIDIA GPU support

The image does **not** include the CUDA Toolkit (saves ~5 GB). Driver libraries (`libcuda.so`, `libnvidia-ml.so`, etc.) are injected at runtime by the **NVIDIA Container Toolkit** when you start with `--gpus all` — so:
- **Ollama** uses GPU automatically (it `dlopen`s the injected `libcuda`).
- **PyTorch wheels** with bundled CUDA runtime work out of the box.
- **whisper.cpp** is not in the image — clone and build on demand: `git clone https://github.com/ggml-org/whisper.cpp && cd whisper.cpp && cmake -B build -DGGML_OPENBLAS=ON && cmake --build build`.

**Host requirements:**
- NVIDIA driver
- `nvidia-container-toolkit` configured for Docker

**Enabling GPU in the dev container:** uncomment the `deploy.resources.reservations.devices` block in `.devcontainer/docker-compose.yml` and restart the container.

**Verify:** `bash scripts/gpu-check.sh`

**Need Ollama / PyTorch / CUDA tools?** Install on demand inside the running container:

```bash
# Ollama
curl -fsSL https://ollama.com/install.sh | sh
# PyTorch
uv pip install torch --index-url https://download.pytorch.org/whl/cu130
```

**Need nvcc / cuDNN headers?** Install on demand inside the running container (the CUDA apt repo URL needs to be added separately; see NVIDIA's docs for `ubuntu2404`):

```bash
sudo apt-get update && sudo apt-get install -y cuda-toolkit-13-0 libcudnn9-cuda-13
```

## Real-Ladybug graph DB

Not preinstalled (the public PyPI `ladybug` is a different package). Add it per project from your private source.

## Office / PDF / screenshot extraction

Programmatic read/extract via `python-docx`, `python-pptx`, `openpyxl`, `pypdf`, `pdfplumber`, `pytesseract`, `pdf2image`. Document conversion (e.g., docx → pdf) is **not** included — install `libreoffice --headless` and `pandoc` if you need it (~1.5 GB).

## RTK (Rust Token Killer)

Pre-installed at `/usr/local/bin/rtk` from `github.com/rtk-ai/rtk`. Verify:

```bash
rtk --version
rtk gain          # token savings analytics
```

(Disambiguated from the unrelated `reachingforthejack/rtk` Rust Type Kit.)

## Performance notes

- **Tool caches** (`~/.cache/uv`, `~/.nuget`, `~/.npm`, `~/.cache/pnpm`, `~/.cache/huggingface`, `~/.azure`, `~/.claude`) live on **named Docker volumes** (ext4 inside the WSL2 VM on Windows) — much faster than NTFS bind mounts for many small files.
- **DB data** persists on named volumes (`mssql-data` → `/var/opt/mssql`, `pg-data` → `/var/lib/postgresql/18/main`).
- **`/tmp`** is a 4 GB tmpfs.
- **`nofile` ulimit** raised to 1,048,576.
- **Telemetry** disabled across .NET, Azure CLI, PowerShell, npm, Next.js, etc.
- **Pre-warmed** Roslyn, NuGet, pyright, tsserver, gopls, rust-analyzer caches under `/home/vscode/.nuget` and `/home/vscode/.dotnet` — Docker named-volume bootstrap copies these into the persistent volumes on first creation.
- **Single-stage Dockerfile** with **2 apt installs total** (bootstrap for repo keys + one big consolidated install for everything else).

## Troubleshooting

- **Build fails at the `apt install` step on a slow link.** `fetch-timeout` is already raised; if you still see ECONNRESET, retry the build — BuildKit cache resumes from the last successful layer.
- **`docker run` from inside the container fails (permission denied on /var/run/docker.sock).** The `fix-docker-perms` entrypoint aligns the docker group GID; if it didn't run, `sudo /usr/local/bin/fix-docker-perms` re-runs it.
- **Slow file ops on Windows.** Workspace is bind-mounted from NTFS — that's the bottleneck for many small files. Move tool caches to named volumes (already configured) and prefer running build commands inside the container shell, not from Windows.
- **`mssql-conf` complains on first run.** Delete `~/.mssql-password` and let `start-mssql.sh` regenerate it (only safe on a fresh `mssql-data` volume).
- **No GPU detected.** Run `bash scripts/gpu-check.sh`. Confirm `nvidia-container-toolkit` is installed on the host and the compose GPU block is uncommented.
- **Hermes Playwright browser install hangs / fails.** The build spoofs `/etc/os-release` as Ubuntu 24.04 during Hermes install so Playwright accepts the host. After install, the file is restored.
- **Git SSH clones don't work inside the container.** The image rewrites `git@github.com:` → `https://github.com/` system-wide for build determinism. To use SSH at runtime, override per-user: `git config --global --unset-all url."https://github.com/".insteadOf` and mount your `~/.ssh` from the host.

## Image size

~10–13 GB after pre-warm. Major contributors: SQL Server 2025 (~1.7 GB), .NET 10 + 11 SDKs (~1.4 GB), `/opt/venv` Python stack (~1.5 GB), npm globals (~600 MB), Go + Rust (~1.1 GB), Azure CLI + extensions (~600 MB), Playwright browser deps (~150 MB libs only — browsers downloaded on first `playwright install`).

