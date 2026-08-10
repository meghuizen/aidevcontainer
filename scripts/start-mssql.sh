#!/usr/bin/env bash
# Start SQL Server 2025 as the `mssql` compose service.
#
# The engine is NOT in this image (it was 1.45 GB of it) — it runs as a separate
# container from mcr.microsoft.com/mssql/server. This script keeps the same
# interface it always had: run it, get a ready server, password on disk at
# ~/.mssql-password.
#
# Works from inside the dev container (the host docker socket is mounted) and
# from the host.
#
# Every compose call below names the `mssql` service explicitly, and that matters
# when running from inside the dev container: compose resolves the dev service's
# relative bind mount (`../:/workspaces/aidevcontainer`) against the compose
# file's directory, which in here is an *in-container* path. Acting on `dev` from
# inside would hand that path to the host daemon and produce a broken container.
# Never run a bare `docker compose up` from inside the dev container.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

COMPOSE_FILE="$SCRIPT_DIR/../.devcontainer/docker-compose.yml"
PWFILE="${HOME}/.mssql-password"
SQLCMD=/opt/mssql-tools18/bin/sqlcmd
HOSTNAME_SQL="${MSSQL_HOST:-mssql}"

command -v docker >/dev/null || {
  echo "error: docker CLI not found" >&2; exit 2; }
docker info >/dev/null 2>&1 || {
  echo "error: cannot reach the Docker daemon." >&2
  echo "       Inside the dev container this needs /var/run/docker.sock mounted." >&2
  exit 2; }
[[ -f "$COMPOSE_FILE" ]] || {
  echo "error: compose file not found at $COMPOSE_FILE" >&2; exit 2; }

# First run: generate an SA password that satisfies SQL Server's complexity rules
# (upper, lower, digit, symbol, length >= 8). The fixed suffix guarantees all four.
if [[ ! -f "$PWFILE" ]]; then
  umask 077
  pw="$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 22)Aa1!"
  printf '%s' "$pw" > "$PWFILE"
  chmod 600 "$PWFILE"
  echo "mssql: generated SA password at $PWFILE"
fi
MSSQL_SA_PASSWORD="$(cat "$PWFILE")"
export MSSQL_SA_PASSWORD

if [[ -x "$SQLCMD" ]]; then
  aidev_already_running mssql \
    "$SQLCMD" -S "${HOSTNAME_SQL},1433" -U sa -P "$MSSQL_SA_PASSWORD" -No -Q "SELECT 1" \
    && exit 0
fi

echo "mssql: starting the ${HOSTNAME_SQL} compose service..."
docker compose -f "$COMPOSE_FILE" --profile mssql up -d mssql

if [[ ! -x "$SQLCMD" ]]; then
  echo "mssql: container started. sqlcmd is not on this host, so readiness was not"
  echo "       verified — check with: docker compose -f $COMPOSE_FILE logs -f mssql"
  exit 0
fi

# The engine takes a while on a fresh data volume (it creates master/model/msdb).
if ! aidev_wait_until mssql 90 2 \
      "$SQLCMD" -S "${HOSTNAME_SQL},1433" -U sa -P "$MSSQL_SA_PASSWORD" -No -Q "SELECT 1"; then
  echo "mssql: dumping container logs" >&2
  docker compose -f "$COMPOSE_FILE" logs --tail 40 mssql >&2 || true
  exit 1
fi

echo "mssql: connect with  sqlcmd -S ${HOSTNAME_SQL},1433 -U sa -P \"\$(cat $PWFILE)\" -No"
