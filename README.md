# ai-dev — high-performance dev container for AI software development

Single-image Ubuntu 26.10 (stonking) dev container that bundles the full AI / .NET / Python / Node stack used for agentic software development. Built against Ubuntu's **amd64v3** (x86-64-v3) optimized package set by default. Tuned for agent harnesses (Claude Code, Codex, Copilot CLI, OpenCode) working on **.NET / Aspire / Angular / Playwright** code: MCP servers (fff, CodeGraph, Playwright, Microsoft Learn) and container-specific guidance are registered for every agent at container create, agent logins persist on volumes, and the .NET debugging/diagnostics, docs and analysis toolchain is preinstalled.

> **Heads up:** 26.10 is a non-LTS interim release (GA 2026-10-15). Most third-party apt repos have no `stonking` suite (Azure CLI uses the 26.04 `resolute` suite, NodeSource uses `nodistro`, only the Docker repo probes for a matching suite).
>
> `--build-arg UBUNTU_TAG=26.04` will **not** work as a quick way back to the LTS: the package list is 26.10-specific (`libmagic1t64`, no `repo` package, `dotnet-sdk-11.0` from the Ubuntu archive). Going back to 26.04 means reverting those too — see git history.

## What's inside

| Category | Tools |
|---|---|
| **OS** | Ubuntu 26.10 (amd64v3 package variant), `en_US.UTF-8`, `vscode` user (UID 1000, passwordless sudo) |
| **.NET** | SDK 10 + SDK 11 (both GA, both from the Ubuntu archive, side-by-side in `/usr/lib/dotnet`), ASP.NET Core 10 + 11 runtimes, Aspire CLI, Roslynator, CSharpier, dotnet-ef, dotnet-script, csharp-ls, dotnet-outdated, sqlpackage, docfx, PowerShell (`pwsh`, for `playwright.ps1`). `dotnet format` is built into the SDK. |
| **.NET debugging & diagnostics** | `netcoredbg` (open-source debugger, CLI/MI/DAP — drivable by agents), `lldb` with SOS preloaded (`~/.lldbinit`), dotnet-dump, dotnet-trace, dotnet-counters, dotnet-gcdump, dotnet-stack, `ilspycmd` (decompiler), dotnet-coverage + ReportGenerator, strace, lsof. `SYS_PTRACE` is granted, so attaching works. Workloads pre-updated; HTTPS dev cert trusted for the `vscode` user via prewarm. Telemetry disabled (`DOTNET_CLI_TELEMETRY_OPTOUT=1`). |
| **Azure** | Azure CLI (apt) + extensions (azure-devops, serviceconnector-passwordless, containerapp [preview], application-insights [preview], aks-preview), `az bicep` built-in, Azure Functions Core Tools v4, Azurite |
| **Python** | **One** Python: Ubuntu's apt `python3` (3.14 on 26.10, amd64v3 build), `python-is-python3`. uv never downloads another CPython (`UV_PYTHON_DOWNLOADS=never`, `UV_PYTHON_PREFERENCE=only-system`). `uv` + `uvx`. uv tools: ruff, pyright, basedpyright, mypy, pytest, ipython, python-lsp-server, pre-commit, **yt-dlp** (`yt-dlp[default]`, uses Node as its JS runtime via `/etc/yt-dlp.conf`). Prebuilt venv at `/opt/venv` (huggingface_hub + `huggingface-cli`, python-docx, python-pptx, openpyxl, pypdf, pdfplumber, pillow, pytesseract, pdf2image, python-magic, duckdb, polars, pandas, numpy, jupyter, mcp, fastmcp, starlette, uvicorn, httpx). |
| **Node / Angular** | v26.13.1 LTS pinned (NodeSource), **pnpm is the default package manager** (corepack-managed); npm and yarn also available. Angular CLI (`ng`) + Angular language server (`ngserver`), TypeScript, ts-language-server, markdownlint-cli2, tree-sitter-cli |
| **Playwright** | **Playwright MCP only** (`playwright-mcp`) — no global `playwright`/`playwright-cli`; projects bring their own `@playwright/test` / Microsoft.Playwright. Chromium + headless shell for the MCP's own Playwright revision preinstalled in `/opt/ms-playwright`, launch-tested at build time, and pinned via `--executable-path /usr/local/bin/chromium`, so the MCP never downloads a browser. | `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64` lets older Playwright versions (incl. Microsoft.Playwright for .NET) download on 26.10. |
| **AI agents** | Claude Code, Codex, GitHub Copilot CLI (`copilot`), OpenCode, Hermes (NousResearch), Happy, **rtk** (Rust Token Killer) — latest release on every build; auto-updaters off (rebuild to upgrade) |
| **Agent MCP servers** | **fff-mcp** (default file search & index), **CodeGraph** (`codegraph`, symbol/call graph), **Playwright MCP**, **Microsoft Learn** (remote docs), **aismartbuddy** (thinking graph, SQL/graph analysis, web crawl — via `uvx`, pre-cached) — registered for every agent, see *Agent setup* below |
| **Docs & analysis** | `markitdown` (docx/pptx/xlsx/pdf → Markdown), pandoc, graphviz (`dot`), semgrep, gitleaks, shellcheck, hadolint, yq, hyperfine |
| **AI/ML runtime** | Hugging Face Hub client (`huggingface-cli`). CUDA Toolkit + cuDNN are NOT preinstalled (saved ~5 GB); torch / faster-whisper / whisper.cpp / Ollama removed (saved ~2.5 GB). Driver libs are injected at runtime by NVIDIA Container Toolkit when `--gpus all` is used. Install on demand inside the container — see GPU section below. |
| **DB clients** | `sqlcmd` (go-sqlcmd, GitHub release, sha256-verified), `psql` (`postgresql-client`, 18), `mysql` (`mysql-client`, 9.x), DuckDB, sqlite3. No database servers — run SQL Server / PostgreSQL / MySQL as separate containers and connect with these clients. |
| **Search & nav** | ripgrep (`rg`), ast-grep (`sg`), tree-sitter, tree, fd, bat, fzf, zoxide, delta |
| **Git** | git, git-lfs, git-extras, GitHub CLI (`gh`), tig, lazygit, pre-commit, `repo` (Android multi-repo tool — 26.10 dropped the apt package, so it comes from Google's official launcher script) |
| **Archive / sync** | zip, unzip, xz-utils, zstd, rsync |
| **Yarn** | `yarn` provided by **corepack** (already in the Node row above). The apt `yarnpkg` package is NOT installed — it would pull in Debian's nodejs + ~150 node-* packages that NodeSource Node 26 then removes. |
| **Build agents** | Azure DevOps agent v5.282.0 (`/opt/azp-agent`), GitHub Actions runner v2.338.2 (`/opt/gh-runner`) |
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
| `UBUNTU_TAG` | `26.10` | Ubuntu base tag |
| `ENABLE_AMD64V3` | `1` | Use Ubuntu's x86-64-v3 optimized packages. Set `0` for a pre-2013 CPU. |
| `NODE_MAJOR` | `26` | NodeSource major repo |
| `NODE_VERSION` | `26.13.1` | Pinned Node patch version |
| `GH_RUNNER_VERSION` | `2.338.2` | GitHub Actions runner version |
| `AZP_AGENT_VERSION` | `5.282.0` | Azure DevOps agent version |
| `RTK_VERSION` | *(empty → latest)* | Pin RTK release tag |
| `FFF_VERSION` | *(empty → latest)* | Pin fff-mcp release tag (e.g. `v0.11.0`) |
| `SQLCMD_VERSION` | *(empty → latest)* | Pin go-sqlcmd release tag (e.g. `v1.11.0`) |

## Run via VS Code (recommended)

1. Install the **Dev Containers** extension.
2. Open this repo folder in VS Code.
3. **F1** → *Dev Containers: Reopen in Container* and pick a variant:
   - **ai-dev (docker)** — `.devcontainer/devcontainer.json` (Docker Desktop / Docker Engine)
   - **ai-dev (podman)** — `.devcontainer/podman/devcontainer.json` (rootless podman, see below)

The first reopen builds the image (or reuses `aidev:latest` if you already built it). Subsequent opens are instant — only the container starts.

Extensions, forwarded ports, `remoteUser` and the post-create hook live in the image's `devcontainer.metadata` label (Dockerfile), so both variants stay identical; the `devcontainer.json` files only pick the compose files.

### Rootless podman

One-time host setup:

```bash
systemctl --user enable --now podman.socket
```

VS Code user settings: `"dev.containers.dockerPath": "podman"`, `"dev.containers.dockerComposePath": "podman-compose"`.

`.devcontainer/docker-compose.podman.yml` layers on top of the base compose file and:

- mounts `$XDG_RUNTIME_DIR/podman/podman.sock` at `/var/run/docker.sock` (docker CLI, Aspire and Testcontainers use it unchanged);
- sets `userns_mode: keep-id`, so `vscode` (UID 1000) is your host user — the workspace and socket are writable;
- uses **host networking**, so containers that Aspire or Testcontainers start (siblings on the host) are reachable on `localhost`; Ryuk is disabled and `TESTCONTAINERS_HOST_OVERRIDE=localhost`.

Without compose: `podman compose -f .devcontainer/docker-compose.yml -f .devcontainer/docker-compose.podman.yml up -d`.

## Run via Docker Compose

```bash
# Start (detached)
docker compose -f .devcontainer/docker-compose.yml up -d

# Exec a shell as the vscode user
docker compose -f .devcontainer/docker-compose.yml exec dev bash

# Stop and keep volumes (caches + agent config preserved)
docker compose -f .devcontainer/docker-compose.yml down

# Stop AND wipe volumes (cold caches, agent config gone)
docker compose -f .devcontainer/docker-compose.yml down -v
```

## Run via plain `docker run` (no compose)

```bash
docker run -it --rm \
  -v "$(dirname "$(pwd)")":/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w /data/"$(basename "$(pwd)")" \
  aidev:latest bash
```

Add `--gpus all` for GPU passthrough (requires `nvidia-container-toolkit` on the host).

## Verify the build

After the container is up:

```bash
bash /opt/aidev/tests/smoke.sh                    # every CLI, MCP registration, Chromium launch
AIDEV_SMOKE_FULL=1 bash /opt/aidev/tests/smoke.sh # also starts Azurite and connects
```

## On-demand services

Heavy services do not auto-start. Launch them when you need them:

| Command | Service | Default port(s) |
|---|---|---|
| `bash /opt/aidev/scripts/start-azurite.sh` | Azurite (Blob/Queue/Table) | 10000 / 10001 / 10002 |
| `bash /opt/aidev/scripts/start-azp-agent.sh` | Azure DevOps build agent | — |
| `bash /opt/aidev/scripts/start-gh-runner.sh` | GitHub Actions runner | — |
| `bash /opt/aidev/scripts/gpu-check.sh` | Report GPU presence | — |
| `bash /opt/aidev/scripts/stop-all.sh` | Stop everything | — |

## Forwarded ports

`10000-10002` (Azurite), `7071` (Azure Functions).

## Data folder (`/data`)

All source code and the working environment are mounted at **`/data`**. By default that is the folder that *contains* this repo (`AIDEV_DATA_DIR`, default `../..` relative to `.devcontainer/` — e.g. `~/Projects` or `C:\Users\<you>\source\repos`), so every sibling repo is available in the container and the dev container opens `/data/<this repo>`. fff-mcp indexes all of `/data`.

Point it elsewhere by setting `AIDEV_DATA_DIR` on the host before starting the container (it must contain this repo):

```bash
export AIDEV_DATA_DIR="$HOME/src"
```

Git trusts every repo under it (`safe.directory '*'`), since the host user owns the bind mount.

## Agent setup

`scripts/post-create.sh` runs `scripts/setup-agents.sh` (also on PATH as `setup-agents`) at container create. It registers these MCP servers for **Claude Code, Codex, Copilot CLI and OpenCode**:

| Server | What | Command |
|---|---|---|
| `fff` | Default file finder + content index of the **data folder** `/data` ([fff](https://github.com/dmtrKovalenko/fff)) | `fff-mcp --no-update-check /data` |
| `codegraph` | Symbol / call-graph queries in repos with a `.codegraph/` index | `codegraph serve --mcp` |
| `playwright` | The container's headless Chromium, every capability on (vision, pdf, devtools), dev-cert HTTPS accepted | `playwright-mcp --headless --isolated --no-sandbox --ignore-https-errors --caps vision,pdf,devtools --browser chromium --executable-path /usr/local/bin/chromium` |
| `microsoft-learn` | Official .NET / ASP.NET Core / Aspire / Azure docs | `https://learn.microsoft.com/api/mcp` (HTTP) |
| `aismartbuddy` | Thinking graph, SQL/graph analysis sessions, web crawl, YouTube ([meghuizen/aismartbuddy](https://github.com/meghuizen/aismartbuddy)) | `uvx --from git+https://github.com/meghuizen/aismartbuddy aismartbuddy` — pre-resolved into the uv cache at build time; uvx tracks `main` |

…and writes a managed guidance block (source: `config/agent-instructions.md`) telling the agents which tools exist and when to use them:

| Agent | MCP config | Guidance |
|---|---|---|
| Claude Code | `~/.claude/.claude.json` (via `CLAUDE_CONFIG_DIR`) | `~/.claude/CLAUDE.md` |
| Codex | `~/.codex/config.toml` | `~/.codex/AGENTS.md` |
| Copilot CLI | `~/.copilot/mcp-config.json` | `~/.copilot/copilot-instructions.md` |
| OpenCode | `~/.config/opencode/opencode.json` | `~/.config/opencode/AGENTS.md` |

**Claude Code extras** (mirroring the tuned host setup): `config/claude-settings.json` is merged into `~/.claude/settings.json` — a permission allow-list for routine read/build/test commands (`dotnet build/test/format`, `pnpm`, `ng`, `git status/diff/log`, `rg`, …, plus the fff/codegraph/microsoft-learn MCP tools) and the `codegraph prompt-hook` on `UserPromptSubmit`. The **csharp-lsp**, **typescript-lsp** and **pyright-lsp** plugins (official marketplace) are installed, so Claude Code gets go-to-definition / find-references / diagnostics through `csharp-ls`, `typescript-language-server` and `pyright`.

Idempotent: servers the user already has under the same name are left alone, other config is merged into, and the guidance block (between `<!-- aidev:begin` / `<!-- aidev:end -->`) is refreshed in place. Hermes is not wired up automatically.

**Logins persist.** Each agent's home (`~/.claude`, `~/.codex`, `~/.copilot`, `~/.config/opencode`, `~/.local/share/opencode`) plus `~/.config/gh` and `~/.azure` are named volumes. `CLAUDE_CONFIG_DIR=/home/vscode/.claude` moves `.claude.json` (auth, onboarding, MCP servers) onto that volume too.

**Aspire.** `aspire run` starts resources through the mounted container-engine socket. With Docker Desktop the resource ports are on the host's network; with the podman variant (host networking) they are on `localhost` inside the container as well.

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

- **Tool caches** (`~/.cache/uv`, `~/.nuget`, `~/.npm`, `~/.cache/pnpm`, `~/.cache/huggingface`) and **agent config** (`~/.claude`, `~/.codex`, `~/.copilot`, OpenCode, `~/.config/gh`, `~/.azure`) live on **named Docker volumes** (ext4 inside the WSL2 VM on Windows) — much faster than NTFS bind mounts for many small files.
- **`/tmp`** is a 4 GB tmpfs. **`/dev/shm`** is 2 GB (the 64 MB default crashes Chromium).
- **amd64v3 packages.** Ubuntu 26.10 publishes a second binary set built for x86-64-v3 (AVX2, FMA, BMI1/BMI2, MOVBE). The image enables it with `APT::Architecture-Variants "amd64v3"`, which covers nearly all of `main` and `universe`; apt falls back to plain amd64 for anything without a v3 build. Requires Intel Haswell / AMD Excavator or newer. Check your CPU with `ld.so --help | grep x86-64-v`.
- **Runtime env tuning.** `DOTNET_EnableWriteXorExecute=0` (faster .NET startup), `DOTNET_TieredPGO=1`, `DOTNET_CLI_USE_MSBUILD_SERVER=1` (warm MSBuild workers), `MALLOC_ARENA_MAX=8` (was 2 — less allocator contention), `NODE_OPTIONS=--max-old-space-size=8192`, `UV_THREADPOOL_SIZE=16`, `UV_COMPILE_BYTECODE=1` (pre-compiled `.pyc` on install).
- **Build-time tuning.** dpkg `force-unsafe-io` (no fsync per unpacked file — safe for a throwaway build FS), `Acquire::Languages "none"` (skips translation indexes), apt retries.
- **Telemetry** disabled across .NET, Azure CLI, PowerShell, npm, Next.js, etc.
- **Pre-warmed** Roslyn, NuGet, pyright, tsserver, gopls, rust-analyzer caches under `/home/vscode/.nuget` and `/home/vscode/.dotnet` — Docker named-volume bootstrap copies these into the persistent volumes on first creation.
- **Single-stage Dockerfile** with **2 apt installs total** (bootstrap for repo keys + one big consolidated install for everything else).

### Resource limits (ulimits)

Set in three places, because they do different jobs. All three carry the same numbers on purpose — the container ceiling always wins, so a bigger number lower down would only be a lie:

| Where | What it does |
|---|---|
| `.devcontainer/docker-compose.yml` → `ulimits:` | The **hard ceiling** the container is created with. Nothing inside the image can raise it. `nofile` 1,048,576 · `nproc` 262,144 · `memlock` unlimited · `stack` soft 8 MB / hard 64 MB · `core` 0 |
| `/etc/security/limits.d/90-aidev.conf` (in image) | Applied by `pam_limits` for login-style sessions (`su`, `sudo -u <user>`, ssh). |
| `/etc/profile.d/10-aidev-limits.sh` (in image) | Raises each interactive shell's **soft** limit up to its hard limit. `docker exec` bypasses PAM, so without this a shell keeps the default soft `nofile`. |

`core 0` stops multi-GB core dumps from .NET or Chromium filling the container's writable layer. `memlock` unlimited is needed for io_uring. `stack` deliberately keeps its **soft** limit at the glibc default of 8 MB — glibc uses the soft `RLIMIT_STACK` as the default pthread stack size, so raising it would make every thread reserve 64 MB of address space; only the hard ceiling is raised, so `ulimit -s` can be bumped for a process that genuinely needs it.

Kernel tunables split by whether they can be namespaced:

- **Namespaced** (`net.core.somaxconn`, `net.ipv4.ip_local_port_range`) — set for real by compose `sysctls:`, and nowhere else.
- **Not namespaced** (`fs.inotify.*`, `fs.file-max`, `vm.max_map_count`, `vm.swappiness`) — listed in `/etc/sysctl.d/90-aidev.conf`, which is **inert in an unprivileged container** (no `systemd-sysctl` here). They apply only on a privileged run, or if you set them on the host. On Docker Desktop/WSL2 that means the WSL2 VM, not Windows.

## Troubleshooting

- **Build fails at the `apt install` step on a slow link.** `fetch-timeout` is already raised; if you still see ECONNRESET, retry the build — BuildKit cache resumes from the last successful layer.
- **`docker run` from inside the container fails (permission denied on /var/run/docker.sock).** The `fix-docker-perms` entrypoint aligns the docker group GID; if it didn't run, `sudo /usr/local/bin/fix-docker-perms` re-runs it.
- **Slow file ops on Windows.** Workspace is bind-mounted from NTFS — that's the bottleneck for many small files. Move tool caches to named volumes (already configured) and prefer running build commands inside the container shell, not from Windows.
- **No GPU detected.** Run `bash scripts/gpu-check.sh`. Confirm `nvidia-container-toolkit` is installed on the host and the compose GPU block is uncommented.
- **Playwright says it does not support `ubuntu26.10-x64`.** `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE` is set image-wide; if a tool clears the environment (e.g. `sudo`), pass it through: `sudo env PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64 …`.
- **An agent lost its MCP servers or guidance** (e.g. after wiping a volume). Run `setup-agents`.
- **A program dies with "Illegal instruction" / SIGILL.** You are running the amd64v3 image on a CPU older than Intel Haswell / AMD Excavator. Rebuild with `--build-arg ENABLE_AMD64V3=0`.
- **A package disappeared or was renamed.** 26.10 is still in development, and the 64-bit `time_t` transition renamed several libraries (e.g. `libmagic1` → `libmagic1t64`). If the big apt install fails on a package name, check `https://packages.ubuntu.com/stonking/<name>` for the current one.
- **Git SSH clones don't work inside the container.** The image rewrites `git@github.com:` → `https://github.com/` system-wide for build determinism. To use SSH at runtime, override per-user: `git config --global --unset-all url."https://github.com/".insteadOf` and mount your `~/.ssh` from the host.

## Image size

~9–12 GB after pre-warm (SQL Server, PostgreSQL and the extra uv Pythons are gone; Chromium, the .NET diagnostics/debug stack, PowerShell, semgrep and pandoc were added). Major contributors: .NET 10 + 11 SDKs (~1.4 GB), `/opt/venv` Python stack (~1.5 GB), npm globals (~600 MB), Go + Rust (~1.1 GB), Azure CLI + extensions (~600 MB), Playwright browser deps (~150 MB libs only — browsers downloaded on first `playwright install`).

