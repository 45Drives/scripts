#!/bin/bash
set -euo pipefail

NETDEV_BUDGET="600"
PREFERRED_RX="4096"
FALLBACK_RX="2047"

DISPATCHER_SCRIPT="/etc/NetworkManager/dispatcher.d/45-ethtool"
SYSCTL_FILE="/etc/sysctl.d/99-netdev-budget.conf"

if [[ $EUID -ne 0 ]]; then
  echo "Run this as root."
  exit 1
fi

command -v ethtool >/dev/null || {
  echo "ethtool is not installed. Install it first."
  exit 1
}

get_physical_interfaces() {
  for path in /sys/class/net/*; do
    iface="$(basename "$path")"

    [[ "$iface" == "lo" ]] && continue
    [[ -d "$path/device" ]] || continue

    echo "$iface"
  done
}

detect_rx_size() {
  local iface="$1"

  if ethtool -G "$iface" rx "$PREFERRED_RX" >/dev/null 2>&1; then
    echo "$PREFERRED_RX"
  elif ethtool -G "$iface" rx "$FALLBACK_RX" >/dev/null 2>&1; then
    echo "$FALLBACK_RX"
  else
    echo ""
  fi
}

echo "Detecting physical interfaces..."
mapfile -t INTERFACES < <(get_physical_interfaces)

if [[ ${#INTERFACES[@]} -eq 0 ]]; then
  echo "No physical interfaces found."
  exit 1
fi

echo "Found interfaces: ${INTERFACES[*]}"
echo

echo "Testing and applying RX ring settings..."

declare -A RX_SIZE_BY_IFACE

for iface in "${INTERFACES[@]}"; do
  rx_size="$(detect_rx_size "$iface")"

  if [[ -n "$rx_size" ]]; then
    RX_SIZE_BY_IFACE["$iface"]="$rx_size"
    echo "$iface: using RX ring size $rx_size"
  else
    echo "$iface: could not set RX ring to $PREFERRED_RX or $FALLBACK_RX, skipping"
  fi
done

echo
echo "Setting net.core.netdev_budget=$NETDEV_BUDGET"
sysctl -w net.core.netdev_budget="$NETDEV_BUDGET"

echo
echo "Writing static dispatcher script: $DISPATCHER_SCRIPT"

[[ -f "$DISPATCHER_SCRIPT" ]] && cp "$DISPATCHER_SCRIPT" "$DISPATCHER_SCRIPT.bak"

cat > "$DISPATCHER_SCRIPT" <<'EOF'
#!/bin/bash
EOF

for iface in "${INTERFACES[@]}"; do
  rx_size="${RX_SIZE_BY_IFACE[$iface]:-}"

  [[ -z "$rx_size" ]] && continue

  cat >> "$DISPATCHER_SCRIPT" <<EOF
if [ "\$1" == "$iface" ] && [ "\$2" == "up" ]; then
    ethtool -G "$iface" rx "$rx_size"
fi

EOF
done

chmod +x "$DISPATCHER_SCRIPT"

echo "Writing persistent sysctl config: $SYSCTL_FILE"

[[ -f "$SYSCTL_FILE" ]] && cp "$SYSCTL_FILE" "$SYSCTL_FILE.bak"

cat > "$SYSCTL_FILE" <<EOF
net.core.netdev_budget=$NETDEV_BUDGET
EOF

sysctl --system >/dev/null

echo
echo "Validating applied settings..."
ACTUAL_BUDGET="$(sysctl -n net.core.netdev_budget)"
if [[ "$ACTUAL_BUDGET" == "$NETDEV_BUDGET" ]]; then
  echo "✓ net.core.netdev_budget correctly set to $NETDEV_BUDGET"
else
  echo "✗ Warning: net.core.netdev_budget is $ACTUAL_BUDGET (expected $NETDEV_BUDGET)"
fi

echo
echo "Done."
echo "Dispatcher script created at: $DISPATCHER_SCRIPT"
echo "Sysctl persistence created at: $SYSCTL_FILE"
[[ -f "$DISPATCHER_SCRIPT.bak" ]] && echo "Backup saved at: $DISPATCHER_SCRIPT.bak"
[[ -f "$SYSCTL_FILE.bak" ]] && echo "Backup saved at: $SYSCTL_FILE.bak"