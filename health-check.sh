#!/bin/bash

# Harmin Patel
# Date created: 10 March 2025
# 45Drives

filename="$(hostname)_report.json"  

platform=$(lsb_release -d | awk -F'\t' '{print $2}')

start_time=$(date +"%Y-%m-%dT%H:%M:%S%:z")

# Disk & RAM usage
ram_usage=$(free -m | awk '/Mem:/ { printf "%.2f", $3/$2 * 100 }')
ram_free=$(awk "BEGIN {printf \"%.2f\", 100 - $ram_usage}")
disk_usage=$(df / | awk 'NR==2 { printf "%.2f", ($3 / ($3 + $4)) * 100 }')
disk_free=$(awk "BEGIN {printf \"%.2f\", 100 - $disk_usage}")

# Hardware perspective checks
# Check if tuned is installed
if ! command -v tuned-adm &> /dev/null; then
    echo
    echo "Tuned is not installed on this system."
    echo
fi

# Get the current tuned profile
active_profile=$(tuned-adm active | awk -F": " '/Current active profile/ {print $2}')
echo "Current Tuned Profile: $active_profile"
echo "-------------------------------------------------------------------------------"

# # Capture RAM info using `free`
echo
read -r _ total used free shared buff_cache available <<< $(free -m | awk '/^Mem:/ {print $1, $2, $3, $4, $5, $6, $7}')
echo "RAM Usage (in MB):"
echo "Total: $total MB"
echo "Used:  $used MB"
echo "Cache: $buff_cache MB"
echo "-------------------------------------------------------------------------------"
echo

# Check if sestatus command exists
if ! command -v sestatus &> /dev/null; then
    echo "SELinux is not installed or sestatus is not available."
    echo
fi

# Get the current SELinux mode
selinux_mode=$(sestatus | awk '/Current mode:/ {print $3}')
echo "SELinux Mode: $selinux_mode"
# Warn if enforcing
if [[ "$selinux_mode" == "enforcing" ]]; then
    echo "⚠️ WARNING: SELinux is in enforcing mode. This may interfere with some operations."
    echo
fi
echo "-------------------------------------------------------------------------------"
echo 

# Check if lsdev exists
if ! command -v lsdev &> /dev/null; then
    echo "lsdev is not installed. Please install the 'procinfo' or equivalent package."
fi
echo "Hardware Device Summary (lsdev -cdt):"
lsdev -cdt
echo "-------------------------------------------------------------------------------"
echo 

# Check if smartctl is installed
if ! command -v smartctl &> /dev/null; then
    echo "smartctl not found. Please install smartmontools."
fi

echo "===== Drive SMART Stats Summary ====="

# Loop through all /dev/sdX devices (exclude partitions like /dev/sda1)
for i in $(ls /dev | grep -i '^sd[a-z]$'); do
    echo -e "\nDevice: /dev/$i"

    if [[ -d /dev/disk/by-vdev ]]; then
        slot=$(ls -l /dev/disk/by-vdev/ | grep -w "$i" | awk '{print $9}')
        echo "Slot: ${slot:-Not labeled}"
    else
        echo "Slot: (by-vdev mapping not found)"
    fi

    smartctl -x /dev/$i 2>/dev/null | grep -iE \
        'serial number|reallocated_sector_ct|power_cycle_count|reported_uncorrect|command_timeout|offline_uncorrectable|current_pending_sector'
done
echo "-------------------------------------------------------------------------------"
echo 

# Memory and Swap usage
echo -e "\nCurrent Uptime:"; uptime;
echo -e "\nReboot History:"; last reboot
echo "-------------------------------------------------------------------------------"
echo 

# Memory and Swap usage
echo -e "\nMemory + Swap Usage:"; free -m; used_swap=$(free -m | awk '/Swap:/ {print $3}'); 
if [ "$used_swap" -gt 500 ]; 
    then echo -e "\n⚠️ WARNING: High swap usage detected ($used_swap MB)"; 
fi
echo "-------------------------------------------------------------------------------"
echo 

# PCI Devices and Drivers
echo -e "\n=== PCI Devices and Drivers ==="; lspci -nnk; 
echo "-------------------------------------------------------------------------------"
echo 

# Network Driver Info
echo -e "\n=== Network Driver Info ==="; 
for iface in $(ls /sys/class/net | grep -v lo); 
    do echo -e "\nInterface: $iface"; 
    ethtool -i $iface 2>/dev/null; 
done
echo "-------------------------------------------------------------------------------"
echo 

# Check for open ports
echo -e "\nOpen Ports:"
ss -tuln
echo "-------------------------------------------------------------------------------"
echo

# Check failed systemd units
echo -e "\nFailed systemd Units:"
systemctl --failed
echo "-------------------------------------------------------------------------------"
echo

# Last boot duration
echo -e "\nLast Boot Duration:"
systemd-analyze
echo "-------------------------------------------------------------------------------"
echo

# Drive Age (Power_On_Hours)
echo -e "Drive Age:"
if ! command -v smartctl &> /dev/null; then
    echo "smartctl not found. Please install smartmontools."
else
    for i in $(ls /dev | grep -i '^sd[a-z]$'); do
        echo -e "\nDevice: /dev/$i"
        power_on_hours=$(smartctl -A /dev/$i 2>/dev/null | awk '/Power_On_Hours/ {print $10}')
        if [[ -n "$power_on_hours" ]]; then
            echo "Power-On Hours: $power_on_hours"
        else
            echo "Power-On Hours not available."
        fi
    done
fi
echo "-------------------------------------------------------------------------------"
echo

# AlertManager Status
echo "AlertManager:" 
systemctl is-active alertmanager
echo "-------------------------------------------------------------------------------"
echo

# Check Snapshots
echo "Snapshots Info:"
zpools=$(zpool list -H -o name 2>/dev/null)
if [[ -z "$zpools" ]]; then
    echo "No zpools found."
else
    for pool in $zpools; do
        echo "Pool: $pool"
        snapshots=$(zfs list -H -t snapshot -o name -s creation -r $pool 2>/dev/null | tail -n 25)
        if [[ -z "$snapshots" ]]; then
            echo "  No snapshots found."
        else
            echo "$snapshots" | sed 's/^/  /'
        fi
    done
fi
echo "-------------------------------------------------------------------------------"
echo

# Packet Error Check
echo "Packet Errors:"
for iface in $(ls /sys/class/net | grep -v lo); do
  echo -n "$iface: "
  cat /sys/class/net/$iface/statistics/{rx_errors,tx_errors} | xargs echo "RX TX"
done
echo "-------------------------------------------------------------------------------"
echo

# System updates
echo "System updates available:"
apt list --upgradable
echo "-------------------------------------------------------------------------------"
echo

# Winbind Running Check (if domain joined)
echo -n "Winbind service status: "
systemctl is-active winbind 2>/dev/null 
echo "-------------------------------------------------------------------------------"
echo

# Primary Route Check
echo "Primary Default Route:"
ip route show default | head -n 1
echo "-------------------------------------------------------------------------------"
echo

# ZFS and Ceph Status
echo "ZFS Status:"
zpool status
echo "Ceph Status:" 
command -v ceph &> /dev/null && ceph -s
echo "-------------------------------------------------------------------------------"
echo

cat <<EOF
{
  "filename": "$filename",
  "platform": "$platform",
  "start_time": "$start_time",
  "system": {
    "ram_usage_percent": $ram_usage,
    "ram_free_percent": $ram_free,
    "disk_usage_percent": $disk_usage,
    "disk_free_percent": $disk_free
  },
}
EOF

# # Excel sheet checks
# # 13) Check System Install Date (System Age)  
# echo "System Install Date (based on root dir creation):"
# ls -lt / | tail -1 | awk '{print $6, $7, $8}'
# echo

# # 15) Test Email Alert (Automatic attempt)
# echo "Email config files:"
# grep -H 'mail' /etc/aliases 2>/dev/null
# grep -i 'smtp' /etc/postfix/main.cf 2>/dev/null
# echo

# # Raid status checks
# if command -v zpool &> /dev/null; then
#     # ZFS Failed Drives Detected
#     echo "ZFS Failed Drives Check:"
#     zpool status | grep -iE 'DEGRADED|FAULTED|OFFLINE' || echo "No failed drives detected"

#     # ZFS Pool Errors
#     echo "ZFS Pool Errors:"
#     zpool status | grep -E 'errors:|read:|write:|cksum:'

#     # ZFS Autotrim Enabled
#     echo "ZFS Autotrim Status:"
#     zpool get autotrim

#     # ZFS Pool Capacity
#     echo "ZFS Pool Capacity:"
#     zpool list -H -o name,capacity
# fi

# # Network Interface Configuration checks
# # 1) Log Network Errors
# echo "Kernel Network Errors (dmesg):"
# dmesg | grep -iE 'error|fail|link|network'
# echo

# # 2) Bonding Configuration
# echo "Network Bonding Interfaces:"
# cat /proc/net/dev | grep 'bond' || echo "No bonding interfaces found"
# echo

# # 3) MTU Setup Check (for eth0)
# echo "eth0 MTU size:"
# ip link show eth0 | grep -oP 'mtu \K[0-9]+'
# echo

# # 7) VLAN Usage Check
# echo "VLAN Interfaces:"
# ip -d link show | grep vlan || echo "No VLAN interfaces found"
# echo

# # 9) ethtool Check for All Interfaces
# for iface in $(ls /sys/class/net | grep -v lo); do
#     echo "Ethtool Info for $iface:"
#     ethtool $iface 2>/dev/null
#     echo
# done

# # Word document checks
# # Network Interface Configuration checks
# # 1) Log Network Errors
# error_logs=$(dmesg | grep -iE 'error|fail|link|network')
# if [[ -n "$error_logs" ]]; then
#     echo "$error_logs" > /tmp/network_error_logs.txt
#     record_check "Network Error Logs Detected (review /tmp/network_error_logs.txt)" "not_reviewed"
# else
#     record_check "Network Error Logs" "passed"
# fi