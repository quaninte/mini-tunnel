#!/usr/bin/env bash
# opencode + openchamber stack: native background processes with pidfiles in tmp/.
# Sourced by start.sh/stop.sh/status.sh — expects lib.sh already sourced and
# DIR/OPENCODE_PORT/OPENCHAMBER_PORT/PASS_KEY/FORCE already set by the caller.

# --- Pre-flight: ensure port is free (shared by both services in this stack) ---
_code_stack_ensure_port_free() {
  local port=$1 name=$2
  if ! is_port_in_use "$port"; then
    return 0
  fi

  local owner_pid
  owner_pid=$(get_port_owner_pid "$port")

  # If we have a pidfile for this service and the PID matches, it's already our process.
  if [ -n "${owner_pid:-}" ] && [ -f "$DIR/tmp/$name.pid" ]; then
    local our_pid
    our_pid=$(cat "$DIR/tmp/$name.pid" 2>/dev/null || true)
    if [ "$owner_pid" = "$our_pid" ]; then
      echo "$name already running on port $port (PID $our_pid)"
      return 2 # 2 = already running (skip)
    fi
  fi

  if [ "${FORCE:-false}" = true ]; then
    echo "Port $port is in use (PID ${owner_pid:-unknown}). Forcing..."
    if [ -n "${owner_pid:-}" ]; then
      kill_and_wait "$owner_pid" 5 3
    fi
    clean_openchamber_stale_state "$port"
    wait_for_port_free "$port" 10 || {
      echo "Error: port $port is still occupied. Cannot start $name."
      exit 1
    }
    return 0
  fi

  echo "Error: port $port is already in use by another process (PID ${owner_pid:-unknown})."
  echo "  Run '$DIR/restart.sh' to stop, clean up, and restart everything,"
  echo "  or '$DIR/start.sh --force' to kill the occupant and restart."
  exit 1
}

start_code_stack() {
  # --- opencode serve ---
  local opencode_skip=false opencode_result=0
  _code_stack_ensure_port_free "$OPENCODE_PORT" "opencode" || opencode_result=$?
  if [ "$opencode_result" -eq 2 ]; then
    opencode_skip=true
  fi
  if [ "$opencode_skip" = false ]; then
    echo "Starting opencode serve..."
    opencode serve --port "$OPENCODE_PORT" --hostname 127.0.0.1 >"$DIR/opencode.log" 2>&1 &
    OPENCODE_PID=$!
    echo "$OPENCODE_PID" >"$DIR/tmp/opencode.pid"
    wait_for_port "$OPENCODE_PORT" "opencode" 15
  fi

  # --- openchamber ---
  # Clean stale openchamber state BEFORE starting so its own CLI doesn't
  # see a stale pidfile and refuse to start ("already running on port X").
  clean_openchamber_stale_state "$OPENCHAMBER_PORT"

  local openchamber_skip=false openchamber_result=0
  _code_stack_ensure_port_free "$OPENCHAMBER_PORT" "openchamber" || openchamber_result=$?
  if [ "$openchamber_result" -eq 2 ]; then
    openchamber_skip=true
  fi
  if [ "$openchamber_skip" = false ]; then
    echo "Starting openchamber..."
    OPENCODE_HOST="http://127.0.0.1:$OPENCODE_PORT" \
      openchamber serve \
      --port "$OPENCHAMBER_PORT" \
      --host 127.0.0.1 \
      --ui-password "$PASS_KEY" \
      --foreground >"$DIR/openchamber.log" 2>&1 &
    OPENCHAMBER_PID=$!
    echo "$OPENCHAMBER_PID" >"$DIR/tmp/openchamber.pid"
    wait_for_port "$OPENCHAMBER_PORT" "openchamber" 15
  fi

  echo "  opencode:     http://127.0.0.1:$OPENCODE_PORT (PID ${OPENCODE_PID:-already running})"
  echo "  openchamber:  http://127.0.0.1:$OPENCHAMBER_PORT (PID ${OPENCHAMBER_PID:-already running})"
}

stop_code_stack() {
  _code_stack_kill_pid() {
    local name=$1
    local pidfile="$DIR/tmp/$2.pid"
    local port=$3
    if [ -f "$pidfile" ]; then
      local pid
      pid=$(cat "$pidfile")
      if is_process_alive "$pid"; then
        kill_and_wait "$pid" 5 3
        echo "Stopped $name (PID $pid)"
      else
        echo "$name (PID $pid) not running"
      fi
      rm -f "$pidfile"
    else
      echo "$name: no pidfile found"
    fi

    # If the port is still occupied (by a process our pidfile didn't know about),
    # kill whoever is on it.
    if [ -n "${port:-}" ] && is_port_in_use "$port"; then
      echo "$name: port $port still occupied by another process, killing it..."
      kill_port_occupant "$port"
    fi
  }

  _code_stack_kill_pid "openchamber" "openchamber" "${OPENCHAMBER_PORT:-3000}"
  _code_stack_kill_pid "opencode" "opencode" "${OPENCODE_PORT:-4096}"

  # Clean openchamber's own stale state files so future starts are clean
  clean_openchamber_stale_state "${OPENCHAMBER_PORT:-3000}"
}

status_code_stack() {
  _code_stack_check_service() {
    local name=$1 port=$2 pidfile="$DIR/tmp/$3.pid"
    local status="not started"

    if [ -f "$pidfile" ]; then
      local pid
      pid=$(cat "$pidfile")
      if is_process_alive "$pid"; then
        status="running (PID $pid)"
      else
        status="not running (stale pidfile)"
      fi
    fi

    if is_port_in_use "$port"; then
      status="$status, port $port occupied"
    else
      status="$status, port $port free"
    fi

    echo "$name: $status"
  }

  _code_stack_check_service "opencode" "${OPENCODE_PORT:-4096}" "opencode"
  _code_stack_check_service "openchamber" "${OPENCHAMBER_PORT:-3000}" "openchamber"
}
