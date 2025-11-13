#!/usr/bin/env bash

# Disable all CPU C states except C0 using a systemd service
# Intended usage:
#   curl -sSL https://scripts.45drives.com/disable-cstates.sh | sudo bash

set -euo pipefail

SERVICE_UNIT="disable-cstates.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_UNIT}"
SCRIPT_PATH="/usr/local/bin/disable-cstates-except0.sh"

echo "CPU C state hardening script"
echo

# Basic safety checks
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root or with sudo."
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemd is required but systemctl was not found."
  exit 1
fi

echo "Creating systemd unit at ${SERVICE_PATH} ..."

cat << 'EOF' > "${SERVICE_PATH}"
[Unit]
Description=Disable all CPU C states except C0 at boot
DefaultDependencies=no
After=sysinit.target
ConditionDirectoryNotEmpty=/sys/devices/system/cpu

[Service]
Type=oneshot
ExecStart=/usr/local/bin/disable-cstates-except0.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo "Creating helper script at ${SCRIPT_PATH} ..."

cat << 'EOF' > "${SCRIPT_PATH}"
#!/bin/bash

if [ -d /sys/devices/system/cpu/cpu0/cpuidle ]; then
  for i in $(seq 0 $(( $(nproc) - 1 ))); do
    for f in /sys/devices/system/cpu/cpu$i/cpuidle/state*/disable; do
      case "$f" in
        */state0/disable) continue ;;
        *) echo 1 > "$f" || true ;;
      esac
    done
  done
fi
EOF

echo "Setting executable bit on helper script ..."
chmod +x "${SCRIPT_PATH}"

echo "Reloading systemd units ..."
systemctl daemon-reload

echo "Enabling and starting ${SERVICE_UNIT} ..."
systemctl enable --now "${SERVICE_UNIT}"

echo
echo "Done."
echo
echo "Reboot the server, then verify with:"
echo "  cpupower idle-info"
echo
