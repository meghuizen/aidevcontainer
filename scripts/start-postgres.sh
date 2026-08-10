#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

PG_VER=18
PG_BIN=/usr/lib/postgresql/${PG_VER}/bin
PG_DATA=/var/lib/postgresql/${PG_VER}/main
PG_CONF_SRC="$SCRIPT_DIR/../config"

aidev_must_be_in_container "$PG_BIN/postgres"
aidev_already_running postgres pg_isready -h 127.0.0.1 -p 5432 -q && exit 0

if [[ ! -s "$PG_DATA/PG_VERSION" ]]; then
  echo "postgres: initializing cluster..."
  sudo mkdir -p "$PG_DATA"
  sudo chown -R postgres:postgres "$PG_DATA"
  sudo -u postgres "$PG_BIN/initdb" -D "$PG_DATA" --locale=en_US.UTF-8 --encoding=UTF8

  sudo install -m 0640 -o postgres -g postgres "$PG_CONF_SRC/postgresql.conf" "$PG_DATA/postgresql.conf"
  sudo install -m 0640 -o postgres -g postgres "$PG_CONF_SRC/pg_hba.conf"     "$PG_DATA/pg_hba.conf"
fi

echo "postgres: starting..."
sudo -u postgres "$PG_BIN/pg_ctl" \
  -D "$PG_DATA" \
  -l /tmp/postgres.log \
  -o "-c config_file=$PG_DATA/postgresql.conf" \
  start

aidev_wait_until postgres 30 1 pg_isready -h 127.0.0.1 -p 5432 -q
