#!/usr/bin/env bash
# Check and install system dependencies for Vigil security sweep

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Check and install dependencies required by Vigil.
Requires root for installation (dry-run works without).

Options:
    -h, --help      Show this help message
    -n, --dry-run   Show what would be installed without installing
    -c, --config    Path to vigil.conf (default: ${SCRIPT_DIR}/vigil.conf)
EOF
}

dry_run="false"
config_path="${SCRIPT_DIR}/vigil.conf"

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            print_usage
            exit 0
            ;;
        -n|--dry-run)
            dry_run="true"
            shift
            ;;
        -c|--config)
            config_path="${2}"
            shift 2
            ;;
        *)
            echo "Unknown option: ${1}" >&2
            print_usage
            exit 1
            ;;
    esac
done

os_family=$(detect_os)
missing_packages=()

log_info "Detected OS family: ${os_family}"
log_info "Checking dependencies..."

check_dep() {
    local cmd_name="${1}"
    local pkg_rhel="${2}"
    local pkg_debian="${3}"

    if command_exists "${cmd_name}"; then
        log_info "  [OK]      ${cmd_name}"
    else
        local pkg=""
        case "${os_family}" in
            rhel)   pkg="${pkg_rhel}" ;;
            debian) pkg="${pkg_debian}" ;;
        esac

        if [[ "${pkg}" == "-" ]]; then
            log_warn "  [SKIP]    ${cmd_name} — not available for ${os_family}"
        else
            log_warn "  [MISSING] ${cmd_name} — will install ${pkg}"
            missing_packages+=("${pkg}")
        fi
    fi
}

#              command      rhel-package    debian-package
check_dep      "rkhunter"   "rkhunter"      "rkhunter"
check_dep      "mailx"      "s-nail"        "mailutils"
check_dep      "openssl"    "openssl"       "openssl"
check_dep      "ss"         "iproute"       "iproute2"
check_dep      "diff"       "diffutils"     "diffutils"
check_dep      "find"       "findutils"     "findutils"

if [[ "${os_family}" == "debian" ]]; then
    check_dep  "debsums"    "-"             "debsums"
fi

echo ""

if [[ ${#missing_packages[@]} -eq 0 ]]; then
    log_info "All dependencies satisfied."
    echo ""

    if [[ -f "${config_path}" ]]; then
        log_info "Setting up data directories..."
        load_config "${config_path}"
        log_info "Directories ready: ${DATA_DIR}, ${LOG_DIR}"
    fi

    exit 0
fi

log_info "Missing packages: ${missing_packages[*]}"

if [[ "${dry_run}" == "true" ]]; then
    log_info "[DRY RUN] Would install: ${missing_packages[*]}"
    exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
    log_error "Root required to install packages. Re-run with sudo."
    exit 1
fi

case "${os_family}" in
    rhel)
        if command_exists dnf; then
            dnf install -y "${missing_packages[@]}"
        elif command_exists yum; then
            yum install -y "${missing_packages[@]}"
        else
            log_error "No package manager found (dnf/yum)"
            exit 1
        fi
        ;;
    debian)
        apt-get update -qq
        apt-get install -y "${missing_packages[@]}"
        ;;
    *)
        log_error "Unsupported OS. Install manually: ${missing_packages[*]}"
        exit 1
        ;;
esac

log_info "Dependencies installed."

if [[ -f "${config_path}" ]]; then
    log_info "Setting up data directories..."
    load_config "${config_path}"
    log_info "Directories ready: ${DATA_DIR}, ${LOG_DIR}"
fi
