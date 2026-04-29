#!/usr/bin/env bash
# Check disk space and inode usage against configured thresholds

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIGIL_DIR="${VIGIL_DIR:-$(dirname "${SCRIPT_DIR}")}"

source "${VIGIL_DIR}/lib/common.sh"
load_config "${1:-${VIGIL_DIR}/vigil.conf}"

CHECK_NAME="disk-usage"
max_severity="${VIGIL_SEVERITY_OK}"

update_severity() {
    local new_sev="${1}"
    if (( new_sev > max_severity )); then
        max_severity="${new_sev}"
    fi
}

check_disk_space() {
    local df_output
    df_output=$(mktemp)

    if df -h --output=source,size,used,avail,pcent,target / >/dev/null 2>&1; then
        df -h --output=source,size,used,avail,pcent,target | tail -n +2 > "${df_output}"
    else
        df -h | tail -n +2 > "${df_output}"
    fi

    while read -r filesystem _size _used avail pct mountpoint; do
        case "${filesystem}" in
            tmpfs|devtmpfs|none|overlay) continue ;;
        esac

        local usage="${pct%\%}"

        if (( usage >= DISK_CRIT_PCT )); then
            report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "Disk ${mountpoint} at ${pct} (${avail} free)"
            update_severity "${VIGIL_SEVERITY_CRIT}"
        elif (( usage >= DISK_WARN_PCT )); then
            report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "Disk ${mountpoint} at ${pct} (${avail} free)"
            update_severity "${VIGIL_SEVERITY_WARN}"
        fi
    done < "${df_output}"

    rm -f "${df_output}"
}

check_inode_usage() {
    local df_output
    df_output=$(mktemp)

    if df -i --output=source,itotal,iused,iavail,ipcent,target / >/dev/null 2>&1; then
        df -i --output=source,itotal,iused,iavail,ipcent,target | tail -n +2 > "${df_output}"
    else
        df -i | tail -n +2 > "${df_output}"
    fi

    while read -r filesystem _itotal _iused iavail ipct mountpoint; do
        case "${filesystem}" in
            tmpfs|devtmpfs|none|overlay) continue ;;
        esac

        if [[ "${ipct}" == "-" ]] || [[ -z "${ipct}" ]]; then
            continue
        fi

        local usage="${ipct%\%}"

        if (( usage >= INODE_CRIT_PCT )); then
            report_finding "${VIGIL_SEVERITY_CRIT}" "${CHECK_NAME}" "Inodes ${mountpoint} at ${ipct} (${iavail} free)"
            update_severity "${VIGIL_SEVERITY_CRIT}"
        elif (( usage >= INODE_WARN_PCT )); then
            report_finding "${VIGIL_SEVERITY_WARN}" "${CHECK_NAME}" "Inodes ${mountpoint} at ${ipct} (${iavail} free)"
            update_severity "${VIGIL_SEVERITY_WARN}"
        fi
    done < "${df_output}"

    rm -f "${df_output}"
}

check_disk_space
check_inode_usage

if (( max_severity == VIGIL_SEVERITY_OK )); then
    report_finding "${VIGIL_SEVERITY_OK}" "${CHECK_NAME}" "All filesystems within thresholds."
fi

exit "${max_severity}"
