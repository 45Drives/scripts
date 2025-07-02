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
echo "The Health Check Report has been saved in tmp/ folder." | tee -a "$logfile"

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
    for iface in $(ls /sys/class/net); do
        # Skip 'lo' and non-directory entries
        if [ "$iface" = "lo" ] || [ ! -d "/sys/class/net/$iface/statistics" ]; then
            continue
        fi

        rx_file="/sys/class/net/$iface/statistics/rx_errors"
        tx_file="/sys/class/net/$iface/statistics/tx_errors"

        if [ -f "$rx_file" ] && [ -f "$tx_file" ]; then
            rx=$(cat "$rx_file")
            tx=$(cat "$tx_file")
            echo "$iface: RX $rx  TX $tx"
        else
            echo "$iface: statistics not available"
        fi
    done
} > "$out_dir/packet_errors.txt"

# ZFS
{
    echo "# ZFS Status"
    zpool status 2>/dev/null

    echo "# ZFS Failed Drives Detected"
    zpool status 2>/dev/null | grep -iE 'DEGRADED|FAULTED|OFFLINE' || echo "No failed drives detected"

    echo "# ZFS Autotrim Status"
    zpool get autotrim 2>/dev/null

    echo "# ZFS Pool Capacity"
    zpool list -H -o name,capacity 2>/dev/null
} > "$out_dir/zfs_summary.txt"

# ZFS: Pool Errors
{
    echo "# ZFS Pool Errors"
    zpool status 2>/dev/null | grep -E 'errors:|read:|write:|cksum:'
} > "$out_dir/zfs_pool_errors.txt"

# Additional files:
uptime > "$out_dir/uptime.txt"
last reboot > "$out_dir/reboot_history.txt"
lspci -nnk > "$out_dir/pci_devices.txt"
ss -tuln > "$out_dir/open_ports.txt"
systemctl --failed > "$out_dir/failed_units.txt"
systemd-analyze > "$out_dir/boot_time.txt"
ip route show default > "$out_dir/default_route.txt"
ceph -s > "$out_dir/ceph_status.txt" 2>/dev/null
apt list --upgradable > "$out_dir/updates.txt" 2>/dev/null
systemctl status winbind > "$out_dir/winbind_status.txt" 2>&1
systemctl status alertmanager > "$out_dir/alertmanager_status.txt" 2>&1

# Config Files
cp /etc/samba/smb.conf "$out_dir/samba_conf.txt" 2>/dev/null || echo "/etc/samba/smb.conf not found" > "$out_dir/samba_conf.txt"
cp /etc/exports.d/cockpit-file-sharing.exports "$out_dir/nfs_exports.txt" 2>/dev/null || echo "/etc/exports.d/cockpit-file-sharing.exports not found" > "$out_dir/nfs_exports.txt"
cp /etc/scst.conf "$out_dir/iscsi_conf.txt" 2>/dev/null || echo "/etc/scst.conf not found" > "$out_dir/iscsi_conf.txt"

# ZFS Usage
zfs list > "$out_dir/zfs_usage.txt" 2>/dev/null || echo "zfs list failed" > "$out_dir/zfs_usage.txt"

# Package Versions
if [ "$os_id" == "rocky" ] || grep -qi "rocky" /etc/os-release; then
    rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}\n' > "$out_dir/rocky_packages.txt"
elif [ "$os_id" == "ubuntu" ] || grep -qi "ubuntu" /etc/os-release; then
    dpkg-query -W -f='${binary:Package} ${Version}\n' > "$out_dir/ubuntu_packages.txt"
else
    echo "Unsupported OS for package query. (No Rocky or Ubuntu detected)" > "$out_dir/package_versions.txt"
fi

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