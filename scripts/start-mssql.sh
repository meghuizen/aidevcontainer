#!/usr/bin/env bash
# Start SQL Server 2025 as the `mssql` compose service, from inside the dev
# container. The engine is NOT in this image (it was 1.45 GB of it) — it runs as a
# separate container from mcr.microsoft.com/mssql/server.
#
# From the host, run compose directly instead:
#   docker compose -p aidev -f .devcontainer/docker-compose.yml --profile mssql up -d mssql
#
# The compose call always names the `mssql` service. That matters in here:
# compose resolves the dev service's relative bind mount
# (`../:/workspaces/aidevcontainer`) against the compose file's directory, which
# in this container is an in-container path. Acting on `dev` from inside would
# hand that path to the host daemon and produce a broken container. Never run a
# bare `docker compose up` from inside the dev container.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

SQLCMD=/opt/mssql-tools18/bin/sqlcmd
aidev_must_be_in_container "$SQLCMD"

# Service name from the compose file == the DNS name on the compose network.
SQL_HOST=mssql
PWFILE="${HOME}/.mssql-password"
# -p is explicit: COMPOSE_PROJECT_NAME in the environment outranks the compose
# file's `name:`, and a different project means a different network and a fresh
# empty data volume.
COMPOSE=(docker compose -p aidev -f "$SCRIPT_DIR/../.devcontainer/docker-compose.yml")

docker info >/dev/null 2>&1 || {
  echo "error: cannot reach the Docker daemon." >&2
  echo "       Needs /var/run/docker.sock mounted and the vscode user in the docker" >&2
  echo "       group — try: sudo /usr/local/bin/fix-docker-perms" >&2
  exit 2; }

# If a container already exists, its SA password was fixed at creation time and
# is the only one the engine will accept: SQL Server applies MSSQL_SA_PASSWORD
# during first-time setup only, then stores the credential in master.mdf. Adopt
# it rather than passing a different value, which would make compose recreate the
# container and leave every login failing.
existing_pw="$("${COMPOSE[@]}" --profile mssql ps -aq mssql 2>/dev/null \
  | head -n1 \
  | xargs -r docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
  | sed -n 's/^MSSQL_SA_PASSWORD=//p' | head -n1 || true)"

if [[ -n "${existing_pw:-}" ]]; then
  if [[ ! -f "$PWFILE" ]] || [[ "$(cat "$PWFILE")" != "$existing_pw" ]]; then
    umask 077
    printf '%s' "$existing_pw" > "$PWFILE"
    chmod 600 "$PWFILE"
    echo "mssql: adopted the SA password from the existing container into $PWFILE"
  fi
elif [[ ! -f "$PWFILE" ]]; then
  # First run. SQL Server requires upper, lower, digit, symbol and length >= 8;
  # the fixed suffix guarantees all four character classes.
  umask 077
  printf '%s' "$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 22)Aa1!" > "$PWFILE"
  chmod 600 "$PWFILE"
  echo "mssql: generated SA password at $PWFILE"
fi

MSSQL_SA_PASSWORD="$(cat "$PWFILE")"
export MSSQL_SA_PASSWORD

probe=("$SQLCMD" -S "${SQL_HOST},1433" -U sa -P "$MSSQL_SA_PASSWORD" -No -Q "SELECT 1")
aidev_already_running mssql "${probe[@]}" && exit 0

echo "mssql: starting the ${SQL_HOST} compose service..."
"${COMPOSE[@]}" --profile mssql up -d mssql

# Fail fast on the common misconfiguration (wrong compose project => the dev
# container is not on the same network) instead of waiting out the full timeout.
if ! getent hosts "$SQL_HOST" >/dev/null 2>&1; then
  echo "error: '${SQL_HOST}' does not resolve from this container." >&2
  echo "       The dev container and the mssql service must be in the same compose" >&2
  echo "       project. Check COMPOSE_PROJECT_NAME is unset or 'aidev':" >&2
  echo "         docker inspect -f '{{index .Config.Labels \"com.docker.compose.project\"}}' \"\$(hostname)\"" >&2
  exit 1
fi

# A fresh data volume takes a while: the engine creates master/model/msdb.
if ! aidev_wait_until mssql 90 2 "${probe[@]}"; then
  echo "mssql: dumping container logs" >&2
  "${COMPOSE[@]}" --profile mssql logs --tail 40 mssql >&2 || true
  exit 1
fi

echo "mssql: connect with  sqlcmd -S ${SQL_HOST},1433 -U sa -P \"\$(cat $PWFILE)\" -No"
