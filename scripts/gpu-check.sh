#!/usr/bin/env bash
set -euo pipefail

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  echo "GPU(s) available:"
  nvidia-smi -L
  if command -v nvcc >/dev/null 2>&1; then
    nvcc --version | tail -n1
  fi
  exit 0
fi

cat <<'EOF'
No NVIDIA GPU detected inside this container.

If you have a GPU on the host, relaunch with:
  docker run --gpus all ...
or uncomment the `deploy.resources.reservations.devices` block in
.devcontainer/docker-compose.yml.

Host requirements:
  - NVIDIA driver installed
  - nvidia-container-toolkit installed and configured for your runtime
EOF
exit 1
