#!/usr/bin/env bash
# Verify package file integrity via rpm -Va or debsums

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIGIL_DIR="${VIGIL_DIR:-$(dirname "${SCRIPT_DIR}")}"

source "${VIGIL_DIR}/lib/common.sh"
load_config "${1:-${VIGIL_DIR}/vigil.conf}"

CHECK_NAME="package-integrity"
os_family=$(detect_os)
max_severity="${VIGIL_SEVERITY_OK}"

case "${os_family}" in
    rhel)
        # rpm -Va output: SM5DLUGTP flags then path
        # S=size M=mode 5=md5 D=device L=link U=user G=group T=time P=caps
        modified_files=$(rpm -Va 2>/dev/null | grep -v '^$' | grep -v 'missing' || true)

        if [[ -n "${modified_files}" ]]; then
            # Binary modifications (checksum changed, not under /etc/)
            critical_mods=$(echo "${modified_files}" | grep -E '^..5' | grep -v '/etc/' || true)
            config_mods=$(echo "${modified_files}" | grep -E '^..5' | grep '/etc/' || true)

            if [[ -n "${critical_mods}" ]]; then
                count=$(echo "${critical_mods}" | wc -l | tr -d ' ')
                report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "${count} binary file(s) with checksum mismatch:"
                echo "${critical_mods}" | head -20 | while IFS= read -r line; do
                    report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "  ${line}"
                done
                max_severity="${VIGIL_SEVERITY_CRIT}"
            fi

            if [[ -n "${config_mods}" ]]; then
                count=$(echo "${config_mods}" | wc -l | tr -d ' ')
                report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "${count} config file(s) modified:"
                echo "${config_mods}" | head -20 | while IFS= read -r line; do
                    report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "  ${line}"
                done
                if (( max_severity < VIGIL_SEVERITY_WARN )); then
                    max_severity="${VIGIL_SEVERITY_WARN}"
                fi
            fi
        fi
        ;;
    debian)
        if ! command_exists debsums; then
            report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "debsums not installed. Run install-deps.sh."
            exit 1
        fi

        changed_files=$(debsums --changed 2>/dev/null || true)

        if [[ -n "${changed_files}" ]]; then
            count=$(echo "${changed_files}" | wc -l | tr -d ' ')
            report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "${count} package file(s) modified:"
            echo "${changed_files}" | head -20 | while IFS= read -r line; do
                report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "  ${line}"
            done
            max_severity="${VIGIL_SEVERITY_CRIT}"
        fi
        ;;
    *)
        report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "Unsupported OS family: ${os_family}"
        exit 1
        ;;
esac

if (( max_severity == VIGIL_SEVERITY_OK )); then
    report_finding "${VIGIL_SEVERITY_OK}" "${CHECK_NAME}" "All package files intact."
fi

exit "${max_severity}"
