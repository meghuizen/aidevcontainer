#!/usr/bin/env bash
# Start SQL Server 2025 as the `mssql` compose service. Run this from INSIDE the
# dev container. The engine is not in this image (it was 1.45 GB of it) — it runs
# as a separate container from mcr.microsoft.com/mssql/server.
#
# From the host, run compose directly instead:
#   docker compose -f .devcontainer/docker-compose.yml --profile mssql up -d mssql
#
# The compose calls always name the `mssql` service. That matters in here:
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

# Service name from the compose file == its DNS name on the compose network.
SQL_HOST=mssql
PWFILE="${HOME}/.mssql-password"

docker info >/dev/null 2>&1 || {
  echo "error: cannot reach the Docker daemon." >&2
  echo "       Needs /var/run/docker.sock mounted and the vscode user in the docker" >&2
  echo "       group — try: sudo /usr/local/bin/fix-docker-perms" >&2
  exit 2; }

# aidev_compose (in _lib.sh) targets this container's own compose project, so the
# service lands on the network the dev container is actually attached to.
AIDEV_SCRIPT_DIR="$SCRIPT_DIR"
PROJECT="$(aidev_compose_project)"

# `sqlcmd` reads SQLCMDPASSWORD, so the password never appears in argv (the wait
# loop below re-execs the probe up to 90 times — that would be 90 chances for any
# process in this container to read it out of /proc).
try_login() {
  SQLCMDPASSWORD="$1" "$SQLCMD" -S "${SQL_HOST},1433" -U sa -No -Q "SELECT 1" \
    >/dev/null 2>&1
}
save_password() {
  umask 077
  printf '%s' "$1" > "$PWFILE"
  chmod 600 "$PWFILE"
}

#---------------------------------------------------------------------------
# Work out which password to use.
#
# SQL Server applies MSSQL_SA_PASSWORD during first-time setup ONLY; afterwards
# the credential lives in master.mdf and the environment variable is ignored. So
# for an existing container the value baked into it at creation is the only one
# compose may be given — passing anything else makes compose recreate the
# container and leaves every login failing.
#
# But a password rotated in-engine (ALTER LOGIN) is newer than that baked value,
# so ~/.mssql-password is never overwritten just because it differs. It is only
# replaced when it is absent, or when it is proven not to work.
#---------------------------------------------------------------------------
# Captured into a variable first: a failing `ps` inside a process substitution
# would leave CIDS empty and read as "no container", which is the one mistake that
# leads to compose recreating the engine with a password it will then ignore.
cids_raw="$(aidev_compose --profile mssql ps -aq mssql)" || {
  echo "error: 'docker compose ps' failed — refusing to continue, because treating" >&2
  echo "       this as 'no container exists' risks breaking sa login permanently." >&2
  exit 1; }
mapfile -t CIDS < <(printf '%s\n' "$cids_raw" | sed '/^$/d')
if (( ${#CIDS[@]} > 1 )); then
  echo "error: ${#CIDS[@]} mssql containers exist in compose project '$PROJECT'." >&2
  echo "       Refusing to guess which one owns the data volume. Remove the extras:" >&2
  printf '         docker rm -f %s\n' "${CIDS[@]}" >&2
  exit 1
fi

baked_pw=""
if (( ${#CIDS[@]} == 1 )); then
  # No error suppression here: a failed read must not look like "no container",
  # which would send a freshly generated password to compose and trigger a
  # recreate that permanently breaks sa login.
  baked_pw="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "${CIDS[0]}" \
              | sed -n 's/^MSSQL_SA_PASSWORD=//p' | head -n1)"
  if [[ -z "$baked_pw" ]]; then
    echo "error: container ${CIDS[0]} has no MSSQL_SA_PASSWORD in its config." >&2
    echo "       Cannot recover the SA password. Recreate it with a known password:" >&2
    echo "         docker rm -f ${CIDS[0]}   # the data volume survives" >&2
    exit 1
  fi
fi

file_pw=""
[[ -f "$PWFILE" ]] && file_pw="$(cat "$PWFILE")"

if [[ -z "$file_pw" && -z "$baked_pw" ]]; then
  # Genuine first run. SQL Server wants upper, lower, digit, symbol, length >= 8;
  # the fixed suffix guarantees all four classes.
  file_pw="$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 22)Aa1!"
  save_password "$file_pw"
  echo "mssql: generated SA password at $PWFILE"
elif [[ -z "$file_pw" ]]; then
  file_pw="$baked_pw"
  save_password "$file_pw"
  echo "mssql: recovered the SA password from the existing container into $PWFILE"
fi

#---------------------------------------------------------------------------
# Already up?
#---------------------------------------------------------------------------
if try_login "$file_pw"; then
  echo "mssql: already running"
  exit 0
fi
if [[ -n "$baked_pw" && "$baked_pw" != "$file_pw" ]] && try_login "$baked_pw"; then
  echo "mssql: already running (the container's password differs from $PWFILE — adopting it)"
  save_password "$baked_pw"
  exit 0
fi

#---------------------------------------------------------------------------
# Start it.
#---------------------------------------------------------------------------
# For an existing container, hand compose the value already baked into it so the
# config is unchanged and compose does not recreate it.
MSSQL_SA_PASSWORD="${baked_pw:-$file_pw}"
export MSSQL_SA_PASSWORD

echo "mssql: starting the ${SQL_HOST} service in compose project '${PROJECT}'..."
aidev_compose --profile mssql up -d mssql

dump_logs_and_die() {
  echo "$1" >&2
  aidev_compose --profile mssql logs --tail 40 mssql >&2 || true
  exit 1
}

# `up -d` returns once the container is *started*, not once it is alive. The two
# documented crash causes — a data volume owned by the pre-migration uid, and an
# empty MSSQL_SA_PASSWORD — both exit within seconds, so check liveness before
# blaming anything else.
cid="$(aidev_compose --profile mssql ps -aq mssql | head -n1)"
if [[ -z "$cid" ]] \
   || [[ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null)" != "true" ]]; then
  dump_logs_and_die "mssql: the container is not running — logs follow"
fi

if ! getent hosts "$SQL_HOST" >/dev/null 2>&1; then
  echo "error: '${SQL_HOST}' does not resolve from this container, although it is running." >&2
  echo "       The dev container and the mssql service must share a compose network." >&2
  echo "       This container's project is '${PROJECT}'; verify with:" >&2
  echo "         docker inspect -f '{{index .Config.Labels \"com.docker.compose.project\"}}' \"\$(hostname)\"" >&2
  dump_logs_and_die "mssql: logs follow"
fi

# A fresh data volume takes a while: the engine creates master/model/msdb.
export SQLCMDPASSWORD="$MSSQL_SA_PASSWORD"
if ! aidev_wait_until mssql 90 2 \
      "$SQLCMD" -S "${SQL_HOST},1433" -U sa -No -Q "SELECT 1"; then
  dump_logs_and_die "mssql: timed out waiting for the engine — logs follow"
fi
unset SQLCMDPASSWORD

[[ "$MSSQL_SA_PASSWORD" == "$file_pw" ]] || save_password "$MSSQL_SA_PASSWORD"
echo "mssql: ready. Connect with:"
echo "  SQLCMDPASSWORD=\"\$(cat $PWFILE)\" sqlcmd -S ${SQL_HOST},1433 -U sa -No"
