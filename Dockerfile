# syntax=docker/dockerfile:1.7
###############################################################################
# ai-dev container — Ubuntu 26.04 LTS (Resolute Raccoon)
#
# Single-stage build: ONE consolidated `apt-get install` for every native package
# the image needs (build deps + runtime tools + language runtimes + DBs +
# Playwright libs). Subsequent RUN steps build on top using those tools.
#
# Order:
#   1. ENV (telemetry off, locale, etc.)
#   2. Bootstrap apt (curl, ca-certs, gnupg, lsb-release, software-properties-common)
#   3. Third-party apt repos (Microsoft, GitHub CLI, Docker, NodeSource, PGDG)
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
#  14. fix-docker-perms + entrypoint scripts
#  15. Project scripts/configs + prewarm
#  16. Validation
#  17. USER vscode + ENTRYPOINT
###############################################################################

ARG UBUNTU_TAG=26.04
ARG GH_RUNNER_VERSION=2.334.0
ARG AZP_AGENT_VERSION=4.272.0
ARG RTK_VERSION=
ARG NODE_MAJOR=25
ARG NODE_VERSION=25.9.0

FROM ubuntu:${UBUNTU_TAG}

ARG NODE_MAJOR
ARG NODE_VERSION
ARG GH_RUNNER_VERSION
ARG AZP_AGENT_VERSION
ARG RTK_VERSION

#-----------------------------------------------------------------------------
# 1. Environment
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
    DOTNET_ROOT=/usr/share/dotnet \
    MALLOC_ARENA_MAX=2 \
    PATH=/usr/local/dotnet-tools:/opt/uv-tools/bin:/opt/venv/bin:/home/vscode/.local/bin:/home/vscode/.local/share/pnpm:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/azp-agent:/opt/gh-runner

#-----------------------------------------------------------------------------
# 2. Bootstrap apt (only what's needed to fetch repo keys)
#-----------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        locales \
        lsb-release \
        software-properties-common \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 \
    && install -d -m 0755 /etc/apt/keyrings

#-----------------------------------------------------------------------------
# 3. Third-party apt repos (signed-by keyrings)
#-----------------------------------------------------------------------------
# Microsoft (.NET, mssql-tools18, mssql-server) + Azure CLI dedicated feed
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
 && chmod 0644 /etc/apt/keyrings/microsoft.gpg \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/24.04/prod noble main" \
      > /etc/apt/sources.list.d/microsoft-prod.list \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/24.04/mssql-server-2025 noble main" \
      > /etc/apt/sources.list.d/mssql-server-2025.list \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ noble main" \
      > /etc/apt/sources.list.d/azure-cli.list

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
 && for c in "$CODENAME" noble; do \
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

# PostgreSQL (PGDG) — fail loudly if no codename works so the build doesn't silently fall back to
# stock Ubuntu's postgres (wrong major).
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /etc/apt/keyrings/pgdg.gpg \
 && chmod 0644 /etc/apt/keyrings/pgdg.gpg \
 && set -e; \
    for c in resolute-pgdg plucky-pgdg noble-pgdg; do \
        if curl -fsI "https://apt.postgresql.org/pub/repos/apt/dists/${c}/Release" >/dev/null 2>&1; then \
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt ${c} main" \
                > /etc/apt/sources.list.d/pgdg.list; \
            echo "PGDG: using ${c}"; \
            FOUND=1; break; \
        fi; \
    done; \
    [ -n "${FOUND:-}" ] || { echo "PGDG: no codename available (tried resolute-pgdg plucky-pgdg noble-pgdg)" >&2; exit 1; }

#-----------------------------------------------------------------------------
# 4. THE big apt install — every native package the image needs.
#    Bootstrap layer + repos already added; this is one apt-get install for
#    base utilities, language runtimes, DBs, and Playwright deps.
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
        libmagic1 \
        libssl-dev \
        man-db \
        nano \
        openssh-client \
        openssl \
        pkg-config \
        procps \
        repo \
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
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet

#-----------------------------------------------------------------------------
# 5. vscode user (UID 1000). Ubuntu 26.04 base ships with `ubuntu` at UID 1000;
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

# Centralized PATH for interactive shells (mirrors the ENV PATH above)
COPY <<'EOF' /etc/profile.d/00-aidev-path.sh
export PATH="/usr/local/dotnet-tools:/opt/uv-tools/bin:/opt/venv/bin:/home/vscode/.local/bin:${PNPM_HOME:-/home/vscode/.local/share/pnpm}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/azp-agent:/opt/gh-runner"
export DOTNET_ROOT=/usr/share/dotnet
export MALLOC_ARENA_MAX=2
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
 && dotnet workload update --skip-sign-check \
 && dotnet workload list

#-----------------------------------------------------------------------------
# 7. .NET 11 side-by-side via dotnet-install.sh (apt only ships .NET 10)
#-----------------------------------------------------------------------------
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
 && chmod +x /tmp/dotnet-install.sh \
 && /tmp/dotnet-install.sh --channel 11.0 --quality preview --install-dir /usr/share/dotnet --no-path \
 && /tmp/dotnet-install.sh --channel 11.0 --quality preview --install-dir /usr/share/dotnet --runtime aspnetcore --no-path \
 && rm /tmp/dotnet-install.sh \
 && ls /usr/share/dotnet/sdk \
 && ls /usr/share/dotnet/shared/Microsoft.AspNetCore.App

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

# rust-analyzer (not in Ubuntu 26.04 apt repos)
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
#    doesn't include ubuntu26.04-x64 yet and rejects with "does not support chromium on
#    ubuntu26.04-x64". Pretending to be 24.04 (noble) lets the Chromium download proceed
#    against the apt deps we already installed (libnss3, libcups2t64, libatk*t64, etc.).
#    /etc/os-release is restored after the install so `lsb_release -a` etc. report 26.04.
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

# inotify limits (best-effort; ignored if container lacks the cap)
RUN printf 'fs.inotify.max_user_watches=524288\nfs.inotify.max_user_instances=8192\n' \
      > /etc/sysctl.d/90-inotify.conf

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
RUN id mssql >/dev/null    || { echo "mssql user not created — mssql-server postinst failed" >&2; exit 1; } \
 && id postgres >/dev/null || { echo "postgres user not created — postgresql-18 postinst failed" >&2; exit 1; } \
 && test -x /usr/lib/postgresql/18/bin/postgres \
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
      org.opencontainers.image.description="High-performance dev container for AI software development on Ubuntu 26.04 (Resolute Raccoon)" \
      org.opencontainers.image.source="https://github.com/" \
      org.opencontainers.image.licenses="MIT"
