#!/usr/bin/env bash
# Create baseline snapshots for Vigil drift detection
# Run once after initial setup, then again after intentional system changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Create baseline snapshots of system state for drift detection.
Requires root. Run after initial setup or intentional system changes.

Captures: users, cron jobs, SUID binaries, listening ports.

Options:
    -h, --help       Show this help message
    -c, --config     Path to vigil.conf (default: ${SCRIPT_DIR}/vigil.conf)
EOF
}

config_path="${SCRIPT_DIR}/vigil.conf"

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            print_usage
            exit 0
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

load_config "${config_path}"

log_info "Creating baseline snapshots in ${BASELINE_DIR}"

# ─── Users ────────────────────────────────────────────────
log_info "Snapshotting users..."
cut -d: -f1,3,6,7 /etc/passwd > "${BASELINE_DIR}/users.baseline"

# ─── Cron Jobs ────────────────────────────────────────────
log_info "Snapshotting cron jobs..."
{
    for crontab_file in /etc/crontab /etc/cron.d/*; do
        if [[ -f "${crontab_file}" ]]; then
            echo "=== ${crontab_file} ==="
            grep -v '^#' "${crontab_file}" | grep -v '^[[:space:]]*$' || true
        fi
    done
    for user_crontab in /var/spool/cron/crontabs/* /var/spool/cron/*; do
        if [[ -f "${user_crontab}" ]]; then
            echo "=== ${user_crontab} ==="
            grep -v '^#' "${user_crontab}" | grep -v '^[[:space:]]*$' || true
        fi
    done
} > "${BASELINE_DIR}/cron.baseline" 2>/dev/null

# ─── SUID Files ──────────────────────────────────────────
log_info "Snapshotting SUID files (may take a moment)..."
find / -perm -4000 -type f 2>/dev/null | sort > "${BASELINE_DIR}/suid.baseline"

# ─── Listening Ports ─────────────────────────────────────
log_info "Snapshotting listening ports as known-good..."
ss -tlnp | tail -n +2 | awk '{print $4}' | sort -u > "${DATA_DIR}/known-ports.txt"

log_info "Baselines created:"
ls -la "${BASELINE_DIR}/"
log_info "Known ports: ${DATA_DIR}/known-ports.txt"
log_info "Review known-ports.txt and remove any ports that should trigger alerts."
