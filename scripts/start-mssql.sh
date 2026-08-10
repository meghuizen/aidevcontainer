#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

aidev_must_be_in_container /opt/mssql/bin/sqlservr

PWFILE="${HOME}/.mssql-password"
DATA=/var/opt/mssql
SQLCMD=/opt/mssql-tools18/bin/sqlcmd

aidev_already_running mssql pgrep -f sqlservr && exit 0

# First-run setup: generate password + initialize SQL Server
if [[ ! -f "$DATA/data/master.mdf" ]]; then
  if [[ ! -f "$PWFILE" ]]; then
    umask 077
    # SQL Server requires upper, lower, digit, length >= 8. Append fixed suffix to guarantee complexity.
    pw="$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 22)Aa1!"
    printf '%s' "$pw" > "$PWFILE"
    chmod 600 "$PWFILE"
    echo "mssql: generated SA password at $PWFILE"
  fi

  sudo mkdir -p "$DATA/data" "$DATA/log" "$DATA/secrets"
  sudo chown -R mssql:mssql "$DATA"
  if [[ -f "$SCRIPT_DIR/../config/mssql.conf" ]]; then
    sudo install -m 0644 -o mssql -g mssql "$SCRIPT_DIR/../config/mssql.conf" "$DATA/mssql.conf"
  fi
  # `sudo -E` is unreliable: sudoers strip env vars unless explicitly preserved. Pass them inline.
  sudo MSSQL_SA_PASSWORD="$(cat "$PWFILE")" \
       ACCEPT_EULA=Y \
       MSSQL_PID=Developer \
       /opt/mssql/bin/mssql-conf -n setup
fi

echo "mssql: starting sqlservr..."
sudo -u mssql /opt/mssql/bin/sqlservr >/tmp/mssql.log 2>&1 &

aidev_wait_until mssql 60 2 \
  "$SQLCMD" -S localhost,1433 -U sa -P "$(cat "$PWFILE")" -No -Q "SELECT 1"
