#!/usr/bin/env bash
# Compare listening ports against known-good baseline

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIGIL_DIR="${VIGIL_DIR:-$(dirname "${SCRIPT_DIR}")}"

source "${VIGIL_DIR}/lib/common.sh"
load_config "${1:-${VIGIL_DIR}/vigil.conf}"

CHECK_NAME="listening-ports"
max_severity="${VIGIL_SEVERITY_OK}"

if ! command_exists ss; then
    report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "ss not found. Install iproute2."
    exit 1
fi

known_ports_file="${KNOWN_PORTS_FILE:-${DATA_DIR}/known-ports.txt}"

if [[ ! -f "${known_ports_file}" ]]; then
    report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "No known-ports file. Run vigil-baseline.sh first."
    exit 1
fi

current_ports=$(mktemp)
ss -tlnp | tail -n +2 | awk '{print $4}' | sort -u > "${current_ports}"

unknown_ports=$(diff "${known_ports_file}" "${current_ports}" | grep '^>' | sed 's/^> //' || true)
missing_ports=$(diff "${known_ports_file}" "${current_ports}" | grep '^<' | sed 's/^< //' || true)

if [[ -n "${unknown_ports}" ]]; then
    while IFS= read -r port_entry; do
        proc_info=$(ss -tlnp | grep "${port_entry}" | awk '{print $6}' | head -1)
        report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "Unknown listener: ${port_entry} ${proc_info}"
        max_severity="${VIGIL_SEVERITY_CRIT}"
    done <<< "${unknown_ports}"
fi

if [[ -n "${missing_ports}" ]]; then
    while IFS= read -r port_entry; do
        report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "Expected listener missing: ${port_entry}"
        if (( max_severity < VIGIL_SEVERITY_WARN )); then
            max_severity="${VIGIL_SEVERITY_WARN}"
        fi
    done <<< "${missing_ports}"
fi

if (( max_severity == VIGIL_SEVERITY_OK )); then
    report_finding "${VIGIL_SEVERITY_OK}" "${CHECK_NAME}" "All listening ports match known-good list."
fi

rm -f "${current_ports}"
exit "${max_severity}"
