#!/usr/bin/env bash
# Parse auth logs for brute-force spikes beyond fail2ban thresholds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIGIL_DIR="${VIGIL_DIR:-$(dirname "${SCRIPT_DIR}")}"

source "${VIGIL_DIR}/lib/common.sh"
load_config "${1:-${VIGIL_DIR}/vigil.conf}"

CHECK_NAME="failed-auth"
max_severity="${VIGIL_SEVERITY_OK}"
os_family=$(detect_os)

case "${os_family}" in
    debian)  auth_log="/var/log/auth.log" ;;
    rhel)    auth_log="/var/log/secure" ;;
    *)
        if [[ -f /var/log/auth.log ]]; then
            auth_log="/var/log/auth.log"
        elif [[ -f /var/log/secure ]]; then
            auth_log="/var/log/secure"
        else
            report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "No auth log found."
            exit 1
        fi
        ;;
esac

if [[ ! -r "${auth_log}" ]]; then
    report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "Cannot read ${auth_log}. Check permissions."
    exit 1
fi

yesterday=$(date -d "yesterday" '+%b %e' 2>/dev/null || true)
today=$(date '+%b %e')
date_filter="${today}"
if [[ -n "${yesterday}" ]]; then
    date_filter="${today}|${yesterday}"
fi

failed_ips=$(mktemp)
grep -E "(Failed password|authentication failure|Invalid user)" "${auth_log}" 2>/dev/null \
    | grep -E "(${date_filter})" \
    | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | sort \
    | uniq -c \
    | sort -rn \
    > "${failed_ips}" || true

total_failures=0
crit_ips=0
warn_ips=0

while read -r count ip_addr; do
    if [[ -z "${count}" ]] || [[ -z "${ip_addr}" ]]; then
        continue
    fi

    total_failures=$((total_failures + count))

    if (( count >= AUTH_FAIL_CRIT_THRESHOLD )); then
        report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "${count} failures from ${ip_addr} in last 24h"
        max_severity="${VIGIL_SEVERITY_CRIT}"
        crit_ips=$((crit_ips + 1))
    elif (( count >= AUTH_FAIL_WARN_THRESHOLD )); then
        report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "${count} failures from ${ip_addr} in last 24h"
        if (( max_severity < VIGIL_SEVERITY_WARN )); then
            max_severity="${VIGIL_SEVERITY_WARN}"
        fi
        warn_ips=$((warn_ips + 1))
    fi
done < "${failed_ips}"

if (( max_severity == VIGIL_SEVERITY_OK )); then
    report_finding "${VIGIL_SEVERITY_OK}" "${CHECK_NAME}" "Auth failures normal. ${total_failures} total attempts."
else
    report_finding "${max_severity}" "${CHECK_NAME}" "Summary: ${total_failures} total, ${crit_ips} critical IPs, ${warn_ips} warning IPs."
fi

rm -f "${failed_ips}"
exit "${max_severity}"
