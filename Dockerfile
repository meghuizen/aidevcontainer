# syntax=docker/dockerfile:1.7
###############################################################################
# ai-dev container — Ubuntu 26.10 (stonking)
#
# NOTE: 26.10 is a non-LTS interim release. At the time of writing it is still
# in development (GA October 2026), so `ubuntu:26.10` is a moving snapshot and
# third-party apt repos mostly do not publish a `stonking` suite yet. Only the
# Docker repo probes for a matching suite; Microsoft is pinned to `noble`,
# GitHub CLI uses `stable`, and NodeSource uses its distro-less `nodistro`.
#
# amd64v3: Ubuntu 26.10 publishes a second set of binaries built for the
# x86-64-v3 microarchitecture level (AVX2/FMA/BMI2 — Intel Haswell / AMD
# Excavator and newer). Enabling it is one apt config line; apt silently falls
# back to plain amd64 for any package that has no v3 build. Controlled by the
# ENABLE_AMD64V3 build arg (default 1). Set it to 0 if the image must run on a
# pre-2013 CPU — v3 binaries crash with SIGILL there.
#
# Single-stage build: ONE consolidated `apt-get install` for every native package
# the image needs (build deps + runtime tools + language runtimes + DBs +
# Playwright libs). Subsequent RUN steps build on top using those tools.
#
# Order:
#   1. ENV (telemetry off, locale, performance defaults)
#   2. Bootstrap apt (amd64v3 opt-in, apt/dpkg tuning, full-upgrade, repo keys)
#   3. Third-party apt repos (Microsoft, GitHub CLI, Docker, NodeSource)
#   4. ONE BIG apt install (build/runtime utilities + .NET 10 + Node + Python + DBs + Playwright libs)
#   5. vscode user (UID 1000) + system PATH profile
#   6. .NET global tools (Roslynator, Aspire CLI, csharp-ls, …) — against stable .NET 10 SDK
#   7. .NET 11 SDK side-by-side via dotnet-install.sh
#   8. npm prefix + corepack + npm global packages (azurite, Claude Code, Codex, …)
#   9. uv + uv-managed Python 3.11 / 3.14 + uv tools + /opt/venv
#  10. Az CLI extensions
#  11. Standalone binaries (yt-dlp, rust-analyzer, DuckDB, delta, lazygit, RTK, Hermes)
#  12. Build agents (Azure DevOps, GitHub Actions runner)
#  13. tree-sitter grammars + ast-grep rule packs
#  14. fix-docker-perms + entrypoint + resource limits (ulimit/sysctl)
#  15. Project scripts/configs + prewarm
#  16. Validation
#  17. USER vscode + ENTRYPOINT
###############################################################################

ARG UBUNTU_TAG=26.10
ARG GH_RUNNER_VERSION=2.336.0
ARG AZP_AGENT_VERSION=5.277.0
ARG RTK_VERSION=
ARG NODE_MAJOR=26
# NodeSource lags nodejs.org by a release or two — pin to the newest version its
# node_26.x repo actually publishes, or the madison lookup in step 4 silently
# falls back to unpinned `nodejs`.
ARG NODE_VERSION=26.6.0
ARG ENABLE_AMD64V3=1

FROM ubuntu:${UBUNTU_TAG}

ARG NODE_MAJOR
ARG NODE_VERSION
ARG GH_RUNNER_VERSION
ARG AZP_AGENT_VERSION
ARG RTK_VERSION
ARG ENABLE_AMD64V3
ARG UBUNTU_TAG

#-----------------------------------------------------------------------------
# 1. Environment
#
# Performance-related entries (the rest is telemetry/locale/tool paths):
#   MALLOC_ARENA_MAX=8         glibc malloc arenas. Was 2 (memory-saving, but it
#                              serialises allocation across threads). 8 matches a
#                              typical dev box core count and trades some RSS for
#                              throughput in multi-threaded builds/analysers.
#   DOTNET_EnableWriteXorExecute=0
#                              Disables W^X in the .NET JIT. Measurably faster
#                              process startup, which dominates `dotnet` CLI use.
#   DOTNET_TieredPGO=1         Profile-guided re-JIT of hot methods.
#   DOTNET_CLI_USE_MSBUILD_SERVER=1
#                              Keeps MSBuild worker processes warm between builds.
#   NODE_OPTIONS=--max-old-space-size=8192
#                              Raises the V8 heap ceiling (a ceiling, not an
#                              allocation) so big TS projects and agent CLIs don't
#                              OOM at the ~4 GB default.
#   UV_THREADPOOL_SIZE=16      libuv's thread pool (Node fs/dns/zlib work).
#                              Unrelated to the astral `uv` UV_* vars above.
#   UV_COMPILE_BYTECODE=1      astral uv: pre-compiles .pyc at install time so
#                              first import of an installed package is not slow.
#-----------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    TZ=Etc/UTC \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    NUGET_XMLDOC_MODE=skip \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    AZURE_CORE_COLLECT_TELEMETRY=no \
    NEXT_TELEMETRY_DISABLED=1 \
    DO_NOT_TRACK=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,video \
    PNPM_HOME=/home/vscode/.local/share/pnpm \
    PNPM_STORE_DIR=/home/vscode/.cache/pnpm \
    PLAYWRIGHT_BROWSERS_PATH=/home/vscode/.cache/ms-playwright \
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=1 \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/opt/uv-tools/bin \
    UV_PYTHON_INSTALL_DIR=/opt/uv-pythons \
    UV_HTTP_TIMEOUT=300 \
    UV_LINK_MODE=copy \
    AZURE_EXTENSION_DIR=/opt/az-extensions \
    DOTNET_ROOT=/usr/lib/dotnet \
    UV_COMPILE_BYTECODE=1 \
    MALLOC_ARENA_MAX=8 \
    DOTNET_EnableWriteXorExecute=0 \
    DOTNET_TieredPGO=1 \
    DOTNET_CLI_USE_MSBUILD_SERVER=1 \
    NODE_OPTIONS=--max-old-space-size=8192 \
    UV_THREADPOOL_SIZE=16 \
    PATH=/usr/local/dotnet-tools:/opt/uv-tools/bin:/opt/venv/bin:/home/vscode/.local/bin:/home/vscode/.local/share/pnpm:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/azp-agent:/opt/gh-runner

#-----------------------------------------------------------------------------
# 2. Bootstrap apt: build-speed tuning, amd64v3 opt-in, full upgrade, repo keys.
#
# `force-unsafe-io` skips dpkg's fsync after every unpacked file. Safe here —
# a container filesystem that dies mid-build is thrown away and rebuilt — and it
# is one of the biggest single wins on install time.
#
# `APT::Architecture-Variants "amd64v3"` is the official switch for Ubuntu's
# x86-64-v3 rebuilds. apt prefers the v3 binary when the suite publishes one and
# transparently uses the plain amd64 build otherwise, so this cannot break the
# package set — only the required CPU baseline.
#-----------------------------------------------------------------------------
COPY <<'EOF' /etc/dpkg/dpkg.cfg.d/01-aidev-unsafe-io
force-unsafe-io
EOF

COPY <<'EOF' /etc/apt/apt.conf.d/99-aidev
Acquire::Retries "5";
Acquire::Languages "none";
Dpkg::Use-Pty "0";
EOF

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    if [ "${ENABLE_AMD64V3}" = "1" ]; then \
        echo 'APT::Architecture-Variants "amd64v3";' > /etc/apt/apt.conf.d/99-amd64v3; \
        echo "amd64v3: enabled"; \
    else \
        echo "amd64v3: disabled (ENABLE_AMD64V3=${ENABLE_AMD64V3})"; \
    fi; \
    apt-get update; \
    apt-get full-upgrade -y; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        locales \
        lsb-release \
        software-properties-common; \
    locale-gen en_US.UTF-8; \
    update-locale LANG=en_US.UTF-8; \
    install -d -m 0755 /etc/apt/keyrings

#-----------------------------------------------------------------------------
# 3. Third-party apt repos (signed-by keyrings)
#-----------------------------------------------------------------------------
# Microsoft: mssql-server, mssql-tools18/msodbcsql18, Azure CLI.
# Deliberately still pinned to the noble (24.04) suites — Microsoft publishes no
# 26.10 suite, and its 26.04 "prod" feed carries only moby/kubernetes packages,
# not the SQL tooling. The noble debs install cleanly on 26.10 (their deps —
# libssl3t64, libicu78, unixodbc — all exist there).
#
# .NET is NOT taken from Microsoft any more: Ubuntu's own archive ships
# dotnet-sdk-10.0 (10.0.109-0ubuntu1) with an amd64v3 build, which the Microsoft
# feed does not. As of now the noble feed carries no .NET packages at all, but the
# pin below makes that independent of Microsoft's future publishing choices —
# otherwise a Microsoft `10.0.x-1` revision would out-rank Ubuntu's `-0ubuntu1`
# and install to /usr/share/dotnet, breaking DOTNET_ROOT.
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
 && chmod 0644 /etc/apt/keyrings/microsoft.gpg \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/24.04/prod noble main" \
      > /etc/apt/sources.list.d/microsoft-prod.list \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/24.04/mssql-server-2025 noble main" \
      > /etc/apt/sources.list.d/mssql-server-2025.list \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ noble main" \
      > /etc/apt/sources.list.d/azure-cli.list

# Keep .NET on the Ubuntu archive no matter what Microsoft publishes. Scoped to
# dotnet/aspnetcore only — mssql-tools18, msodbcsql18 and azure-cli still come
# from Microsoft and are unaffected.
COPY <<'EOF' /etc/apt/preferences.d/no-microsoft-dotnet
Package: dotnet* aspnetcore*
Pin: origin packages.microsoft.com
Pin-Priority: -1
EOF

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /etc/apt/keyrings/githubcli.gpg >/dev/null \
 && chmod 0644 /etc/apt/keyrings/githubcli.gpg \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list

# Docker CLI (daemon comes from host via mounted socket)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod 0644 /etc/apt/keyrings/docker.gpg \
 && CODENAME="$(lsb_release -cs 2>/dev/null || echo noble)" \
 && for c in "$CODENAME" questing noble; do \
        if curl -fsI "https://download.docker.com/linux/ubuntu/dists/${c}/Release" >/dev/null 2>&1; then \
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${c} stable" \
                > /etc/apt/sources.list.d/docker.list; \
            break; \
        fi; \
    done

# NodeSource Node (per-major repo)
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && chmod 0644 /etc/apt/keyrings/nodesource.gpg \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list

# PostgreSQL: no PGDG repo. Ubuntu 26.10 main ships postgresql-18 itself (with an
# amd64v3 build), so PGDG would only add a second origin for the same major — two
# sources racing over one `postgresql-18` package, which is exactly what we don't
# want. Single origin: the Ubuntu archive.
#
# Stop postgresql-common's postinst from auto-creating the 18/main cluster at BUILD
# time. Its cluster keeps postgresql.conf under /etc/postgresql/18/main, but
# scripts/start-postgres.sh installs this repo's config INTO the data dir and
# starts postgres with `-c config_file=$PG_DATA/postgresql.conf`. With an
# auto-created cluster the script sees a populated PG_DATA, skips its init branch,
# never installs the config, and postgres then dies on a missing config_file.
# Letting the script run initdb itself is the arrangement it was written for.
RUN install -d -m 0755 /etc/postgresql-common \
 && echo 'create_main_cluster = false' > /etc/postgresql-common/createcluster.conf

#-----------------------------------------------------------------------------
# 4. THE big apt install — every native package the image needs.
#    Bootstrap layer + repos already added; this is one apt-get install for
#    base utilities, language runtimes, DBs, and Playwright deps.
#
#    26.10 rename/removal notes vs 26.04:
#      libmagic1 -> libmagic1t64 (64-bit time_t transition)
#      repo (Android multi-repo tool) was dropped from the archive — installed
#      from Google's official launcher in step 11 instead.
#-----------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    export ACCEPT_EULA=Y MSSQL_PID=Developer DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    NODEJS_PKG="$(apt-cache madison nodejs | awk -v v="${NODE_VERSION}" '$3 ~ v {print "nodejs="$3; exit}')"; \
    : "${NODEJS_PKG:=nodejs}"; \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        bash-completion \
        build-essential \
        cmake \
        dirmngr \
        file \
        git \
        git-extras \
        git-lfs \
        htop \
        iproute2 \
        iputils-ping \
        jq \
        less \
        libicu-dev \
        libmagic1t64 \
        libssl-dev \
        man-db \
        nano \
        openssh-client \
        openssl \
        pkg-config \
        procps \
        ripgrep \
        rsync \
        sudo \
        tig \
        tmux \
        tree \
        tzdata \
        unzip \
        vim \
        wget \
        xz-utils \
        zip \
        zlib1g-dev \
        zstd \
        \
        dotnet-sdk-10.0 \
        \
        "$NODEJS_PKG" \
        \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        python-is-python3 \
        \
        azure-cli \
        bat \
        docker-ce-cli \
        docker-compose-plugin \
        fd-find \
        ffmpeg \
        fzf \
        gh \
        golang-go \
        gopls \
        mssql-server \
        mssql-tools18 \
        poppler-utils \
        postgresql-18 \
        postgresql-client-18 \
        libpq-dev \
        rust-all \
        sqlite3 \
        libopenblas-dev \
        libnss3 \
        libnss3-tools \
        libatk1.0-0t64 \
        libatk-bridge2.0-0t64 \
        libcups2t64 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxrandr2 \
        libxfixes3 \
        libxshmfence1 \
        libxext6 \
        libx11-xcb1 \
        libgbm1 \
        libpango-1.0-0 \
        libcairo2 \
        libasound2t64 \
        tesseract-ocr \
        tesseract-ocr-eng \
        tree-sitter-cli \
        unixodbc-dev \
        zoxide; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    ln -sf /usr/bin/batcat /usr/local/bin/bat 2>/dev/null || true; \
    test -x /usr/lib/dotnet/dotnet \
      || { echo "dotnet did not land in /usr/lib/dotnet — wrong origin? check apt-cache policy dotnet-sdk-10.0" >&2; \
           apt-cache policy dotnet-sdk-10.0 >&2; exit 1; }; \
    ln -sf /usr/lib/dotnet/dotnet /usr/local/bin/dotnet; \
    /usr/local/bin/dotnet --list-sdks

#-----------------------------------------------------------------------------
# 5. vscode user (UID 1000). The Ubuntu base image ships `ubuntu` at UID 1000;
#    rename it rather than fail trying to add a fresh one.
#-----------------------------------------------------------------------------
RUN if id -u vscode >/dev/null 2>&1; then \
        echo "vscode user already present"; \
    elif getent passwd 1000 >/dev/null 2>&1; then \
        OLD_USER="$(getent passwd 1000 | cut -d: -f1)"; \
        OLD_GROUP="$(getent group 1000 | cut -d: -f1)"; \
        echo "renaming existing UID 1000 user '$OLD_USER' (group '$OLD_GROUP') to vscode"; \
        groupmod -n vscode "$OLD_GROUP"; \
        usermod  -l vscode -d /home/vscode -m "$OLD_USER"; \
        chsh -s /bin/bash vscode; \
    else \
        groupadd -g 1000 vscode; \
        useradd  -u 1000 -g 1000 -m -s /bin/bash vscode; \
    fi \
 && echo 'vscode ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/vscode \
 && chmod 0440 /etc/sudoers.d/vscode

# PATH safety net for shells that start from a cleared environment (some CI
# agents, `su -`, `env -i bash -l`). Everything else — DOTNET_ROOT,
# MALLOC_ARENA_MAX, the perf vars — is set once by ENV above and inherited by
# login shells and `docker exec` alike. Do not restate ENV values here: this file
# and the ENV block silently drifting apart is a real failure mode.
COPY <<'EOF' /etc/profile.d/00-aidev-path.sh
export PATH="/usr/local/dotnet-tools:/opt/uv-tools/bin:/opt/venv/bin:/home/vscode/.local/bin:${PNPM_HOME:-/home/vscode/.local/share/pnpm}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/azp-agent:/opt/gh-runner"
EOF

#-----------------------------------------------------------------------------
# 6. .NET global tools — installed FIRST against the stable .NET 10 SDK so they
#    don't accidentally resolve against the .NET 11 preview SDK we add next.
#-----------------------------------------------------------------------------
RUN --mount=type=cache,target=/root/.nuget,sharing=locked \
    dotnet tool install --tool-path /usr/local/dotnet-tools Roslynator.DotNet.Cli \
 && dotnet tool install --tool-path /usr/local/dotnet-tools dotnet-ef \
 && dotnet tool install --tool-path /usr/local/dotnet-tools dotnet-format \
 && dotnet tool install --tool-path /usr/local/dotnet-tools dotnet-outdated-tool \
 && dotnet tool install --tool-path /usr/local/dotnet-tools dotnet-script \
 && dotnet tool install --tool-path /usr/local/dotnet-tools csharp-ls \
 && dotnet tool install --tool-path /usr/local/dotnet-tools Aspire.Cli \
 && { dotnet workload update --skip-sign-check && dotnet workload list; } \
      || echo "dotnet workloads: unavailable on this SDK build (non-fatal)"

#-----------------------------------------------------------------------------
# 7. .NET 11 side-by-side via dotnet-install.sh. Ubuntu 26.10's archive has
#    dotnet-sdk-10.0 but no dotnet-sdk-11.0, and .NET 11 is still preview.
#-----------------------------------------------------------------------------
#    Installed INTO /usr/lib/dotnet — the same root apt uses — because a single
#    DOTNET_ROOT is what makes `dotnet --list-sdks` show both majors.
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
 && chmod +x /tmp/dotnet-install.sh \
 && /tmp/dotnet-install.sh --channel 11.0 --quality preview --install-dir /usr/lib/dotnet --no-path \
 && /tmp/dotnet-install.sh --channel 11.0 --quality preview --install-dir /usr/lib/dotnet --runtime aspnetcore --no-path \
 && rm /tmp/dotnet-install.sh \
 && ls /usr/lib/dotnet/sdk \
 && ls /usr/lib/dotnet/shared/Microsoft.AspNetCore.App \
 && dotnet --list-sdks

#-----------------------------------------------------------------------------
# 8. npm config + corepack + global npm packages
#    pnpm = default package manager (corepack-managed). corepack is no longer
#    bundled with Node 25+ from NodeSource — install it explicitly.
#-----------------------------------------------------------------------------
RUN npm config set prefix /usr/local --location=global \
 && npm config set fetch-retries 5 --location=global \
 && npm config set fetch-retry-mintimeout 20000 --location=global \
 && npm config set fetch-retry-maxtimeout 120000 --location=global \
 && npm config set fetch-timeout 600000 --location=global \
 && npm install -g --no-audit --no-fund corepack \
 && corepack enable --install-directory /usr/local/bin pnpm yarn \
 && corepack prepare pnpm@latest --activate \
 && corepack prepare yarn@stable --activate \
 && pnpm --version && yarn --version && npm --version

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g --no-audit --no-fund --prefer-offline \
        azurite \
        azure-functions-core-tools@4 \
        @anthropic-ai/claude-code \
        @openai/codex \
        opencode-ai \
        typescript \
        typescript-language-server \
        vscode-langservers-extracted \
        bash-language-server \
        yaml-language-server \
        dockerfile-language-server-nodejs \
        sql-language-server \
        @ast-grep/cli \
        playwright \
        @playwright/cli \
        happy

#-----------------------------------------------------------------------------
# 9. uv + Python 3.11 + 3.14 + uv tools + /opt/venv
#-----------------------------------------------------------------------------
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh \
 && /usr/local/bin/uv --version && /usr/local/bin/uvx --version

# Preinstall Python 3.11 and 3.14 alongside Ubuntu's apt python3.
RUN --mount=type=cache,target=/root/.cache/uv,sharing=locked \
    uv python install 3.11 3.14 \
 && uv python find 3.11 \
 && uv python find 3.14

# Expose uv-managed Pythons as python3.11 / python3.14 on PATH.
RUN set -eux; \
    for ver in 3.11 3.14; do \
        PY="$(find /opt/uv-pythons -maxdepth 4 -type f -name "python${ver}" -executable 2>/dev/null | head -n1)"; \
        [ -x "$PY" ] || { echo "uv python ${ver} not found under /opt/uv-pythons" >&2; exit 1; }; \
        ln -sf "$PY" "/usr/local/bin/python${ver}"; \
        "/usr/local/bin/python${ver}" --version; \
    done

# uv-managed dev tools (resolved against the apt-installed system python3)
RUN --mount=type=cache,target=/root/.cache/uv,sharing=locked \
    mkdir -p /opt/uv-tools/bin \
 && uv tool install ruff \
 && uv tool install pyright \
 && uv tool install basedpyright \
 && uv tool install mypy \
 && uv tool install pytest \
 && uv tool install ipython \
 && uv tool install python-lsp-server \
 && uv tool install pre-commit

# Prebuilt venv at /opt/venv with the doc / AI / MCP stack.
# openai-whisper / faster-whisper / whisper.cpp intentionally NOT installed
# (would pull ~2 GB of torch+CUDA wheels we don't want by default).
RUN --mount=type=cache,target=/root/.cache/uv,sharing=locked \
    uv venv --python /usr/bin/python3 /opt/venv \
 && uv pip install --python /opt/venv/bin/python \
        huggingface_hub[cli] \
        python-docx \
        python-pptx \
        openpyxl \
        pypdf \
        pdfplumber \
        pillow \
        pytesseract \
        pdf2image \
        python-magic \
        duckdb \
        polars \
        pandas \
        numpy \
        jupyterlab \
        mcp \
        fastmcp \
        starlette \
        uvicorn \
        httpx

#-----------------------------------------------------------------------------
# 10. Az CLI extensions (system-wide via AZURE_EXTENSION_DIR)
#-----------------------------------------------------------------------------
RUN mkdir -p /opt/az-extensions \
 && az extension add --name azure-devops --yes \
 && az extension add --name serviceconnector-passwordless --yes \
 && az extension add --name containerapp          --yes --allow-preview true \
 && az extension add --name application-insights  --yes --allow-preview true \
 && az extension add --name aks-preview           --yes --allow-preview true

#-----------------------------------------------------------------------------
# 11. Standalone binaries (curl + extract pattern)
#-----------------------------------------------------------------------------
# yt-dlp (self-contained Python zipapp from upstream releases)
RUN curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o /usr/local/bin/yt-dlp \
 && chmod +x /usr/local/bin/yt-dlp \
 && yt-dlp --version

# repo (Android multi-repository tool). Ubuntu 26.10 dropped the `repo` package;
# this is the official launcher script, which needs only python3.
RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
 && chmod 0755 /usr/local/bin/repo \
 && head -n1 /usr/local/bin/repo | grep -q python

# rust-analyzer (not in Ubuntu apt repos)
RUN curl -fsSL "https://github.com/rust-lang/rust-analyzer/releases/latest/download/rust-analyzer-x86_64-unknown-linux-gnu.gz" \
      -o /tmp/rust-analyzer.gz \
 && gunzip /tmp/rust-analyzer.gz \
 && install -m 0755 /tmp/rust-analyzer /usr/local/bin/rust-analyzer \
 && rm /tmp/rust-analyzer \
 && rust-analyzer --version

# DuckDB CLI
RUN curl -fsSL "https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip" -o /tmp/duckdb.zip \
 && unzip -q /tmp/duckdb.zip -d /usr/local/bin \
 && chmod +x /usr/local/bin/duckdb \
 && rm /tmp/duckdb.zip

# delta — version-in-filename, resolve dynamically
RUN set -eux; \
    DELTA_TAG="$(curl -fsSL https://api.github.com/repos/dandavison/delta/releases/latest | jq -r .tag_name)"; \
    DELTA_VER="${DELTA_TAG#v}"; \
    curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_TAG}/delta-${DELTA_VER}-x86_64-unknown-linux-gnu.tar.gz" -o /tmp/delta.tgz; \
    tar -xzf /tmp/delta.tgz -C /tmp; \
    install -m 0755 "/tmp/delta-${DELTA_VER}-x86_64-unknown-linux-gnu/delta" /usr/local/bin/delta; \
    rm -rf /tmp/delta*; \
    delta --version

# lazygit — version-in-filename, resolve dynamically
RUN set -eux; \
    LG_TAG="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name)"; \
    LG_VER="${LG_TAG#v}"; \
    curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${LG_TAG}/lazygit_${LG_VER}_Linux_x86_64.tar.gz" -o /tmp/lz.tgz; \
    tar -xzf /tmp/lz.tgz -C /usr/local/bin lazygit; \
    chmod +x /usr/local/bin/lazygit; \
    rm /tmp/lz.tgz; \
    lazygit --version

# Hermes agent (NousResearch). Two installer-environment hacks needed:
#  - Force HTTPS for git clones — installer tries SSH first, no credentials in build env.
#  - Spoof /etc/os-release as Ubuntu 24.04 for the duration of the install. The installer
#    runs `npx playwright install --with-deps chromium`; Playwright's binary-host map
#    doesn't include ubuntu26.10-x64 yet and rejects with "does not support chromium on
#    ubuntu26.10-x64". Pretending to be 24.04 (noble) lets the Chromium download proceed
#    against the apt deps we already installed (libnss3, libcups2t64, libatk*t64, etc.).
#    /etc/os-release is restored after the install so `lsb_release -a` etc. report 26.10.
RUN set -eux; \
    install -d -m 0755 /opt/hermes-install; \
    git config --system url."https://github.com/".insteadOf "git@github.com:"; \
    git config --system url."https://github.com/".insteadOf "ssh://git@github.com/"; \
    cp /etc/os-release /etc/os-release.real; \
    sed -i 's/^VERSION_ID=.*/VERSION_ID="24.04"/; \
            s/^VERSION_CODENAME=.*/VERSION_CODENAME=noble/; \
            s/^UBUNTU_CODENAME=.*/UBUNTU_CODENAME=noble/; \
            s/^VERSION="[^"]*"/VERSION="24.04 LTS (Noble Numbat)"/; \
            s/^PRETTY_NAME=.*/PRETTY_NAME="Ubuntu 24.04 LTS"/' /etc/os-release; \
    HOME=/opt/hermes-install bash -c \
        'curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash' \
    || true; \
    mv -f /etc/os-release.real /etc/os-release; \
    if [ ! -x /usr/local/bin/hermes ]; then \
        BIN="$(find /opt/hermes-install /root /usr/local -maxdepth 5 -type f -name hermes -executable 2>/dev/null | head -n1)"; \
        if [ -n "$BIN" ]; then install -m 0755 "$BIN" /usr/local/bin/hermes; \
        else echo "hermes: install.sh did not produce a hermes binary" >&2; exit 1; fi; \
    fi; \
    test -x /usr/local/bin/hermes

# RTK (Rust Token Killer)
RUN set -eux; \
    if [ -n "${RTK_VERSION}" ]; then TAG="${RTK_VERSION}"; \
    else TAG="$(curl -fsSL https://api.github.com/repos/rtk-ai/rtk/releases/latest | jq -r .tag_name)"; fi; \
    curl -fsSL "https://github.com/rtk-ai/rtk/releases/download/${TAG}/rtk-x86_64-unknown-linux-musl.tar.gz" -o /tmp/rtk.tgz; \
    tar -xzf /tmp/rtk.tgz -C /tmp; \
    install -m 0755 /tmp/rtk /usr/local/bin/rtk 2>/dev/null \
      || install -m 0755 "$(find /tmp -maxdepth 3 -type f -name rtk -executable | head -n1)" /usr/local/bin/rtk; \
    rm -rf /tmp/rtk*; \
    /usr/local/bin/rtk --version

#-----------------------------------------------------------------------------
# 12. Build agents (Azure DevOps + GitHub Actions)
#-----------------------------------------------------------------------------
RUN mkdir -p /opt/azp-agent \
 && curl -fsSL "https://download.agent.dev.azure.com/agent/${AZP_AGENT_VERSION}/vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz" \
      -o /tmp/azp.tgz \
 && tar -xzf /tmp/azp.tgz -C /opt/azp-agent \
 && rm /tmp/azp.tgz \
 && /opt/azp-agent/bin/installdependencies.sh || true \
 && chown -R vscode:vscode /opt/azp-agent

RUN mkdir -p /opt/gh-runner \
 && curl -fsSL "https://github.com/actions/runner/releases/download/v${GH_RUNNER_VERSION}/actions-runner-linux-x64-${GH_RUNNER_VERSION}.tar.gz" \
      -o /tmp/ghr.tgz \
 && tar -xzf /tmp/ghr.tgz -C /opt/gh-runner \
 && rm /tmp/ghr.tgz \
 && /opt/gh-runner/bin/installdependencies.sh || true \
 && chown -R vscode:vscode /opt/gh-runner

#-----------------------------------------------------------------------------
# 13. Tree-sitter grammars + ast-grep rule packs
#-----------------------------------------------------------------------------
RUN mkdir -p /opt/tree-sitter-grammars \
 && for g in c-sharp python typescript javascript bash rust go sql yaml html css; do \
        git clone --depth=1 "https://github.com/tree-sitter/tree-sitter-${g}.git" \
            "/opt/tree-sitter-grammars/tree-sitter-${g}" \
            2>/dev/null || echo "skip ${g}"; \
    done \
 && rm -rf /opt/tree-sitter-grammars/*/.git

RUN git clone --depth=1 https://github.com/ast-grep/awesome-rules.git /opt/ast-grep/rules || true \
 && rm -rf /opt/ast-grep/rules/.git

#-----------------------------------------------------------------------------
# 14. fix-docker-perms + entrypoint
#-----------------------------------------------------------------------------
# `set -e` is intentionally OFF: every step is best-effort and a missing socket
# (running without docker mount) must be a no-op, not a failure.
COPY <<'EOF' /usr/local/bin/fix-docker-perms
#!/usr/bin/env bash
set -uo pipefail
SOCK=/var/run/docker.sock
[[ -S "$SOCK" ]] || exit 0
GID=$(stat -c '%g' "$SOCK" 2>/dev/null || echo "")
[[ -z "$GID" ]] && exit 0
if ! getent group docker >/dev/null; then
    groupadd -g "$GID" docker 2>/dev/null || groupadd docker
fi
groupmod -g "$GID" docker 2>/dev/null || true
usermod -aG docker vscode 2>/dev/null || true
EOF
RUN chmod +x /usr/local/bin/fix-docker-perms

COPY <<'EOF' /usr/local/bin/aidev-entrypoint
#!/usr/bin/env bash
set -uo pipefail
if [[ "$EUID" -eq 0 ]]; then
  /usr/local/bin/fix-docker-perms || true
else
  sudo -n /usr/local/bin/fix-docker-perms 2>/dev/null || true
fi
exec "$@"
EOF
RUN chmod +x /usr/local/bin/aidev-entrypoint

#-----------------------------------------------------------------------------
# Resource limits.
#
# Two separate mechanisms, both needed:
#
#  a) limits.d — pam_limits, which only runs for *login-ish* sessions (`su`,
#     `sudo -i`, ssh). It is what raises limits for the DB servers we start via
#     `sudo -u postgres` / `sudo -u mssql`.
#  b) profile.d — raises each interactive shell's SOFT limit to its HARD limit.
#     A `docker exec` does not go through PAM, so it inherits whatever the
#     container was created with; the hard ceiling itself comes from the Docker
#     daemon, i.e. the `ulimits:` block in .devcontainer/docker-compose.yml.
#
# nofile is the one that actually bites: pnpm/node watchers, Roslyn, and
# ripgrep all burn file descriptors fast. memlock matters for SQL Server's
# locked pages and for io_uring. core=0 stops multi-GB core dumps from .NET or
# Chromium filling the container's writable layer.
#-----------------------------------------------------------------------------
# Values must match the compose `ulimits:` block — the container ceiling always
# wins, so a larger number here would just be a lie. `*` does not cover root in
# limits.conf, hence the explicit root rows.
COPY <<'EOF' /etc/security/limits.d/90-aidev.conf
# domain  type   item     value
*         soft   nofile   1048576
*         hard   nofile   1048576
*         soft   nproc    262144
*         hard   nproc    262144
*         soft   memlock  unlimited
*         hard   memlock  unlimited
*         soft   stack    8192
*         hard   stack    65536
*         soft   core     0
*         hard   core     0
root      soft   nofile   1048576
root      hard   nofile   1048576
root      soft   nproc    262144
root      hard   nproc    262144
root      soft   memlock  unlimited
root      hard   memlock  unlimited
root      soft   stack    8192
root      hard   stack    65536
root      soft   core     0
root      hard   core     0
EOF

# Raise soft limits to the hard ceiling the container was started with. Under the
# compose file these are already correct; the lines matter for a plain
# `docker run` with no --ulimit flags, where memlock defaults to 64 KB and core
# dumps are unbounded. Best-effort: a restricted container keeps its defaults.
COPY <<'EOF' /etc/profile.d/10-aidev-limits.sh
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true
ulimit -l unlimited       2>/dev/null || true
ulimit -c 0               2>/dev/null || true
EOF

# Kernel tunables that are NOT namespaced, so they can only come from the host or
# a privileged run. NOTE: nothing applies /etc/sysctl.d inside an unprivileged
# container (no systemd-sysctl here) — this file is inert there, and is kept as
# the documented target plus a privileged-run convenience.
# The namespaced values (net.core.somaxconn, net.ipv4.ip_local_port_range) are
# deliberately NOT here: compose `sysctls:` owns those, one home per number.
COPY <<'EOF' /etc/sysctl.d/90-aidev.conf
# File watching — VS Code, dotnet watch, vite, and pnpm all register watches.
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=8192
fs.file-max=2097152
# Many small mmaps: .NET, JVM-style tooling, Chromium.
vm.max_map_count=1048576
# Prefer keeping page cache over swapping build artefacts out.
vm.swappiness=10
EOF

#-----------------------------------------------------------------------------
# 15. Project scripts/configs + prewarm
#-----------------------------------------------------------------------------
COPY scripts /opt/aidev/scripts
COPY tests   /opt/aidev/tests
COPY config  /opt/aidev/config
RUN chmod +x /opt/aidev/scripts/*.sh /opt/aidev/tests/*.sh

# Pre-create vscode home subdirs and pre-warm analyzer caches in one pass.
# `sudo` resets PATH to its `secure_path`, stripping our /usr/local/dotnet-tools and
# /opt/uv-tools/bin entries — the script's `command -v` checks would silently skip those
# tools. Pass PATH explicitly via `env` so the prewarm actually covers what we installed.
RUN mkdir -p /home/vscode/.cache /home/vscode/.local/share /home/vscode/.config \
            /home/vscode/.nuget /home/vscode/.dotnet /home/vscode/.npm /home/vscode/.azure \
            /home/vscode/.claude /home/vscode/.cache/uv /home/vscode/.cache/huggingface \
            /home/vscode/.cache/pnpm /home/vscode/.local/share/pnpm \
 && chown -R vscode:vscode /home/vscode \
 && sudo -u vscode -H env "PATH=$PATH" bash /opt/aidev/scripts/prewarm-lsp.sh || true

#-----------------------------------------------------------------------------
# 16. Validation — fail loud if anything critical is missing
#-----------------------------------------------------------------------------
# Report the base release so a stale cached layer or a retagged base is visible in
# the build log. Deliberately a warning, not a failure: on a pre-GA series the
# base image's VERSION_ID is not something to bet a whole build on.
# tests/smoke.sh asserts the release properly, at run time.
RUN set -eu; \
    . /etc/os-release; \
    echo "release: ${VERSION_ID:-?} ${VERSION_CODENAME:-?} (requested ${UBUNTU_TAG})"; \
    [ "${VERSION_ID:-}" = "${UBUNTU_TAG}" ] \
      || echo "WARNING: base image is Ubuntu ${VERSION_ID:-unknown}, expected ${UBUNTU_TAG}" >&2

# `ld.so` is not on PATH on Ubuntu — ask the dynamic loader directly. It lists the
# glibc-hwcaps levels it will search, e.g. "x86-64-v3 (supported, searched)".
RUN set -eu; \
    if [ "${ENABLE_AMD64V3}" = "1" ]; then \
        apt-config dump | grep -qi 'APT::Architecture-Variants.*amd64v3' \
          || { echo "amd64v3 was requested but apt is not configured for it" >&2; exit 1; }; \
        LOADER="$(command -v ld.so || echo /lib64/ld-linux-x86-64.so.2)"; \
        if "$LOADER" --help 2>/dev/null | grep -q 'x86-64-v3.*supported'; then \
            echo "amd64v3: build host CPU supports x86-64-v3"; \
        else \
            echo "amd64v3: NOTE — could not confirm x86-64-v3 on this build host." >&2; \
            echo "amd64v3: the image is still valid; it just needs a v3-capable CPU to run." >&2; \
        fi; \
    fi

RUN id mssql >/dev/null    || { echo "mssql user not created — mssql-server postinst failed" >&2; exit 1; } \
 && id postgres >/dev/null || { echo "postgres user not created — postgresql-18 postinst failed" >&2; exit 1; } \
 && test -x /usr/lib/postgresql/18/bin/postgres \
 && test -x /usr/local/bin/repo \
 && test -f /etc/security/limits.d/90-aidev.conf \
 && test -x /opt/mssql/bin/sqlservr \
 && test -x /opt/mssql-tools18/bin/sqlcmd \
 && test -x /usr/local/bin/dotnet \
 && test -x /usr/local/bin/uv \
 && test -x /usr/local/bin/rtk \
 && test -x /usr/local/bin/hermes \
 && test -x /usr/local/bin/yt-dlp \
 && test -x /usr/bin/node \
 && command -v npm    >/dev/null \
 && command -v pnpm   >/dev/null \
 && command -v yarn   >/dev/null \
 && command -v rg     >/dev/null \
 && command -v sg     >/dev/null \
 && command -v aspire >/dev/null \
 && command -v claude >/dev/null \
 && command -v codex  >/dev/null \
 && command -v opencode >/dev/null \
 && command -v happy  >/dev/null \
 && command -v playwright >/dev/null \
 && command -v playwright-cli >/dev/null \
 && /usr/bin/python3 -c "import sys; print(sys.version)" \
 && /usr/local/bin/python3.11 -c "import sys; assert sys.version_info[:2] == (3,11)" \
 && /usr/local/bin/python3.14 -c "import sys; assert sys.version_info[:2] == (3,14)" \
 && /opt/venv/bin/python -c "import huggingface_hub, docx, pptx, openpyxl, pypdf, duckdb, polars"

USER vscode
WORKDIR /workspaces/aidevcontainer

ENTRYPOINT ["/usr/local/bin/aidev-entrypoint"]
CMD ["sleep", "infinity"]

LABEL org.opencontainers.image.title="ai-dev" \
      org.opencontainers.image.description="High-performance dev container for AI software development on Ubuntu 26.10 (amd64v3-optimized)" \
      org.opencontainers.image.source="https://github.com/" \
      org.opencontainers.image.licenses="MIT"
