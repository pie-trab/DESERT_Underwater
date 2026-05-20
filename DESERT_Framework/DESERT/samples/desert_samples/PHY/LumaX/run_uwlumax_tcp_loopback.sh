#!/usr/bin/env bash
set -euo pipefail

if ! command -v ns >/dev/null 2>&1; then
	echo "ERROR: ns not found. Source the DESERT environment first." >&2
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PORT="${1:-5555}"
START="${2:-5}"
STOP="${3:-60}"
TRAFFIC="${4:-5}"
PKTSIZE="${5:-16}"

echo "Starting LumaX TCP loopback receiver on 127.0.0.1:${PORT}"
ns test_uwlumax_application.tcl 2 1 "$START" "$STOP" 0 127.0.0.1 "$PORT" "$PKTSIZE" TCP 0 0 SERVER &
SERVER_PID=$!

cleanup() {
	if kill -0 "$SERVER_PID" >/dev/null 2>&1; then
		kill "$SERVER_PID" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

sleep 1

echo "Starting LumaX TCP loopback transmitter toward 127.0.0.1:${PORT}"
ns test_uwlumax_application.tcl 1 2 "$START" "$STOP" "$TRAFFIC" 127.0.0.1 "$PORT" "$PKTSIZE" TCP 0 0 CLIENT

wait "$SERVER_PID"
