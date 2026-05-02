#!/usr/bin/env bash
# Check for drift from known-good baseline: users, cron jobs, SUID files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIGIL_DIR="${VIGIL_DIR:-$(dirname "${SCRIPT_DIR}")}"

source "${VIGIL_DIR}/lib/common.sh"
load_config "${1:-${VIGIL_DIR}/vigil.conf}"

CHECK_NAME="baseline-drift"
max_severity="${VIGIL_SEVERITY_OK}"

update_severity() {
    local new_sev="${1}"
    if (( new_sev > max_severity )); then
        max_severity="${new_sev}"
    fi
}

if [[ ! -d "${BASELINE_DIR}" ]] || [[ -z "$(ls -A "${BASELINE_DIR}" 2>/dev/null)" ]]; then
    report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "No baseline found. Run vigil-baseline.sh first."
    exit 1
fi

# ─── Users ────────────────────────────────────────────────
if [[ -f "${BASELINE_DIR}/users.baseline" ]]; then
    current_users=$(mktemp)
    cut -d: -f1,3,6,7 /etc/passwd > "${current_users}"

    new_users=$(diff "${BASELINE_DIR}/users.baseline" "${current_users}" | grep '^>' | sed 's/^> //' || true)
    removed_users=$(diff "${BASELINE_DIR}/users.baseline" "${current_users}" | grep '^<' | sed 's/^< //' || true)

    if [[ -n "${new_users}" ]]; then
        while IFS= read -r user_line; do
            report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "New user: ${user_line}"
            update_severity "${VIGIL_SEVERITY_CRIT}"
        done <<< "${new_users}"
    fi

    if [[ -n "${removed_users}" ]]; then
        while IFS= read -r user_line; do
            report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "Removed user: ${user_line}"
            update_severity "${VIGIL_SEVERITY_WARN}"
        done <<< "${removed_users}"
    fi

    rm -f "${current_users}"
fi

# ─── Cron Jobs ────────────────────────────────────────────
if [[ -f "${BASELINE_DIR}/cron.baseline" ]]; then
    current_cron=$(mktemp)
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
    } > "${current_cron}" 2>/dev/null

    cron_diff=$(diff "${BASELINE_DIR}/cron.baseline" "${current_cron}" 2>/dev/null || true)
    if [[ -n "${cron_diff}" ]]; then
        new_entries=$(echo "${cron_diff}" | grep '^>' | head -20 || true)
        if [[ -n "${new_entries}" ]]; then
            report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "Cron jobs changed — new/modified entries:"
            while IFS= read -r line; do
                report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "  ${line}"
            done <<< "${new_entries}"
            update_severity "${VIGIL_SEVERITY_CRIT}"
        fi
    fi

    rm -f "${current_cron}"
fi

# ─── SUID Files ──────────────────────────────────────────
if [[ "${SKIP_SUID_CHECK}" != "true" ]] && [[ -f "${BASELINE_DIR}/suid.baseline" ]]; then
    current_suid=$(mktemp)
    find / -perm -4000 -type f 2>/dev/null | sort > "${current_suid}"

    new_suid=$(diff "${BASELINE_DIR}/suid.baseline" "${current_suid}" | grep '^>' | sed 's/^> //' || true)
    removed_suid=$(diff "${BASELINE_DIR}/suid.baseline" "${current_suid}" | grep '^<' | sed 's/^< //' || true)

    if [[ -n "${new_suid}" ]]; then
        while IFS= read -r suid_file; do
            report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "New SUID binary: ${suid_file}"
            update_severity "${VIGIL_SEVERITY_CRIT}"
        done <<< "${new_suid}"
    fi

    if [[ -n "${removed_suid}" ]]; then
        while IFS= read -r suid_file; do
            report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "Removed SUID binary: ${suid_file}"
            update_severity "${VIGIL_SEVERITY_WARN}"
        done <<< "${removed_suid}"
    fi

    rm -f "${current_suid}"
fi

if (( max_severity == VIGIL_SEVERITY_OK )); then
    report_finding "${VIGIL_SEVERITY_OK}" "${CHECK_NAME}" "No drift from baseline detected."
fi

exit "${max_severity}"
