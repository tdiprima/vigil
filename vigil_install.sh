#!/bin/bash

YELLOW='\033[0;33m'
NC='\033[0m'

rm -rf vigil
sudo rm -rf /opt/vigil

git clone https://github.com/tdiprima/vigil.git
cd vigil

# Check what's needed and install missing packages
sudo ./install-deps.sh

# Copy to deployment location
sudo cp -r . /opt/vigil

sudo /opt/vigil/vigil-baseline.sh

# Install the systemd timer (runs daily at 05:00 with up to 30 min jitter)
sudo cp /opt/vigil/systemd/vigil-sweep.service /etc/systemd/system/
sudo cp /opt/vigil/systemd/vigil-sweep.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vigil-sweep.timer

# Verify it's scheduled
echo
systemctl list-timers vigil-sweep.timer
echo

echo -e "${YELLOW}Be sure to edit the config${NC}"
echo -e "${YELLOW}sudo vim /opt/vigil/vigil.conf${NC}"
