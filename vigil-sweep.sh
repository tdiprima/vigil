#!/usr/bin/env bash
# Vigil — Daily Security Sweep Orchestrator
# Runs all checks, sends critical alerts immediately, then daily digest

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/alert.sh"

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Run all Vigil security checks and email results.

Options:
    -h, --help       Show this help message
    -c, --config     Path to vigil.conf (default: ${SCRIPT_DIR}/vigil.conf)
    -q, --quiet      Suppress stdout output (still sends email)
    -n, --no-email   Run checks but don't send email
EOF
}

config_path="${SCRIPT_DIR}/vigil.conf"
quiet="false"
send_mail="true"

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
        -q|--quiet)
            quiet="true"
            shift
            ;;
        -n|--no-email)
            send_mail="false"
            shift
            ;;
        *)
            echo "Unknown option: ${1}" >&2
            print_usage
            exit 1
            ;;
    esac
done

load_config "${config_path}"

hostname_short="$(hostname -s 2>/dev/null || hostname)"
report_file="${REPORT_DIR}/report-$(datestamp).txt"
has_critical="false"
summary_ok=0
summary_warn=0
summary_crit=0

CHECKS=(
    "baseline-drift:Baseline Drift"
    "rootkit-scan:Rootkit Scan"
    "package-integrity:Package Integrity"
    "cert-expiry:Certificate Expiry"
    "listening-ports:Listening Ports"
    "failed-auth:Failed Auth"
    "disk-usage:Disk Usage"
)

declare -a check_output_files=()
declare -a check_exit_codes=()

# ─── Run All Checks ─────────────────────────────────────
for idx in "${!CHECKS[@]}"; do
    entry="${CHECKS[${idx}]}"
    check="${entry%%:*}"
    label="${entry#*:}"
    check_script="${SCRIPT_DIR}/checks/${check}.sh"

    output_file=$(mktemp)
    check_exit=0

    if [[ ! -x "${check_script}" ]]; then
        echo "[WARN] [${check}] Check script not found or not executable" > "${output_file}"
        check_exit=1
    else
        "${check_script}" "${config_path}" > "${output_file}" 2>&1 || check_exit=$?
    fi

    check_output_files+=("${output_file}")
    check_exit_codes+=("${check_exit}")

    case "${check_exit}" in
        0) summary_ok=$((summary_ok + 1)) ;;
        1) summary_warn=$((summary_warn + 1)) ;;
        *)
            summary_crit=$((summary_crit + 1))
            has_critical="true"

            # Critical alert sent immediately per check, not batched
            if [[ "${send_mail}" == "true" ]]; then
                alert_body=$(mktemp)
                {
                    echo "CRITICAL finding during Vigil sweep on ${hostname_short}"
                    echo "Check: ${label}"
                    echo "Time:  $(timestamp)"
                    echo ""
                    cat "${output_file}"
                } > "${alert_body}"
                send_critical_alert "${alert_body}" || log_error "Failed to send critical alert for ${label}"
                rm -f "${alert_body}"
            fi
            ;;
    esac
done

# ─── Build Report ───────────────────────────────────────
{
    echo "======================================================="
    echo "  VIGIL Security Sweep — ${hostname_short} — $(datestamp)"
    echo "======================================================="
    echo ""
    echo "Summary: ${summary_crit} critical, ${summary_warn} warnings, ${summary_ok} clean"
    echo ""

    for idx in "${!CHECKS[@]}"; do
        entry="${CHECKS[${idx}]}"
        label="${entry#*:}"

        echo "--- ${label} -------------------------------------------"
        cat "${check_output_files[${idx}]}"
        echo ""
    done

    echo "======================================================="
    echo "  End of Report — $(timestamp)"
    echo "======================================================="
} > "${report_file}"

# ─── Cleanup Temp Files ─────────────────────────────────
for output_file in "${check_output_files[@]}"; do
    rm -f "${output_file}"
done

# ─── Output ─────────────────────────────────────────────
if [[ "${quiet}" != "true" ]]; then
    cat "${report_file}"
fi

# ─── Send Daily Digest ──────────────────────────────────
if [[ "${send_mail}" == "true" ]]; then
    log_info "Sending daily digest..."
    send_digest "${report_file}" || log_error "Failed to send digest email"
fi

# ─── Log ────────────────────────────────────────────────
log_file="${LOG_DIR}/vigil-$(datestamp).log"
echo "[$(timestamp)] Sweep complete. ${summary_crit} critical, ${summary_warn} warnings, ${summary_ok} clean" >> "${log_file}"

if [[ "${has_critical}" == "true" ]]; then
    exit 2
elif (( summary_warn > 0 )); then
    exit 1
fi
exit 0
