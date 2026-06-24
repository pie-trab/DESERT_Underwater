#!/bin/bash
#
# Localhost smoke test for the LumaX sample.
# Starts a receiver and a sender on 127.0.0.1 using the same TCL script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TCL_SCRIPT="$SCRIPT_DIR/test_uwlumax_multicast.tcl"
NS_CMD="${NS_CMD:-ns}"
MODEM_IP="${1:-127.0.0.1}"
MODEM_PORT="${2:-9200}"
SERVER_APP_PORT="${3:-22223}"
CLIENT_APP_PORT="${4:-22224}"
START_TIME="${5:-1}"
STOP_TIME="${6:-100}"
TRAFFIC_PERIOD="${7:-60}"
SERVER_NODE_ID="${8:-2}"
CLIENT_NODE_ID="${9:-1}"
SERVER_RNGSTREAM="${10:-1}"
CLIENT_RNGSTREAM="${11:-2}"

if ! command -v "$NS_CMD" >/dev/null 2>&1; then
	echo "Error: '$NS_CMD' not found in PATH."
	exit 1
fi

if ! command -v nc >/dev/null 2>&1; then
	echo "Error: 'nc' not found in PATH."
	exit 1
fi

if [[ ! -f "$TCL_SCRIPT" ]]; then
	echo "Error: TCL script not found at $TCL_SCRIPT"
	exit 1
fi

SERVER_LOG="$SCRIPT_DIR/uwlumax_localhost_server.log"
CLIENT_LOG="$SCRIPT_DIR/uwlumax_localhost_client.log"
MODEM_LOG="$SCRIPT_DIR/uwlumax_localhost_modem.log"

rm -f "$SERVER_LOG" "$CLIENT_LOG" "$MODEM_LOG"

nc -lk "$MODEM_IP" "$MODEM_PORT" > "$MODEM_LOG" 2>&1 &
MODEM_PID=$!

for _ in $(seq 1 20); do
	if nc -z "$MODEM_IP" "$MODEM_PORT" >/dev/null 2>&1; then
		break
	fi
	sleep 0.1
done

"$NS_CMD" "$TCL_SCRIPT" \
	"$SERVER_NODE_ID" \
	"$CLIENT_NODE_ID" \
	"$START_TIME" \
	"$STOP_TIME" \
	0 \
	"$MODEM_IP" \
	"$MODEM_PORT" \
	"$SERVER_APP_PORT" \
	"$SERVER_RNGSTREAM" \
	> "$SERVER_LOG" 2>&1 &
SERVER_PID=$!

"$NS_CMD" "$TCL_SCRIPT" \
	"$CLIENT_NODE_ID" \
	"$SERVER_NODE_ID" \
	"$START_TIME" \
	"$STOP_TIME" \
	"$TRAFFIC_PERIOD" \
	"$MODEM_IP" \
	"$MODEM_PORT" \
	"$CLIENT_APP_PORT" \
	"$CLIENT_RNGSTREAM" \
	> "$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!

cleanup() {
	kill "$SERVER_PID" "$CLIENT_PID" "$MODEM_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

wait "$SERVER_PID"
wait "$CLIENT_PID"

echo "Server log: $SERVER_LOG"
echo "Client log: $CLIENT_LOG"
