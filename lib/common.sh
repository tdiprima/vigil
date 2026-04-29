#!/usr/bin/env bash
# Shared utilities for Vigil security sweep

set -euo pipefail

VIGIL_SEVERITY_OK=0
VIGIL_SEVERITY_WARN=1
VIGIL_SEVERITY_CRIT=2

_vigil_config_loaded="${_vigil_config_loaded:-false}"

load_config() {
    if [[ "${_vigil_config_loaded}" == "true" ]]; then
        return 0
    fi

    local config_path="${1:-/opt/vigil/vigil.conf}"

    if [[ ! -f "${config_path}" ]]; then
        echo "ERROR: config not found: ${config_path}" >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    source "${config_path}"
    _vigil_config_loaded="true"

    mkdir -p "${DATA_DIR}" "${LOG_DIR}" "${BASELINE_DIR}" "${REPORT_DIR}"
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        case "${ID}" in
            rhel|centos|rocky|alma|fedora)
                echo "rhel"
                ;;
            ubuntu|debian)
                echo "debian"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
}

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

datestamp() {
    date '+%Y-%m-%d'
}

log_info() {
    echo "[$(timestamp)] [INFO] $*"
}

log_warn() {
    echo "[$(timestamp)] [WARN] $*"
}

log_error() {
    echo "[$(timestamp)] [ERROR] $*" >&2
}

report_finding() {
    local severity="${1}"
    local check_name="${2}"
    local message="${3}"

    local level="OK"
    case "${severity}" in
        "${VIGIL_SEVERITY_WARN}") level="WARN" ;;
        "${VIGIL_SEVERITY_CRIT}") level="CRIT" ;;
    esac

    echo "[${level}] [${check_name}] ${message}"
}

command_exists() {
    command -v "${1}" >/dev/null 2>&1
}
