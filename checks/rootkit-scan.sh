#!/usr/bin/env bash
# Run rkhunter rootkit scan and report warnings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIGIL_DIR="${VIGIL_DIR:-$(dirname "${SCRIPT_DIR}")}"

source "${VIGIL_DIR}/lib/common.sh"
load_config "${1:-${VIGIL_DIR}/vigil.conf}"

CHECK_NAME="rootkit-scan"

if ! command_exists rkhunter; then
    report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "rkhunter not installed. Run install-deps.sh."
    exit 1
fi

rkhunter --update --nocolors 2>/dev/null || true

scan_output=$(mktemp)
rkhunter --check --skip-keypress --nocolors --report-warnings-only > "${scan_output}" 2>&1 || true

warning_count=$(grep -c "Warning:" "${scan_output}" 2>/dev/null || true)

if (( warning_count > 0 )); then
    report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "${warning_count} warning(s) from rkhunter:"
    grep "Warning:" "${scan_output}" | while IFS= read -r line; do
        report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "  ${line}"
    done
    rm -f "${scan_output}"
    exit "${VIGIL_SEVERITY_CRIT}"
fi

report_finding "${VIGIL_SEVERITY_OK}" "${CHECK_NAME}" "No rootkits or suspicious files detected."
rm -f "${scan_output}"
exit "${VIGIL_SEVERITY_OK}"
