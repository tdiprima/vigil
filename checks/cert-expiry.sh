#!/usr/bin/env bash
# Scan for TLS certificates expiring within configured threshold

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIGIL_DIR="${VIGIL_DIR:-$(dirname "${SCRIPT_DIR}")}"

source "${VIGIL_DIR}/lib/common.sh"
load_config "${1:-${VIGIL_DIR}/vigil.conf}"

CHECK_NAME="cert-expiry"
max_severity="${VIGIL_SEVERITY_OK}"
certs_checked=0

update_severity() {
    local new_sev="${1}"
    if (( new_sev > max_severity )); then
        max_severity="${new_sev}"
    fi
}

check_cert() {
    local cert_path="${1}"
    local now_epoch
    now_epoch=$(date +%s)

    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "${cert_path}" 2>/dev/null) || return 0
    expiry_date="${expiry_date#notAfter=}"

    local expiry_epoch
    expiry_epoch=$(date -d "${expiry_date}" +%s 2>/dev/null) || return 0

    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

    if (( days_left < 0 )); then
        report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "EXPIRED: ${cert_path} (${days_left#-} days ago)"
        update_severity "${VIGIL_SEVERITY_CRIT}"
    elif (( days_left <= CERT_CRIT_DAYS )); then
        report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "${cert_path} expires in ${days_left} days"
        update_severity "${VIGIL_SEVERITY_CRIT}"
    elif (( days_left <= CERT_WARN_DAYS )); then
        report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "${cert_path} expires in ${days_left} days"
        update_severity "${VIGIL_SEVERITY_WARN}"
    fi

    certs_checked=$((certs_checked + 1))
}

if ! command_exists openssl; then
    report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "openssl not installed."
    exit 1
fi

for cert_dir in ${CERT_DIRS}; do
    if [[ ! -d "${cert_dir}" ]]; then
        continue
    fi

    while IFS= read -r -d '' cert_file; do
        check_cert "${cert_file}"
    done < <(find "${cert_dir}" -type f \( -name '*.pem' -o -name '*.crt' -o -name '*.cert' \) -print0 2>/dev/null)
done

if (( certs_checked == 0 )); then
    report_finding "${VIGIL_SEVERITY_OK}" "${CHECK_NAME}" "No certificate files found in configured directories."
elif (( max_severity == VIGIL_SEVERITY_OK )); then
    report_finding "${VIGIL_SEVERITY_OK}" "${CHECK_NAME}" "All ${certs_checked} certificates valid (>${CERT_WARN_DAYS} days remaining)."
fi

exit "${max_severity}"
