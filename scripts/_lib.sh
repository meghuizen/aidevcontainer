# Shared helpers for ai-dev service-start scripts. Source, don't execute.
# Intentionally no shebang — this file is sourced.

# aidev_must_be_in_container <sentinel-path>
# Aborts with a clear message if the sentinel binary/file is missing on the host.
aidev_must_be_in_container() {
  local sentinel="$1"
  if [[ ! -e "$sentinel" ]]; then
    echo "error: this script must run inside the ai-dev container (missing $sentinel)" >&2
    exit 2
  fi
}

# aidev_wait_until <name> <max-attempts> <sleep-secs> <probe-cmd...>
# Returns 0 on first success, prints log tail on timeout.
aidev_wait_until() {
  local name="$1" max="$2" gap="$3"; shift 3
  local i
  for (( i=1; i<=max; i++ )); do
    if "$@" >/dev/null 2>&1; then
      echo "$name: ready"
      return 0
    fi
    sleep "$gap"
  done
  echo "$name: timed out after $((max*gap))s" >&2
  if [[ -f "/tmp/${name}.log" ]]; then
    tail -n 40 "/tmp/${name}.log" >&2 || true
  fi
  return 1
}

# aidev_already_running <name> <probe-cmd...>
# Echoes "already running" and returns 0 if probe succeeds.
aidev_already_running() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "$name: already running"
    return 0
  fi
  return 1
}

# aidev_compose_project
# Echoes the compose project this container belongs to. Prefers the container's
# own label over assuming the compose file's `name:`, because devcontainer
# tooling may create the stack under a different project — and a mismatched
# project means a different network and a different (empty) data volume.
# Memoized: each compose call would otherwise pay a `docker inspect` round trip.
AIDEV_COMPOSE_PROJECT=""
aidev_compose_project() {
  if [[ -z "$AIDEV_COMPOSE_PROJECT" ]]; then
    AIDEV_COMPOSE_PROJECT="$(docker inspect \
        -f '{{index .Config.Labels "com.docker.compose.project"}}' \
        "$(hostname)" 2>/dev/null || true)"
    : "${AIDEV_COMPOSE_PROJECT:=aidev}"
  fi
  printf '%s' "$AIDEV_COMPOSE_PROJECT"
}

# aidev_compose <args...>
# Runs docker compose against this repo's compose file in the right project.
# Single definition so start-mssql.sh and stop-all.sh cannot drift apart.
aidev_compose() {
  local dir="${AIDEV_SCRIPT_DIR:?aidev_compose: set AIDEV_SCRIPT_DIR first}"
  docker compose -p "$(aidev_compose_project)" \
                 -f "$dir/../.devcontainer/docker-compose.yml" "$@"
}
