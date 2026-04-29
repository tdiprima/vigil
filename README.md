# Vigil 🕯️

vigil — "keeping watch"

**A daily automated security sweep for Linux servers that catches drift, rootkits, tampered binaries, expiring certs, unauthorized ports, brute-force spikes, and full disks — then emails you a single digest before your morning coffee.**

## Servers Don't Tell You When They've Been Compromised

A new user appears in `/etc/passwd` at 3 AM. A cron job shows up that nobody added. A binary's checksum no longer matches its package. A certificate quietly expires and takes down your API. Disk fills up overnight and your database crashes.

These things happen between your SSH sessions. Without automated daily checks, you find out from an outage — not from a report.

Most teams either run nothing (too busy) or run expensive commercial agents (too complex). There's a gap for teams that want solid coverage from tools already on the box, wired together and scheduled to run every morning.

## Seven Checks, One Report, Zero Agents to Install

Vigil is a pure-bash pipeline that runs seven security and health checks via a systemd timer, compiles the results into a single digest email, and fires immediate alerts for anything critical. No daemons, no databases, no external dependencies beyond standard Linux packages.

| Check | What it uses | What it catches |
|-------|-------------|-----------------|
| Baseline drift | `diff` against snapshots | New users, cron jobs, SUID binaries |
| Rootkit scan | `rkhunter --check` | Known rootkits, suspicious files |
| Package integrity | `rpm -Va` / `debsums` | Modified system binaries |
| Certificate expiry | `openssl x509 -enddate` | Certs expiring within 30 days (configurable) |
| Listening ports | `ss -tlnp` diff against known-good | Unauthorized services |
| Failed auth spike | Auth log parsing | Brute-force attempts beyond thresholds |
| Disk/inode usage | `df -h` / `df -i` | Full disks before they kill services |

Each check is an independent script that can run standalone or as part of the sweep. Critical findings trigger an immediate email the moment that check completes — the daily digest follows with everything.

## What the Output Looks Like

```
=======================================================
  VIGIL Security Sweep — prod-web-01 — 2026-04-29
=======================================================

Summary: 1 critical, 2 warnings, 4 clean

--- Baseline Drift -----------------------------------------
[CRIT] [baseline-drift] New SUID binary: /usr/local/bin/ncat
[CRIT] [baseline-drift] New user: deploy:1001:/home/deploy:/bin/bash

--- Rootkit Scan -------------------------------------------
[OK] [rootkit-scan] No rootkits or suspicious files detected.

--- Package Integrity --------------------------------------
[WARN] [package-integrity] 2 config file(s) modified:
[WARN] [package-integrity]   ..5....T.  c /etc/ssh/sshd_config

--- Certificate Expiry -------------------------------------
[WARN] [cert-expiry] /etc/letsencrypt/live/api.example.com/cert.pem expires in 12 days

--- Listening Ports ----------------------------------------
[CRIT] [listening-ports] Unknown listener: 0.0.0.0:4444 users:(("nc",pid=8821,fd=3))

--- Failed Auth --------------------------------------------
[OK] [failed-auth] Auth failures normal. 23 total attempts.

--- Disk Usage ---------------------------------------------
[OK] [disk-usage] All filesystems within thresholds.

=======================================================
  End of Report — 2026-04-29 05:03:17
=======================================================
```

## Getting Started

### Prerequisites

RHEL/CentOS/Rocky/Alma or Ubuntu/Debian. Vigil autodetects the OS family and uses the right package manager and log paths.

### Install

```bash
git clone <repo-url> vigil
cd vigil

# Check what's needed and install missing packages
sudo ./install-deps.sh

# Preview without installing
./install-deps.sh --dry-run
```

### Configure

```bash
# Copy to deployment location
sudo cp -r . /opt/vigil

# Edit the config
sudo vim /opt/vigil/vigil.conf
```

Key settings in `vigil.conf`:

```bash
EMAIL_RECIPIENT="you@example.com"
SMTP_METHOD="mailx"            # mailx, sendmail, or msmtp
CERT_WARN_DAYS=30              # days before cert expiry triggers warning
DISK_WARN_PCT=80               # disk usage warning threshold
AUTH_FAIL_WARN_THRESHOLD=50    # failed auths per IP before alerting
```

### Create the Baseline

Vigil compares current system state against a known-good snapshot. Create one after setup:

```bash
sudo /opt/vigil/vigil-baseline.sh
```

This captures users, cron jobs, SUID files, and listening ports. Re-run it after intentional system changes (new packages, new users, new services).

### Test Run

```bash
# Run all checks, print report, skip email
sudo /opt/vigil/vigil-sweep.sh --no-email
```

### Schedule It

```bash
# Install the systemd timer (runs daily at 05:00 with up to 5 min jitter)
sudo cp /opt/vigil/systemd/vigil-sweep.service /etc/systemd/system/
sudo cp /opt/vigil/systemd/vigil-sweep.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vigil-sweep.timer

# Verify it's scheduled
systemctl list-timers vigil-sweep.timer
```

## Project Structure

```
vigil/
├── vigil.conf                 # Thresholds, paths, email settings
├── vigil-sweep.sh             # Orchestrator — runs all checks, builds report
├── vigil-baseline.sh          # Snapshot known-good system state
├── install-deps.sh            # Detect + install missing packages
├── lib/
│   ├── common.sh              # OS detection, logging, severity levels
│   └── alert.sh               # Email dispatch (mailx/sendmail/msmtp)
├── checks/
│   ├── baseline-drift.sh      # Users, cron jobs, SUID changes
│   ├── rootkit-scan.sh        # rkhunter wrapper
│   ├── package-integrity.sh   # rpm -Va or debsums
│   ├── cert-expiry.sh         # TLS certificate expiration
│   ├── listening-ports.sh     # Ports vs known-good list
│   ├── failed-auth.sh         # Auth log brute-force detection
│   └── disk-usage.sh          # Disk space and inode thresholds
└── systemd/
    ├── vigil-sweep.service    # oneshot service unit
    └── vigil-sweep.timer      # daily timer with jitter
```

## Running Individual Checks

Every check script is independently executable:

```bash
sudo ./checks/cert-expiry.sh /opt/vigil/vigil.conf
sudo ./checks/disk-usage.sh /opt/vigil/vigil.conf
```

Exit codes follow a consistent convention: `0` = clean, `1` = warning, `2` = critical.

## License

[MIT](LICENSE)

<BR>
