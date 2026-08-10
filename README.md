# ai-dev — high-performance dev container for AI software development

Single-image Ubuntu 26.10 (stonking) dev container that bundles the full AI / .NET / Python / Node stack used for agentic software development. Built against Ubuntu's **amd64v3** (x86-64-v3) optimized package set by default.

> **Heads up:** 26.10 is a non-LTS interim release and, until October 2026, still in development — `ubuntu:26.10` is a moving snapshot and most third-party apt repos have no `stonking` suite yet (Microsoft is pinned to `noble`, NodeSource uses `nodistro`, only the Docker repo probes for a matching suite).
>
> `--build-arg UBUNTU_TAG=26.04` will **not** work as a quick way back to the LTS: the package list is 26.10-specific (`libmagic1t64`, no `repo` package, `postgresql-18` from the Ubuntu archive rather than PGDG). Going back to 26.04 means reverting those too — see git history.

## What's inside

| Category | Tools |
|---|---|
| **OS** | Ubuntu 26.10 (amd64v3 package variant), `en_US.UTF-8`, `vscode` user (UID 1000, passwordless sudo) |
| **.NET** | SDK 10 (apt) + SDK 11 preview (via dotnet-install.sh, side-by-side), ASP.NET Core 10 + 11 runtimes, Aspire CLI, Roslynator, dotnet-ef, dotnet-format, dotnet-script, csharp-ls, dotnet-outdated. Workloads pre-updated; HTTPS dev cert trusted for the `vscode` user via prewarm. Telemetry disabled (`DOTNET_CLI_TELEMETRY_OPTOUT=1`). |
| **Azure** | Azure CLI (apt) + extensions (azure-devops, serviceconnector-passwordless, containerapp [preview], application-insights [preview], aks-preview), `az bicep` built-in, Azure Functions Core Tools v4, Azurite |
| **Python** | Ubuntu's apt `python3` (whatever 26.10 ships), `python-is-python3`, plus uv-managed **Python 3.11** and **3.14** on PATH as `python3.11` / `python3.14`. `uv` + `uvx`. uv-managed dev tools: ruff, pyright, basedpyright, mypy, pytest, ipython, python-lsp-server, pre-commit. Prebuilt venv at `/opt/venv` (huggingface_hub + `huggingface-cli`, python-docx, python-pptx, openpyxl, pypdf, pdfplumber, pillow, pytesseract, pdf2image, python-magic, duckdb, polars, pandas, numpy, jupyter, yt-dlp, mcp, fastmcp, starlette, uvicorn, httpx). |
| **Node** | v26.6.0 pinned (NodeSource), **pnpm is the default package manager** (corepack-managed); npm and yarn also available. TypeScript, ts-language-server, tree-sitter-cli, Playwright CLI (browsers downloaded on demand with `playwright install`) |
| **AI agents** | Claude Code (`@anthropic-ai/claude-code`), Codex (`@openai/codex`), OpenCode (`opencode-ai`), Hermes (NousResearch), Happy (happy.engineering — `happy`), **rtk** (Rust Token Killer) — all preinstalled |
| **AI/ML runtime** | Hugging Face Hub client (`huggingface-cli`). CUDA Toolkit + cuDNN are NOT preinstalled (saved ~5 GB); torch / faster-whisper / whisper.cpp / Ollama removed (saved ~2.5 GB). Driver libs are injected at runtime by NVIDIA Container Toolkit when `--gpus all` is used. Install on demand inside the container — see GPU section below. |
| **DBs (servers)** | PostgreSQL 18 (Ubuntu archive — single origin, no PGDG), DuckDB. **SQL Server 2025 runs as a separate `mssql` container**, not in this image — see below |
| **DB clients** | sqlcmd + bcp (mssql-tools18), ODBC Driver 18 (msodbcsql18 + unixodbc), psql 18, sqlite3 |
| **Search & nav** | ripgrep (`rg`), ast-grep (`sg`), tree-sitter, tree, fd, bat, fzf, zoxide, delta |
| **Git** | git, git-lfs, git-extras, GitHub CLI (`gh`), tig, lazygit, pre-commit, `repo` (Android multi-repo tool — 26.10 dropped the apt package, so it comes from Google's official launcher script) |
| **Archive / sync** | zip, unzip, xz-utils, zstd, rsync |
| **Yarn** | `yarn` provided by **corepack** (already in the Node row above). The apt `yarnpkg` package is NOT installed — it would pull in Debian's nodejs + ~150 node-* packages that NodeSource Node 26 then removes. |
| **Build agents** | Azure DevOps agent v5.277.0 (`/opt/azp-agent`), GitHub Actions runner v2.336.0 (`/opt/gh-runner`) |
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
| `NODE_VERSION` | `26.6.0` | Pinned Node patch version |
| `GH_RUNNER_VERSION` | `2.336.0` | GitHub Actions runner version |
| `AZP_AGENT_VERSION` | `5.277.0` | Azure DevOps agent version |
| `RTK_VERSION` | *(empty → latest)* | Pin RTK release tag |
| `TREE_SITTER_GRAMMARS` | `c-sharp python typescript javascript bash sql` | Grammar sources to clone. Add any of `rust go yaml html css`, or set to `""` for none |

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
| `bash scripts/start-mssql.sh` | SQL Server 2025 (separate container) | 1433 |
| `bash scripts/start-postgres.sh` | PostgreSQL 18 | 5432 |
| `bash scripts/start-azurite.sh` | Azurite (Blob/Queue/Table) | 10000 / 10001 / 10002 |
| `bash scripts/start-azp-agent.sh` | Azure DevOps build agent | — |
| `bash scripts/start-gh-runner.sh` | GitHub Actions runner | — |
| `bash scripts/gpu-check.sh` | Report GPU presence | — |
| `bash scripts/stop-all.sh` | Stop everything | — |

**SQL Server runs in its own container.** The 1.45 GB engine is not baked into the dev image. `.devcontainer/docker-compose.yml` declares an `mssql` service using `mcr.microsoft.com/mssql/server:2025-latest`, behind the compose profile `mssql` so it does **not** start with the dev container (the engine wants ~2 GB of RAM).

`bash scripts/start-mssql.sh` works exactly as before — it generates the SA password at `~/.mssql-password` on first run, brings the service up, and waits until the engine answers. It drives compose through the mounted Docker socket, so it works from inside the dev container or from the host. From the host directly:

```bash
docker compose -f .devcontainer/docker-compose.yml --profile mssql up -d mssql
```

**Connect to host `mssql`, not `localhost`** — the engine is a different container on the compose network:

```bash
sqlcmd -S mssql,1433 -U sa -P "$(cat ~/.mssql-password)" -No
```

Port 1433 is still published to the host, so host-side tools (SSMS, Azure Data Studio) reach it at `localhost,1433` as before. Set `MSSQL_HOST` to override the hostname the scripts use.

> **Never run a bare `docker compose up` from inside the dev container.** Compose resolves the dev service's relative bind mount (`../:/workspaces/aidevcontainer`) against the compose file's directory — an in-container path — and would hand that to the host daemon, producing a dev container with an empty workspace. Always name the service (`up -d mssql`), which is what `start-mssql.sh` and `stop-all.sh` do, or run compose from the host.

The old `config/mssql.conf` is gone; the equivalent settings are `MSSQL_*` environment variables on the service (`MSSQL_MEMORY_LIMIT_MB`, `MSSQL_TCP_PORT`, `MSSQL_LCID`, `MSSQL_PID`). One setting did not survive the move: `customerfeedback = false`. The official container image has no documented environment variable for it, so telemetry is at the image's default.

The SA password comes from `MSSQL_SA_PASSWORD` in the environment (the script exports it from `~/.mssql-password`) and is baked into the container at creation. Changing it later means `docker compose -f .devcontainer/docker-compose.yml rm -f mssql` and starting again — the `mssql-data` volume survives that, so your databases do too. Starting the service by hand without that variable set makes the SQL Server image refuse to start; check `docker compose logs mssql`.

**Existing data carries over.** The volume is still `aidev_mssql-data`, the same name the in-image server used, so databases created before this change are picked up by the new container with no migration.

**Postgres cluster creation.** The image sets `create_main_cluster = false` in `/etc/postgresql-common/createcluster.conf`, so `postgresql-18`'s postinst does **not** create a cluster during the build. `start-postgres.sh` runs `initdb` itself on first start and installs `config/postgresql.conf` + `config/pg_hba.conf` into the data dir, which is what it starts postgres with (`-c config_file=$PG_DATA/postgresql.conf`). Without this, the auto-created cluster would leave a populated data dir, the script would skip its init branch, the repo's configs would never be installed, and postgres would fail on a missing `config_file`.

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
- **`/tmp`** is a 4 GB tmpfs. **`/dev/shm`** is 2 GB (the 64 MB default crashes Chromium and upsets SQL Server).
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
| `/etc/security/limits.d/90-aidev.conf` (in image) | Applied by `pam_limits` for login-style sessions — this is what the DB servers get when started via `sudo -u postgres` / `sudo -u mssql`. |
| `/etc/profile.d/10-aidev-limits.sh` (in image) | Raises each interactive shell's **soft** limit up to its hard limit. `docker exec` bypasses PAM, so without this a shell keeps the default soft `nofile`. |

`core 0` stops multi-GB core dumps from .NET or Chromium filling the container's writable layer. `memlock` unlimited is needed for SQL Server locked pages and io_uring. `stack` deliberately keeps its **soft** limit at the glibc default of 8 MB — glibc uses the soft `RLIMIT_STACK` as the default pthread stack size, so raising it would make every thread reserve 64 MB of address space; only the hard ceiling is raised, so `ulimit -s` can be bumped for a process that genuinely needs it.

Kernel tunables split by whether they can be namespaced:

- **Namespaced** (`net.core.somaxconn`, `net.ipv4.ip_local_port_range`) — set for real by compose `sysctls:`, and nowhere else.
- **Not namespaced** (`fs.inotify.*`, `fs.file-max`, `vm.max_map_count`, `vm.swappiness`) — listed in `/etc/sysctl.d/90-aidev.conf`, which is **inert in an unprivileged container** (no `systemd-sysctl` here). They apply only on a privileged run, or if you set them on the host. On Docker Desktop/WSL2 that means the WSL2 VM, not Windows.

## Troubleshooting

- **Build fails at the `apt install` step on a slow link.** `fetch-timeout` is already raised; if you still see ECONNRESET, retry the build — BuildKit cache resumes from the last successful layer.
- **`docker run` from inside the container fails (permission denied on /var/run/docker.sock).** The `fix-docker-perms` entrypoint aligns the docker group GID; if it didn't run, `sudo /usr/local/bin/fix-docker-perms` re-runs it.
- **Slow file ops on Windows.** Workspace is bind-mounted from NTFS — that's the bottleneck for many small files. Move tool caches to named volumes (already configured) and prefer running build commands inside the container shell, not from Windows.
- **`sqlcmd` can't reach the server / "Login failed for user 'sa'".** Two usual causes. First, connect to `mssql,1433`, not `localhost,1433` — the engine is a separate container. Second, `~/.mssql-password` must match the password baked into the running container; if you regenerated the file, run `docker compose -f .devcontainer/docker-compose.yml rm -f mssql` and `start-mssql.sh` again (your data volume survives).
- **`start-mssql.sh` says it cannot reach the Docker daemon.** It drives compose over the mounted socket, so `/var/run/docker.sock` has to be mounted and the `vscode` user has to be in the `docker` group — run `sudo /usr/local/bin/fix-docker-perms` if the entrypoint didn't.
- **Microsoft's apt repo is pinned to `noble` (24.04), not 26.04.** Deliberate, and it is the only option: the `ubuntu/26.04/prod` feed (suite `resolute`) exists but contains 218 packages of moby/Kubernetes/Defender/sysinternals tooling — no `mssql-tools18`, no `msodbcsql18`, no `powershell`, no .NET. The `noble` debs install cleanly on 26.10 because their dependencies (`libc6`, `libstdc++6`, `libkrb5-3`, `openssl`, `unixodbc`, `odbcinst`) all exist there. Verify before "upgrading" it: `curl -s https://packages.microsoft.com/ubuntu/26.04/prod/dists/resolute/main/binary-amd64/Packages | grep '^Package:' | sort -u`.
- **No GPU detected.** Run `bash scripts/gpu-check.sh`. Confirm `nvidia-container-toolkit` is installed on the host and the compose GPU block is uncommented.
- **Hermes Playwright browser install hangs / fails.** The build spoofs `/etc/os-release` as Ubuntu 24.04 during Hermes install so Playwright accepts the host (its binary-host map has no `ubuntu26.10-x64` entry). After install, the file is restored.
- **A program dies with "Illegal instruction" / SIGILL.** You are running the amd64v3 image on a CPU older than Intel Haswell / AMD Excavator. Rebuild with `--build-arg ENABLE_AMD64V3=0`.
- **A package disappeared or was renamed.** 26.10 is still in development, and the 64-bit `time_t` transition renamed several libraries (e.g. `libmagic1` → `libmagic1t64`). If the big apt install fails on a package name, check `https://packages.ubuntu.com/stonking/<name>` for the current one.
- **Git SSH clones don't work inside the container.** The image rewrites `git@github.com:` → `https://github.com/` system-wide for build determinism. To use SSH at runtime, override per-user: `git config --global --unset-all url."https://github.com/".insteadOf` and mount your `~/.ssh` from the host.

## Image size

**Roughly 9 GB**, down from ~11 GB before the cuts described below. The apt half is measured exactly; the rest is estimated. Nothing here has been confirmed against a built image yet — run `docker image ls aidev:latest` and the audit commands at the end of this section to replace these numbers with real ones.

### Measured: apt packages — 3.43 GiB

Full dependency closure of the 86 explicitly installed packages (598 packages total), summing `Installed-Size` from the Ubuntu 26.10, Microsoft, and Azure CLI indexes. Excludes `docker-ce-cli` + `docker-compose-plugin` (~130 MB, not in the indexes checked).

Removing `mssql-server`, `libicu-dev` and `libopenblas-dev` took this from **5.00 GiB to 3.43 GiB — 1.57 GiB saved, 18 fewer packages**, with `mssql-tools18`, `msodbcsql18`, `unixodbc`, `odbcinst` and `libicu78` all still present.

The "marginal cost" column is what you actually get back by removing something — the package plus the dependencies nothing else needs:

| Component | Marginal cost | Notes |
|---|---:|---|
| `azure-cli` | **677 MiB** | apt build bundles its own Python and all deps |
| `rust-all` | **646 MiB** | `rust-1.93-src` 194 + `libstd-rust-dev` 188 + LLVM 216 |
| `dotnet-sdk-10.0` | **537 MiB** | Plus runtime and targeting packs |
| `golang-go` + `gopls` | 254 MiB | `golang-1.26-src` alone is 147 MiB |
| `ffmpeg` | 215 MiB | Pulls the full codec library set |
| `cmake` | 59 MiB | |
| `vim` + `nano` + `tmux` + `tig` + `htop` | 50 MiB | |
| `postgresql-18` + client | 32 MiB | Genuinely cheap |
| `tesseract-ocr` + eng data | 21 MiB | |
| `mssql-tools18` + `msodbcsql18` | ~1 MiB compressed | The client stack, kept. Microsoft's index omits `Installed-Size`, so this is **not** included in the 3.43 GiB above — add roughly 25 MB for it |
| Playwright system libs | 4 MiB | The libs are nearly free; browsers are not |

Removed, for reference: `mssql-server` was **1451 MiB** — the largest single item in the image. (`rust-all` and `postgresql-18` cost slightly more now that they no longer share dependencies with it.)

### Estimated: everything else — ~6 GB

| Component | Size | How it was derived |
|---|---:|---|
| `azure-functions-core-tools` | ~600 MiB | 553 MiB release zip, measured |
| GitHub Actions runner | ~550 MiB | 216 MiB tarball, measured; bundles its own .NET + Node |
| Azure DevOps agent | ~500 MiB | 207 MiB tarball, measured; same |
| .NET 11 preview SDK + ASP.NET runtime | ~800 MiB | Estimate from typical SDK tarball size |
| npm globals | ~450 MiB | Registry `unpackedSize`: `opencode-ai` 175, `happy` 107, `@ast-grep/cli` 51, rest small |
| Hermes + its Chromium | ~400 MiB | Its installer runs `playwright install --with-deps chromium` |
| Pre-warm caches (NuGet, Roslyn, LSPs) | ~400 MiB | The point of the image; buys first-run speed |
| .NET global tools (7) | ~350 MiB | |
| uv tools (ruff, pyright, mypy, …) | ~350 MiB | Wheels total 46 MiB; each tool gets its own venv |
| `/opt/venv` Python stack | ~450 MiB | Wheels total ~75 MiB, installed 1.5–2.5× plus transitive deps |
| Azure CLI extensions | ~300 MiB | 5 extensions incl. `aks-preview` |
| uv-managed Python 3.11 + 3.14 | ~250 MiB | Two standalone builds |
| tree-sitter grammars (10 clones) | ~200 MiB | Source only, not compiled |
| Standalone binaries | ~100 MiB | duckdb 20, rust-analyzer 14, lazygit, delta, yt-dlp, rtk |

### Already trimmed (~1.7 GB)

- **SQL Server engine → separate container** (−1451 MiB). The biggest single item, removed from an image you rebuild often. The client stack stays. See the SQL Server section above.
- **`libopenblas-dev`** (−107 MiB). Only needed to *compile* against BLAS; NumPy/SciPy wheels bundle their own OpenBLAS.
- **`libicu-dev`** (−50 MiB). Only needed to *compile* against ICU; `dotnet-runtime-10.0` depends on the runtime `libicu78`, which still comes in.
- **tree-sitter grammars trimmed** from 11 languages to 6 (−~90 MiB). Controlled by the `TREE_SITTER_GRAMMARS` build arg; `tree-sitter-cli` clones any other grammar on demand.

### Still available

**Build agents — drop unless you self-host (~1.05 GB):**

The Azure DevOps agent and GitHub Actions runner are ~1 GB together, each bundling its own .NET and Node, and **both self-update on registration anyway** — so the baked-in version is discarded the first time you configure one. Replace with a download-on-demand step inside `start-azp-agent.sh` / `start-gh-runner.sh`. Biggest remaining saving for the least loss.

**Agent CLIs (~280 MB):** drop whichever of the four you don't use — `opencode-ai` is 175 MiB, `happy` is 107 MiB. Each is a one-line `npm i -g` when wanted. Left in place because which ones matter is a per-user call.

**Real tradeoffs — only if you don't use them:**

| Drop | Saves | You lose |
|---|---:|---|
| .NET 11 preview SDK | ~800 MiB | Targeting .NET 11; .NET 10 SDK stays |
| `azure-functions-core-tools` | ~600 MiB | Local Functions host. Reinstallable via npm |
| `rust-all` → `rustc cargo rustfmt clippy` | ~250 MiB | `rust-src` (worse rust-analyzer completion) and Rust docs |
| `rust-all` entirely | ~646 MiB | Rust entirely; `rust-analyzer` would have nothing to analyse |
| `golang-go` + `gopls` | ~254 MiB | Go entirely |
| `ffmpeg` | ~215 MiB | Audio/video transcode; needed for whisper-style workflows |
| Hermes | ~400 MiB | The Hermes agent, and the trickiest step in the build |
| `azure-cli` apt → `uv tool install azure-cli` | ~300 MiB | Shares the system Python instead of bundling one. Less battle-tested |

The cuts applied so far take the image from ~11 GB to **roughly 9 GB with no loss of function**. Making the agents download-on-demand would land near 8 GB; adding the .NET 11 and Functions-tools cuts gets it to about 6.5 GB.

**What not to cut:** the pre-warm caches and PostgreSQL. The caches are the reason the container is fast on first use, and Postgres is 32 MiB — cheaper than the paragraph describing it.

### Auditing the real image

```bash
docker image ls aidev:latest                       # total
docker history --no-trunc --human aidev:latest      # cost per layer
# inside the container — biggest directories
docker compose -f .devcontainer/docker-compose.yml run --rm dev \
  sudo du -xh --max-depth=2 / 2>/dev/null | sort -rh | head -40
# biggest installed apt packages
docker compose -f .devcontainer/docker-compose.yml run --rm dev \
  dpkg-query -Wf '${Installed-Size}\t${Package}\n' | sort -rn | head -30
```

