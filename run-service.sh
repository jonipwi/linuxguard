#!/usr/bin/env bash
# run-service.sh - linuxguard-go service runner (Linux / macOS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
BINARY="$BIN_DIR/linuxguard"
PID_FILE="$SCRIPT_DIR/linuxguard.pid"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/linuxguard.log"
ERR_LOG_FILE="$LOG_DIR/linuxguard.err.log"
CONFIG_PATH="configs/config.yaml"

cyan()  { printf "\033[36m[linuxguard-go] %s\033[0m\n" "$*"; }
green() { printf "\033[32m[linuxguard-go] %s\033[0m\n" "$*"; }
red()   { printf "\033[31m[linuxguard-go] %s\033[0m\n" "$*"; }

resolve_config_path() {
    if [[ "$CONFIG_PATH" = /* ]]; then
        printf '%s\n' "$CONFIG_PATH"
    else
        printf '%s\n' "$SCRIPT_DIR/$CONFIG_PATH"
    fi
}

dashboard_addr() {
    local resolved_config="$1"
    local value
    value="$(sed -n 's/^[[:space:]]*dashboard_addr[[:space:]]*:[[:space:]]*//p' "$resolved_config" | head -n 1 | tr -d '"')"
    if [[ -z "$value" ]]; then
        value="127.0.0.1:8765"
    fi
    printf '%s\n' "$value"
}

do_build() {
    cyan "Building linuxguard ..."
    cd "$SCRIPT_DIR"
    mkdir -p "$BIN_DIR" "$SCRIPT_DIR/tmp"
    GOTMPDIR="$SCRIPT_DIR/tmp" go build -o "$BINARY" ./cmd/linuxguard
    green "Build successful -> $BINARY"
}

do_start() {
    local resolved_config ui_addr existing_pid
    resolved_config="$(resolve_config_path)"

    if [[ ! -f "$BINARY" ]]; then
        red "Binary not found: $BINARY  (run with -build first)"
        exit 1
    fi

    if [[ ! -f "$resolved_config" ]]; then
        red "Config not found: $resolved_config"
        exit 1
    fi

    if [[ -f "$PID_FILE" ]]; then
        existing_pid="$(cat "$PID_FILE")"
        if kill -0 "$existing_pid" 2>/dev/null; then
            red "linuxguard-go is already running (PID $existing_pid). Use -stop first."
            exit 1
        fi
        rm -f "$PID_FILE"
    fi

    mkdir -p "$LOG_DIR"
    ui_addr="$(dashboard_addr "$resolved_config")"

    cyan "Starting linuxguard-go ..."
    cyan "  config   = $resolved_config"
    cyan "  log      = $LOG_FILE"
    cyan "  err-log  = $ERR_LOG_FILE"
    cyan "  ui       = http://$ui_addr/"

    nohup "$BINARY" serve --config "$resolved_config" >> "$LOG_FILE" 2>> "$ERR_LOG_FILE" &
    echo $! > "$PID_FILE"
    green "linuxguard-go started (PID $!)"
}

do_stop() {
    local pid i
    if [[ ! -f "$PID_FILE" ]]; then
        red "PID file not found - linuxguard-go may not be running."
        exit 1
    fi

    pid="$(cat "$PID_FILE")"
    if ! kill -0 "$pid" 2>/dev/null; then
        red "Process PID $pid not found - cleaning up stale PID file."
        rm -f "$PID_FILE"
        exit 1
    fi

    cyan "Stopping linuxguard-go (PID $pid) ..."
    kill -TERM "$pid"

    i=0
    while kill -0 "$pid" 2>/dev/null && (( i < 50 )); do
        sleep 0.1
        ((i++)) || true
    done

    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
    fi

    rm -f "$PID_FILE"
    green "linuxguard-go stopped."
}

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [-build] [-start] [-stop] [-config path]"
    echo "  -build    Compile the linuxguard binary"
    echo "  -start    Start the server in the background"
    echo "  -stop     Stop a running server"
    echo "  -config   Path to configs/config.yaml"
    exit 0
fi

DO_BUILD=false
DO_START=false
DO_STOP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -build) DO_BUILD=true ; shift ;;
        -start) DO_START=true ; shift ;;
        -stop) DO_STOP=true ; shift ;;
        -config)
            shift
            if [[ $# -eq 0 ]]; then
                echo "Missing value for -config"
                exit 1
            fi
            CONFIG_PATH="$1"
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

$DO_BUILD && do_build
$DO_START && do_start
$DO_STOP && do_stop