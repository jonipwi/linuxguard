#!/usr/bin/env bash
# one-secure-setup.sh - install LinuxGuard-Go as a Linux systemd service.

set -euo pipefail

APP_NAME="linuxguard-go"
DISPLAY_NAME="LinuxGuard-Go"
SERVICE_NAME="${APP_NAME}.service"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/go.mod" && -d "${SCRIPT_DIR}/cmd/linuxguard" ]]; then
    SOURCE_DIR="${SCRIPT_DIR}"
elif [[ -f "${SCRIPT_DIR}/linuxguard-go/go.mod" && -d "${SCRIPT_DIR}/linuxguard-go/cmd/linuxguard" ]]; then
    SOURCE_DIR="${SCRIPT_DIR}/linuxguard-go"
else
    SOURCE_DIR="${SCRIPT_DIR}/linuxguard-go"
fi
INSTALL_DIR="/opt/${APP_NAME}"
CONFIG_DIR="/etc/${APP_NAME}"
DATA_DIR="/var/lib/${APP_NAME}"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
BINARY_PATH="${INSTALL_DIR}/bin/linuxguard"
UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}"

info() { printf '[one-secure] %s\n' "$*"; }
warn() { printf '[one-secure] warning: %s\n' "$*" >&2; }
die()  { printf '[one-secure] error: %s\n' "$*" >&2; exit 1; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "run this script as root, for example: sudo ./one-secure-setup.sh"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

copy_source() {
    [[ -d "${SOURCE_DIR}" ]] || die "LinuxGuard-Go source not found at ${SOURCE_DIR}"

    info "Installing source to ${INSTALL_DIR}"
    install -d -m 0755 "${INSTALL_DIR}"

    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete \
            --exclude '.git' \
            --exclude 'bin' \
            --exclude 'tmp' \
            --exclude 'logs' \
            "${SOURCE_DIR}/" "${INSTALL_DIR}/"
    else
        rm -rf "${INSTALL_DIR:?}/cmd" "${INSTALL_DIR:?}/configs" "${INSTALL_DIR:?}/internal"
        cp -R "${SOURCE_DIR}/." "${INSTALL_DIR}/"
        rm -rf "${INSTALL_DIR}/bin" "${INSTALL_DIR}/tmp" "${INSTALL_DIR}/logs"
    fi
}

stop_local_runner() {
    local pid_file="${SOURCE_DIR}/linuxguard.pid"
    local pid

    if [[ ! -f "${pid_file}" ]]; then
        return
    fi

    pid="$(cat "${pid_file}" 2>/dev/null || true)"
    if [[ -z "${pid}" || ! "${pid}" =~ ^[0-9]+$ ]]; then
        rm -f "${pid_file}"
        return
    fi

    if kill -0 "${pid}" 2>/dev/null; then
        info "Stopping existing run-service.sh LinuxGuard-Go process PID ${pid}"
        kill -TERM "${pid}" 2>/dev/null || true
        sleep 1
        if kill -0 "${pid}" 2>/dev/null; then
            kill -KILL "${pid}" 2>/dev/null || true
        fi
    fi
    rm -f "${pid_file}"
}

install_config() {
    info "Preparing config and data directories"
    install -d -m 0755 "${CONFIG_DIR}" "${DATA_DIR}"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        [[ -f "${INSTALL_DIR}/configs/config.example.yaml" ]] || die "config template missing: ${INSTALL_DIR}/configs/config.example.yaml"
        install -m 0644 "${INSTALL_DIR}/configs/config.example.yaml" "${CONFIG_FILE}"
    else
        info "Keeping existing config at ${CONFIG_FILE}"
    fi

    if grep -q 'path: data/linuxguard.db' "${CONFIG_FILE}"; then
        sed -i "s#path: data/linuxguard.db#path: ${DATA_DIR}/linuxguard.db#g" "${CONFIG_FILE}"
    fi
}

build_binary() {
    info "Building ${DISPLAY_NAME}"
    install -d -m 0755 "${INSTALL_DIR}/bin" "${INSTALL_DIR}/tmp"
    (
        cd "${INSTALL_DIR}"
        GOTMPDIR="${INSTALL_DIR}/tmp" go build -o "${BINARY_PATH}" ./cmd/linuxguard
    )
    [[ -x "${BINARY_PATH}" ]] || die "build did not create executable binary: ${BINARY_PATH}"
    chmod 0755 "${BINARY_PATH}"
}

install_linuxguard_service() {
    info "Writing systemd unit ${UNIT_FILE}"
    cat > "${UNIT_FILE}" <<EOF
[Unit]
Description=${DISPLAY_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BINARY_PATH} serve --config ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
NoNewPrivileges=false
ReadWritePaths=${CONFIG_DIR} ${DATA_DIR} ${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}"
}

postflight() {
    info "Service status:"
    systemctl --no-pager --full status "${SERVICE_NAME}" || true

    warn_if_missing iptables "IPv4 firewall enforcement may fail"
    warn_if_missing ip6tables "IPv6 firewall enforcement may fail"
    warn_if_missing ss "outbound scanning will fall back to netstat if available"
    warn_if_missing journalctl "SSH brute-force detection requires systemd journal access"

    info "${DISPLAY_NAME} dashboard: http://127.0.0.1:8765"
}

warn_if_missing() {
    local cmd="$1"
    local message="$2"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        warn "${cmd} not found; ${message}"
    fi
}

main() {
    require_root
    require_command go
    require_command systemctl
    require_command sed

    stop_local_runner
    copy_source
    install_config
    build_binary
    install_linuxguard_service
    postflight
}

main "$@"
