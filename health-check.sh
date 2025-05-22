#!/bin/bash

# Harmin Patel
# Date created: 10 March 2025
# 45Drives

timestamp=$(date +"%Y%m%d_%H%M%S")
out_dir="/tmp/health-check_$timestamp"
mkdir -p "$out_dir"
logfile="$out_dir/report.log"
filename="report_$timestamp.json"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    platform=$PRETTY_NAME
    os_id=$ID
else
    platform=$(uname -a)
    os_id="unknown"
fi

start_time=$(date +"%Y-%m-%dT%H:%M:%S%:z")
echo "Starting health check script at $start_time for platform: $platform" | tee -a "$logfile"

# Get the current tuned profile
{
    echo "Checking Tuned..."
    if ! command -v tuned-adm &> /dev/null; then
        echo "Tuned is not installed."
    else
        tuned-adm active
    fi
} > "$out_dir/tuned.txt"

# Get the current SELinux mode
{
    echo "Checking SELinux..."
    if ! command -v sestatus &> /dev/null; then
        echo "sestatus not found."
    else
        sestatus
    fi
} > "$out_dir/selinux.txt"

selinux_mode=$(sestatus 2>/dev/null | awk '/Current mode:/ {print $3}')
if [[ "$selinux_mode" == "enforcing" ]]; then
    echo "WARNING: SELinux is in enforcing mode. This may interfere with some operations." >> "$out_dir/selinux.txt"
fi

# RAM usage
free -m > "$out_dir/memory.txt"

# Swap usage
{
    echo "Memory + Swap Usage:"
    free -m
    used_swap=$(free -m | awk '/Swap:/ {print $3}')
    if [ "$used_swap" -gt 500 ]; then
        echo
        echo "WARNING: High swap usage detected ($used_swap MB)"
    fi
} > "$out_dir/swap.txt"

# SMART Drive Summary
{
    echo "SMART Drive Summary"
    for i in $(ls /dev | grep -E '^sd[a-z]$'); do
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
} > "$out_dir/smartctl.txt"

# Drive Age
{
    echo "Drive Age (Power_On_Hours):"
    for i in $(ls /dev | grep -i '^sd[a-z]$'); do
        echo -e "\nDevice: /dev/$i"
        power_on_hours=$(smartctl -A /dev/$i 2>/dev/null | awk '/Power_On_Hours/ {print $10}')
        if [[ -n "$power_on_hours" ]]; then
            echo "Power-On Hours: $power_on_hours"
        else
            echo "Power-On Hours not available."
        fi
    done
} > "$out_dir/drive_age.txt"

# Snapshots
{
    echo "ZFS Snapshots:"
    zpools=$(zpool list -H -o name 2>/dev/null)
    for pool in $zpools; do
        echo "Pool: $pool"
        zfs list -H -t snapshot -o name -s creation -r "$pool" 2>/dev/null | tail -n 25
    done
} > "$out_dir/zfs_snapshots.txt"

# NIC packet errors
{
    echo "Packet Errors:"
    for iface in $(ls /sys/class/net | grep -v lo); do
        echo -n "$iface: "
        cat /sys/class/net/$iface/statistics/{rx_errors,tx_errors} | xargs echo "RX TX"
    done
} > "$out_dir/packet_errors.txt"

# ZFS: Failed Drives Detection
{
    echo "# ZFS Failed Drives Detected"
    zpool status 2>/dev/null | grep -iE 'DEGRADED|FAULTED|OFFLINE' || echo "No failed drives detected"
} > "$out_dir/zfs_failed_drives.txt"

# ZFS: Pool Errors
{
    echo "# ZFS Pool Errors"
    zpool status 2>/dev/null | grep -E 'errors:|read:|write:|cksum:'
} > "$out_dir/zfs_pool_errors.txt"

# ZFS: Autotrim Status
{
    echo "# ZFS Autotrim Status"
    zpool get autotrim 2>/dev/null
} > "$out_dir/zfs_autotrim.txt"

# ZFS: Pool Capacity 
{
    echo "# ZFS Pool Capacity"
    zpool list -H -o name,capacity 2>/dev/null
} > "$out_dir/zfs_capacity.txt"

# Additional files:
uptime > "$out_dir/uptime.txt"
last reboot > "$out_dir/reboot_history.txt"
lspci -nnk > "$out_dir/pci_devices.txt"
ss -tuln > "$out_dir/open_ports.txt"
systemctl --failed > "$out_dir/failed_units.txt"
systemd-analyze > "$out_dir/boot_time.txt"
ip route show default > "$out_dir/default_route.txt"
zpool status > "$out_dir/zfs_status.txt" 2>/dev/null
ceph -s > "$out_dir/ceph_status.txt" 2>/dev/null
apt list --upgradable > "$out_dir/updates.txt" 2>/dev/null
systemctl is-active winbind > "$out_dir/winbind_status.txt" 2>/dev/null
systemctl is-active alertmanager > "$out_dir/alertmanager_status.txt" 2>/dev/null

# JSON Summary File
cat <<EOF > "$out_dir/$filename"
{
  "filename": "$filename",
  "platform": "$platform",
  "os_id": "$os_id",
  "start_time": "$start_time",
  "output_directory": "$out_dir"
}
EOF

# Tarball folder
tar -czf "$out_dir.tar.gz" -C "$(dirname "$out_dir")" "$(basename "$out_dir")"




# filename="$(hostname)_report.json"  

# platform=$(lsb_release -d | awk -F'\t' '{print $2}')

# start_time=$(date +"%Y-%m-%dT%H:%M:%S%:z")

# # Hardware perspective script
# # Check if tuned is installed
# if ! command -v tuned-adm &> /dev/null; then
#     echo
#     echo "Tuned is not installed on this system."
#     echo
# fi

# # Get the current tuned profile
# active_profile=$(tuned-adm active | awk -F": " '/Current active profile/ {print $2}')
# echo "Current Tuned Profile: $active_profile"
# echo "-------------------------------------------------------------------------------"

# # # Capture RAM info using `free`
# echo
# read -r _ total used free shared buff_cache available <<< $(free -m | awk '/^Mem:/ {print $1, $2, $3, $4, $5, $6, $7}')
# echo "RAM Usage (in MB):"
# echo "Total: $total MB"
# echo "Used:  $used MB"
# echo "Cache: $buff_cache MB"
# echo "-------------------------------------------------------------------------------"
# echo

# # Check if sestatus command exists
# if ! command -v sestatus &> /dev/null; then
#     echo "SELinux is not installed or sestatus is not available."
#     echo
# fi

# # Get the current SELinux mode
# selinux_mode=$(sestatus | awk '/Current mode:/ {print $3}')
# echo "SELinux Mode: $selinux_mode"
# # Warn if enforcing
# if [[ "$selinux_mode" == "enforcing" ]]; then
#     echo "WARNING: SELinux is in enforcing mode. This may interfere with some operations."
#     echo
# fi
# echo "-------------------------------------------------------------------------------"
# echo 

# # Check if lsdev exists
# if ! command -v lsdev &> /dev/null; then
#     echo "lsdev is not installed. Please install the 'procinfo' or equivalent package."
# fi
# echo "Hardware Device Summary:"
# lsdev -cdt
# echo "-------------------------------------------------------------------------------"
# echo 

# # Check if smartctl is installed
# if ! command -v smartctl &> /dev/null; then
#     echo "smartctl not found. Please install smartmontools."
# fi

# echo "Drive SMART Stats Summary:"

# # Loop through all /dev/sdX devices (exclude partitions like /dev/sda1)
# for i in $(ls /dev | grep -i '^sd[a-z]$'); do
#     echo -e "\nDevice: /dev/$i"

#     if [[ -d /dev/disk/by-vdev ]]; then
#         slot=$(ls -l /dev/disk/by-vdev/ | grep -w "$i" | awk '{print $9}')
#         echo "Slot: ${slot:-Not labeled}"
#     else
#         echo "Slot: (by-vdev mapping not found)"
#     fi

#     smartctl -x /dev/$i 2>/dev/null | grep -iE \
#         'serial number|reallocated_sector_ct|power_cycle_count|reported_uncorrect|command_timeout|offline_uncorrectable|current_pending_sector'
# done
# echo "-------------------------------------------------------------------------------"
# echo 

# # Memory and Swap usage
# echo -e "Current Uptime:"; uptime;
# echo -e "\nReboot History:"; last reboot
# echo "-------------------------------------------------------------------------------"
# echo 

# # Memory and Swap usage
# echo -e "Memory + Swap Usage:"; free -m; used_swap=$(free -m | awk '/Swap:/ {print $3}'); 
# if [ "$used_swap" -gt 500 ]; 
#     then echo -e "\nWARNING: High swap usage detected ($used_swap MB)"; 
# fi
# echo "-------------------------------------------------------------------------------"
# echo 

# # PCI Devices and Drivers
# echo -e "PCI Devices and Drivers:"; lspci -nnk; 
# echo "-------------------------------------------------------------------------------"
# echo 

# # Network Driver Info
# echo -e "Network Driver Info:"; 
# for iface in $(ls /sys/class/net | grep -v lo); 
#     do echo -e "\nInterface: $iface"; 
#     ethtool -i $iface 2>/dev/null; 
# done
# echo "-------------------------------------------------------------------------------"
# echo 

# # Check for open ports
# echo -e "Open Ports:"
# ss -tuln
# echo "-------------------------------------------------------------------------------"
# echo

# # Check failed systemd units
# echo -e "Failed systemd Units:"
# systemctl --failed
# echo "-------------------------------------------------------------------------------"
# echo

# # Last boot duration
# echo -e "Last Boot Duration:"
# systemd-analyze
# echo "-------------------------------------------------------------------------------"
# echo

# # Drive Age (Power_On_Hours)
# echo -e "Drive Age:"
# if ! command -v smartctl &> /dev/null; then
#     echo "smartctl not found. Please install smartmontools."
# else
#     for i in $(ls /dev | grep -i '^sd[a-z]$'); do
#         echo -e "\nDevice: /dev/$i"
#         power_on_hours=$(smartctl -A /dev/$i 2>/dev/null | awk '/Power_On_Hours/ {print $10}')
#         if [[ -n "$power_on_hours" ]]; then
#             echo "Power-On Hours: $power_on_hours"
#         else
#             echo "Power-On Hours not available."
#         fi
#     done
# fi
# echo "-------------------------------------------------------------------------------"
# echo

# # AlertManager Status
# echo "AlertManager:" 
# systemctl is-active alertmanager
# echo "-------------------------------------------------------------------------------"
# echo

# # Check Snapshots
# echo "Snapshots Info:"
# zpools=$(zpool list -H -o name 2>/dev/null)
# if [[ -z "$zpools" ]]; then
#     echo "No zpools found."
# else
#     for pool in $zpools; do
#         echo "Pool: $pool"
#         snapshots=$(zfs list -H -t snapshot -o name -s creation -r $pool 2>/dev/null | tail -n 25)
#         if [[ -z "$snapshots" ]]; then
#             echo "  No snapshots found."
#         else
#             echo "$snapshots" | sed 's/^/  /'
#         fi
#     done
# fi
# echo "-------------------------------------------------------------------------------"
# echo

# # Packet Error Check
# echo "Packet Errors:"
# for iface in $(ls /sys/class/net | grep -v lo); do
#   echo -n "$iface: "
#   cat /sys/class/net/$iface/statistics/{rx_errors,tx_errors} | xargs echo "RX TX"
# done
# echo "-------------------------------------------------------------------------------"
# echo

# # System updates
# echo "System updates available:"
# apt list --upgradable
# echo "-------------------------------------------------------------------------------"
# echo

# # Winbind Running Check (if domain joined)
# echo -n "Winbind service status: "
# systemctl is-active winbind 2>/dev/null 
# echo "-------------------------------------------------------------------------------"
# echo

# # Primary Route Check
# echo "Primary Default Route:"
# ip route show default | head -n 1
# echo "-------------------------------------------------------------------------------"
# echo

# # ZFS and Ceph Status
# echo "ZFS Status:"
# zpool status
# echo "Ceph Status:" 
# ceph -s
# echo "-------------------------------------------------------------------------------"
# echo

# cat <<EOF
# {
#   "filename": "$filename",
#   "platform": "$platform",
#   "start_time": "$start_time",
# }
# EOF