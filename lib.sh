#!/usr/bin/env bash
# Shared utilities for mini-tunnel scripts.
# Source this file from other scripts in the same directory.

# --- DNS / TCP port helpers ---

# Check whether a TCP port is in LISTEN state on 127.0.0.1.
is_port_in_use() {
  local port=$1
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH "sport = :$port" 2>/dev/null | grep -q . && return 0
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN -n -P 2>/dev/null | grep -q . && return 0
  fi
  return 1
}

# Get the PID of the process listening on a TCP port (127.0.0.1).
# Echoes the PID, or empty string if not found.
get_port_owner_pid() {
  local port=$1
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "sport = :$port" 2>/dev/null | grep -oP 'pid=\K\d+' | head -1 || true
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN -t -n -P 2>/dev/null || true
  fi
}

# Wait until a port is free (not in LISTEN).
# Returns 0 when free, 1 on timeout.
wait_for_port_free() {
  local port=$1 timeout=${2:-10}
  local waited=0
  while is_port_in_use "$port"; do
    if [ "$waited" -ge "$timeout" ]; then
      echo "Timeout waiting for port $port to be free"
      return 1
    fi
    sleep 0.5
    waited=$((waited + 1))
  done
  return 0
}

# Wait until a port is open (in LISTEN).
# Returns 0 when open, 1 on timeout.
wait_for_port() {
  local port=$1 name=$2 max=${3:-30}
  local i=0
  while ! (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge "$max" ]; then
      echo "Timeout waiting for $name on port $port"
      return 1
    fi
    sleep 1
  done
  echo "$name ready on port $port"
}

# --- openchamber state management ---

# Get the openchamber data directory.
# openchamber uses ~/.config/openchamber (Linux) by default,
# overrideable via $OPENCHAMBER_DATA_DIR.
get_openchamber_data_dir() {
  if [ -n "${OPENCHAMBER_DATA_DIR:-}" ]; then
    echo "$OPENCHAMBER_DATA_DIR"
  else
    echo "$HOME/.config/openchamber"
  fi
}

# Get the openchamber run directory (holds PID and instance JSON files).
get_openchamber_run_dir() {
  echo "$(get_openchamber_data_dir)/run"
}

# Clean up openchamber's own PID and instance files for a given port.
# openchamber's CLI checks these on startup to decide if it's "already running".
clean_openchamber_stale_state() {
  local port=$1
  local run_dir
  run_dir=$(get_openchamber_run_dir)
  if [ -d "$run_dir" ]; then
    rm -f "$run_dir/openchamber-$port.pid" "$run_dir/openchamber-$port.json" 2>/dev/null || true
  fi
}

# Clean all openchamber stale state files (all ports).
clean_all_openchamber_stale_state() {
  local run_dir
  run_dir=$(get_openchamber_run_dir)
  if [ -d "$run_dir" ]; then
    rm -f "$run_dir/openchamber-"*.pid "$run_dir/openchamber-"*.json 2>/dev/null || true
  fi
}

# --- Process helpers ---

# Check whether a PID is alive.
is_process_alive() {
  local pid=$1
  kill -0 "$pid" 2>/dev/null
}

# Kill a process gracefully (SIGTERM), wait for it to die, then force-kill.
# Args: pid [grace_period_s=5] [force_timeout_s=5]
kill_and_wait() {
  local pid=$1 grace=${2:-5} force=${3:-5}

  if ! is_process_alive "$pid"; then
    return 0
  fi

  kill "$pid" 2>/dev/null || true

  local waited=0
  while is_process_alive "$pid" && [ "$waited" -lt "$grace" ]; do
    sleep 0.5
    waited=$((waited + 1))
  done

  if is_process_alive "$pid"; then
    echo "Process $pid did not die after SIGTERM, sending SIGKILL..."
    kill -9 "$pid" 2>/dev/null || true
    waited=0
    while is_process_alive "$pid" && [ "$waited" -lt "$force" ]; do
      sleep 0.5
      waited=$((waited + 1))
    done
  fi

  if is_process_alive "$pid"; then
    echo "Warning: process $pid still alive after SIGKILL"
    return 1
  fi
  return 0
}
