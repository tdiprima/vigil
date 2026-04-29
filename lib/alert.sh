#!/usr/bin/env bash
# Email alerting for Vigil security sweep

send_email() {
    local subject="${1}"
    local body_file="${2}"
    local recipient="${3:-${EMAIL_RECIPIENT}}"
    local from="${EMAIL_FROM:-vigil@$(hostname)}"

    if [[ ! -f "${body_file}" ]]; then
        log_error "Email body file not found: ${body_file}"
        return 1
    fi

    case "${SMTP_METHOD}" in
        mailx)
            if command_exists mailx; then
                mailx -s "${subject}" "${recipient}" < "${body_file}"
            elif command_exists mail; then
                mail -s "${subject}" "${recipient}" < "${body_file}"
            else
                log_error "No mail command found. Install mailx."
                return 1
            fi
            ;;
        sendmail)
            if ! command_exists sendmail; then
                log_error "sendmail not found"
                return 1
            fi
            {
                echo "From: ${from}"
                echo "To: ${recipient}"
                echo "Subject: ${subject}"
                echo "Content-Type: text/plain; charset=UTF-8"
                echo ""
                cat "${body_file}"
            } | sendmail -t
            ;;
        msmtp)
            if ! command_exists msmtp; then
                log_error "msmtp not found"
                return 1
            fi
            {
                echo "From: ${from}"
                echo "To: ${recipient}"
                echo "Subject: ${subject}"
                echo "Content-Type: text/plain; charset=UTF-8"
                echo ""
                cat "${body_file}"
            } | msmtp "${recipient}"
            ;;
        *)
            log_error "Unknown SMTP method: ${SMTP_METHOD}"
            return 1
            ;;
    esac
}

send_digest() {
    local report_file="${1}"
    local hostname_short
    hostname_short="$(hostname -s 2>/dev/null || hostname)"
    local subject
    subject="[Vigil] Daily Security Digest — ${hostname_short} — $(datestamp)"
    send_email "${subject}" "${report_file}"
}

send_critical_alert() {
    local alert_file="${1}"
    local hostname_short
    hostname_short="$(hostname -s 2>/dev/null || hostname)"
    local subject="[VIGIL CRITICAL] ${hostname_short} — Immediate Attention Required"
    send_email "${subject}" "${alert_file}"
}
