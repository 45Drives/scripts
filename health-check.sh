#!/bin/bash

# Harmin Patel
# Date created: 10 March 2025
# 45Drives

filename="$(hostname)_report.json"  

platform=$(lsb_release -d | awk -F'\t' '{print $2}')

start_time=$(date +"%Y-%m-%dT%H:%M:%S%:z")

# Disk & RAM usage
disk_usage=$(df -h / | awk 'NR==2 {print "%.2f", $5}' | sed 's/%//')
disk_free=$(awk "BEGIN {printf \"%.2f\", 100 - $disk_usage}")
ram_usage=$(free -m | awk '/Mem:/ { printf "%.2f", $3/$2 * 100 }')
ram_free=$(awk "BEGIN {printf \"%.2f\", 100 - $ram_usage}")

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
# Show concise device summary
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

    # Try to get slot/vdev label if available
    if [[ -d /dev/disk/by-vdev ]]; then
        slot=$(ls -l /dev/disk/by-vdev/ | grep -w "$i" | awk '{print $9}')
        echo "Slot: ${slot:-Not labeled}"
    else
        echo "Slot: (by-vdev mapping not found)"
    fi

    # Print selected SMART attributes
    smartctl -x /dev/$i 2>/dev/null | grep -iE \
        'serial number|reallocated_sector_ct|power_cycle_count|reported_uncorrect|command_timeout|offline_uncorrectable|current_pending_sector'
done
echo "-------------------------------------------------------------------------------"
echo 

echo -e "\nCurrent Uptime:"; uptime;
echo -e "\nReboot History:"; last reboot
echo "-------------------------------------------------------------------------------"
echo 

echo -e "\nMemory + Swap Usage:"; free -m; used_swap=$(free -m | awk '/Swap:/ {print $3}'); if [ "$used_swap" -gt 500 ]; then echo -e "\n⚠️ WARNING: High swap usage detected ($used_swap MB)"; fi
echo "-------------------------------------------------------------------------------"
echo 

echo -e "\n=== PCI Devices and Drivers ==="; lspci -nnk; 
echo "-------------------------------------------------------------------------------"
echo 

echo -e "\n=== Network Driver Info ==="; for iface in $(ls /sys/class/net | grep -v lo); do echo -e "\nInterface: $iface"; ethtool -i $iface 2>/dev/null; done
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
echo -e "Drive Age (Power_On_Hours):"
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

# # 3) Check Storage System
# if command -v zfs &> /dev/null; then
#     echo "ZFS Status:"
#     zpool status
#     echo
# fi

# # Check Ceph Status
# if command -v ceph &> /dev/null; then
#     echo "Ceph Status:" 
#     ceph -s
#     echo
# fi

# # 4) Check Snapshots
# echo "Snapshots Info:"
# zpools=$(zpool list -H -o name 2>/dev/null)
# if [[ -z "$zpools" ]]; then
#     echo "No zpools found."
# else
#     for pool in $zpools; do
#         echo "Pool: $pool"
#         snapshots=$(zfs list -H -t snapshot -o name -r $pool 2>/dev/null)
#         if [[ -z "$snapshots" ]]; then
#             echo "  No snapshots found."
#         else
#             echo "$snapshots" | sed 's/^/  /'
#         fi
#     done
# fi
# echo

# # 5) AlertManager Status
# echo -n "AlertManager is-active: "
# systemctl is-active alertmanager
# echo

# # 7) Packet Errors
# echo "Packet Errors:"
# netstat -i | awk 'NR==1 || $5 > 0'
# echo

# # 8) iSCSI Fix Applied
# # iSCSI Fix Applied
# if [[ -f /etc/systemd/system/iscsi.service ]]; then
#     echo "iSCSI Fix is applied (/etc/systemd/system/iscsi.service exists)"
# else
#     echo "iSCSI Fix is not applied"
# fi
# echo

# # 9) System Updates Check
# echo "System updates available (apt list --upgradable):"
# apt list --upgradable 2>/dev/null
# echo

# # 10) Read/Write Test
# echo "Performing Read/Write Test on /tmp/testfile..."
# touch /tmp/testfile && echo "test" > /tmp/testfile && cat /tmp/testfile && rm /tmp/testfile
# echo

# # 11) Check Serial Number 
# echo "System Serial mber:"
# cat /sys/class/dmi/id/product_serial 2>/dev/null || echo "not_available"
# echo

# # 12) Check Amount of RAM  
# echo "Total RAM (in MB):"
# free -m | awk '/Mem:/ {print $2}'
# echo

# # 13) Check System Install Date (System Age)  
# echo "System Install Date (based on root dir creation):"
# ls -lt --time=cr / | tail -1 | awk '{print $6, $7, $8}'
# echo

# # 14) Check Link Speed for eth0 (or main NIC)
# echo "eth0 Link Speed:"
# ethtool eth0 2>/dev/null | grep "Speed" || echo "eth0 not detected"
# echo

# # 15) Test Email Alert (Automatic attempt)
# echo "Email config files:"
# grep -H 'mail' /etc/aliases 2>/dev/null
# grep -i 'smtp' /etc/postfix/main.cf 2>/dev/null
# echo

# # 16) AlertManager UI Verification
# # echo "Checking if AlertManager is running on port 9093:"
# # netstat -tuln | grep ':9093'
# # echo

# # 17) Winbind Running Check (if domain joined)
# echo -n "Winbind service status: "
# systemctl is-active winbind 2>/dev/null || echo "not installed"
# echo

# # 18) Global MacOS Config Check (Look for related configs)
# echo "Checking for macOS global config in smb.conf:"
# grep -i 'macos' /etc/samba/smb.conf 2>/dev/null | grep 'global'
# echo

# # 19) File Sharing Permissions Check
# echo "Checking for 'valid users' in smb.conf:"
# grep -i 'valid users' /etc/samba/smb.conf 2>/dev/null
# echo

# # 20) Windows ACL with Linux/MacOS Support
# echo "Checking for Windows ACL support in smb.conf:"
# grep -iq 'nt acl support = yes' /etc/samba/smb.conf 2>/dev/null && echo "ACL support enabled"
# echo

# # 22) SnapShield Last FireDrill Check
# echo "Checking for SnapShield fire drill log:"
# cat /var/log/snapshield_firedrill.log 2>/dev/null || echo "No fire drill log found"
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

# # 4) Network Driver Installed Check
# echo "Network Driver Info for eth0:"
# ethtool -i eth0 2>/dev/null || echo "No driver info found for eth0"
# echo

# # 7) VLAN Usage Check
# echo "VLAN Interfaces:"
# ip -d link show | grep vlan || echo "No VLAN interfaces found"
# echo

# # 8) IPMI Reachability Check
# ipmi_ip="192.168.209.220"  # Change as needed
# echo "Pinging IPMI ($ipmi_ip):"
# ping -c 1 $ipmi_ip
# echo

# # 9) ethtool Check for All Interfaces
# for iface in $(ls /sys/class/net | grep -v lo); do
#     echo "Ethtool Info for $iface:"
#     ethtool $iface 2>/dev/null
#     echo
# done

# # 10) Primary Route Check
# echo "Primary Default Route:"
# ip route show default | head -n 1
# echo




# Check counters and result storage
# "status": {
#     "passed": $passed,
#     "failed": $failed,
#     "not_applicable": $not_applicable,
#     "not_reviewed": $not_reviewed,
#     "total_checks": $total_checks
#   },

# total_checks=0
# passed=0
# failed=0
# not_applicable=0
# not_reviewed=0
# check_results="["

# # Function to run and record checks
# record_check() {
#     local name="$1"
#     local result="$2"
#     check_results+="{\"check\": \"$name\", \"status\": \"$result\"},"
#     if [[ "$result" == "passed" ]]; then
#         passed=$((passed+1))
#     elif [[ "$result" == "failed" ]]; then
#         failed=$((failed+1))
#     elif [[ "$result" == "not_applicable" ]]; then
#         not_applicable=$((not_applicable+1))
#     elif [[ "$result" == "not_reviewed" ]]; then
#         not_reviewed=$((not_reviewed+1))
#     fi
#     total_checks=$((total_checks+1))
# }

# # CHECKS

# # Excel sheet checks
# # 1) Check System Uptime
# uptime_check=$(uptime -p)
# if [[ -n "$uptime_check" ]]; then
#     record_check "System Uptime" "passed"
# else
#     record_check "System Uptime" "failed"
# fi

# # 2) Check Drive Age
# drive_hours=$(smartctl -A /dev/sdb | awk '/Power_On_Hours/ {print $10}')
# if [[ -n "$drive_hours" ]]; then
#     record_check "Drive Age Available" "passed"
# else
#     record_check "Drive Age Available" "failed"
# fi

# # 3) Check Storage System
# if command -v zfs &> /dev/null; then
#     zpool status &> /dev/null && record_check "ZFS Status" "passed"
# else
#     record_check "ZFS Status" "failed"
# fi

# if command -v ceph &> /dev/null; then
#     ceph -s &> /dev/null && record_check "Ceph Status" "passed"
# else
#     record_check "Ceph Status" "failed"
# fi

# # 4) Check Snapshots
# print_snapshots_info() {
#     echo "Snapshots Info:"
#     zpools=$(zpool list -H -o name 2>/dev/null)
#     if [[ -z "$zpools" ]]; then
#         echo "No zpools found."
#         return
#     fi
#     for pool in $zpools; do
#         echo "Pool: $pool"
#         snapshots=$(zfs list -H -t snapshot -o name -r $pool 2>/dev/null)
#         if [[ -z "$snapshots" ]]; then
#             echo "No snapshots found for pool: $pool"
#         else
#             for snapshot in $snapshots; do
#                 echo "Snapshot: $snapshot"
#             done
#         fi
#         echo ""
#     done
# }

# snapshots_enabled=$(zfs list -t snapshot 2>/dev/null | wc -l)
# if [[ "$snapshots_enabled" -gt 0 ]]; then
#     record_check "Snapshots Enabled" "passed"
#     print_snapshots_info
# else
#     record_check "Snapshots Enabled" "failed"
# fi

# # 5) AlertManager Status
# systemctl is-active --quiet alertmanager && record_check "AlertManager Running" "passed" || record_check "AlertManager Running" "failed"

# # 6) Network Connectivity
# ping -c 2 8.8.8.8 &> /dev/null && record_check "Network Connectivity" "passed" || record_check "Network Connectivity" "failed"

# # 7) Packet Errors
# packet_errors=$(netstat -i | awk '{if ($5 > 0) print $0}')
# if [[ -z "$packet_errors" ]]; then
#     record_check "Packet Errors" "passed"
# else
#     record_check "Packet Errors" "failed"
# fi

# # 8) iSCSI Fix Applied
# [[ -f /etc/systemd/system/iscsi.service ]] && record_check "iSCSI Fix Applied" "passed" || record_check "iSCSI Fix Applied" "not_applicable"

# # 9) System Updates Check
# updates_available=$(apt list --upgradable 2>/dev/null | wc -l)
# if [[ "$updates_available" -gt 1 ]]; then
#     record_check "Updates Pending" "failed"
# else
#     record_check "Updates Pending" "passed"
# fi

# # 10) Read/Write Test
# touch /tmp/testfile && echo "test" > /tmp/testfile && rm /tmp/testfile && record_check "Read/Write Test" "passed" || record_check "Read/Write Test" "failed"

# # 11) Check Serial Number  
# serial_number=$(cat /sys/class/dmi/id/product_serial 2>/dev/null || echo "not_available")
# if [[ "$serial_number" != "not_available" ]]; then
#     record_check "System Serial Number Available" "passed"
# else
#     record_check "System Serial Number Available" "failed"
# fi

# # 12) Check Amount of RAM  
# ram_total=$(free -m | awk '/Mem:/ {print $2}')  
# if [[ -n "$ram_total" ]]; then  
#     record_check "RAM Reporting Available" "passed"  
# else  
#     record_check "RAM Reporting Available" "failed"  
# fi  

# # 13) Check System Install Date (System Age)  
# install_date=$(ls -lt --time=cr / | tail -1 | awk '{print $6, $7, $8}')  
# if [[ -n "$install_date" ]]; then  
#     record_check "System Age Available" "passed"  
# else  
#     record_check "System Age Available" "not_reviewed"  
# fi  

# # 14) Check Link Speed for eth0 (or main NIC)  
# link_speed=$(ethtool eth0 2>/dev/null | grep "Speed" | awk '{print $2}')  
# if [[ -n "$link_speed" ]]; then  
#     record_check "Network Link Speed Detected" "passed"  
# else  
#     record_check "Network Link Speed Detected" "not_applicable"  
# fi  
# # 15) Test Email Alert (Automatic attempt)
# if grep -q 'mail' /etc/aliases || grep -qi 'smtp' /etc/postfix/main.cf 2>/dev/null; then
#     record_check "Test Email Alert" "passed"
# else
#     record_check "Test Email Alert" "not_reviewed"
# fi

# # 16) AlertManager UI Verification (Attempt automatic check for running web port)
# if netstat -tuln | grep -q ':9093'; then
#     record_check "AlertManager UI Verification" "passed"
# else
#     record_check "AlertManager UI Verification" "not_reviewed"
# fi

# # 17) Winbind Running Check (if domain joined)
# if systemctl is-active --quiet winbind; then
#     record_check "Winbind Running" "passed"
# else
#     record_check "Winbind Running" "not_applicable"
# fi

# # 18) Global MacOS Config Check (Look for related configs)
# if grep -i 'macos' /etc/samba/smb.conf 2>/dev/null | grep -q 'global'; then
#     record_check "Global MacOS Config" "passed"
# else
#     record_check "Global MacOS Config" "not_reviewed"
# fi

# # 19) File Sharing Permissions Check (Look for valid user/group misconfigurations)
# if grep -i 'valid users' /etc/samba/smb.conf 2>/dev/null; then
#     record_check "File Sharing Permissions" "passed"
# else
#     record_check "File Sharing Permissions" "not_reviewed"
# fi

# # 20) Windows ACL with Linux/MacOS Support (Attempt detection)
# if grep -iq 'nt acl support = yes' /etc/samba/smb.conf 2>/dev/null; then
#     record_check "Windows ACL Config" "passed"
# else
#     record_check "Windows ACL Config" "not_reviewed"
# fi

# # 21) Recalls or Power Harness Defect (Manual or external lookup required)
# #record_check "Hardware Recall Check" "not_reviewed"

# # 22) SnapShield Last FireDrill Check (Look for logs or config entry if exists)
# if [ -f /var/log/snapshield_firedrill.log ]; then
#     record_check "SnapShield Last FireDrill" "passed"
# else
#     record_check "SnapShield Last FireDrill" "not_reviewed"
# fi

# # 23) Recommend Actions Summary (to be generated post-checks or flagged for manual summary)
# #record_check "Recommendation Summary" "not_reviewed"

# # Word document checks
# # Raid status checks
# if command -v zpool &> /dev/null; then
#     zpool status -v > /tmp/zpool_status.txt
#     record_check "ZFS Pool Spec Check (Manual review of /tmp/zpool_status.txt)" "not_reviewed"

#     if zpool status | grep -qi "DEGRADED\|FAULTED\|OFFLINE"; then
#         record_check "ZFS Failed Drives Detected" "failed"
#     else
#         record_check "ZFS Failed Drives Detected" "passed"
#     fi

#     errors=$(zpool status | grep -E 'errors:|read:|write:|cksum:' | grep -v 'errors: No known data errors' | wc -l)
#     if [[ $errors -gt 0 ]]; then
#         record_check "ZFS Pool Errors Found" "failed"
#     else
#         record_check "ZFS Pool Errors Found" "passed"
#     fi

#     if zpool get autotrim | grep -q "on"; then
#         record_check "ZFS Autotrim Enabled" "passed"
#     else
#         record_check "ZFS Autotrim Enabled" "failed"
#     fi

#     zpool status > /tmp/zfs_raid_layout.txt
#     record_check "RAID Layout Best Practice (Manual review in /tmp/zfs_raid_layout.txt)" "not_reviewed"

#     pool_capacity=$(zpool list -H -o capacity | cut -d'%' -f1)
#     if (( pool_capacity < 80 )); then
#         record_check "ZFS Pool Room for Expansion" "passed"
#     else
#         record_check "ZFS Pool Room for Expansion" "failed"
#     fi
# else
#     record_check "ZFS Pool Spec Check" "not_applicable"
#     record_check "ZFS Failed Drives Detected" "not_applicable"
#     record_check "ZFS Pool Errors Found" "not_applicable"
#     record_check "ZFS Autotrim Enabled" "not_applicable"
#     record_check "RAID Layout Best Practice" "not_applicable"
#     record_check "ZFS Pool Room for Expansion" "not_applicable"
# fi

# # Network Interface Configuration checks
# # 1) Log Network Errors
# error_logs=$(dmesg | grep -iE 'error|fail|link|network')
# if [[ -n "$error_logs" ]]; then
#     echo "$error_logs" > /tmp/network_error_logs.txt
#     record_check "Network Error Logs Detected (review /tmp/network_error_logs.txt)" "not_reviewed"
# else
#     record_check "Network Error Logs" "passed"
# fi

# # 2) Bonding Configuration
# if grep -q "bonding" /proc/net/dev; then
#     record_check "Network Bonding Setup" "passed"
# else
#     record_check "Network Bonding Setup" "not_applicable"
# fi

# # 3) MTU Setup Check (for eth0)
# mtu_size=$(ip link show eth0 | grep -oP 'mtu \K[0-9]+')
# if [[ -n "$mtu_size" && "$mtu_size" -ge 1500 ]]; then
#     record_check "MTU Size Setup Properly (eth0)" "passed"
# else
#     record_check "MTU Size Setup (eth0)" "failed"
# fi

# # 4) Network Driver Installed Check
# if ethtool -i eth0 &> /dev/null; then
#     record_check "Network Driver Installed (eth0)" "passed"
# else
#     record_check "Network Driver Installed (eth0)" "failed"
# fi

# # 5) Best Practice Tuning - Manual
# #record_check "Network Best Practice Tuning Review" "not_reviewed"

# # 6) Iperf Test - Manual Recommendation
# #record_check "Iperf Test Between Client and Server" "not_reviewed"

# # 7) VLAN Usage Check
# if ip -d link show | grep -q vlan; then
#     record_check "VLANs In Use" "passed"
# else
#     record_check "VLANs In Use" "not_applicable"
# fi

# # 8) IPMI Reachability Check (assuming default IP)
# ipmi_ip="192.168.209.220"  # Change as needed
# if ping -c 1 $ipmi_ip &> /dev/null; then
#     record_check "IPMI Reachable" "passed"
# else
#     record_check "IPMI Reachability" "not_reviewed"
# fi

# # 9) ethtool Check for All Interfaces
# interfaces=$(ls /sys/class/net | grep -v lo)
# for iface in $interfaces; do
#     ethtool $iface > /tmp/ethtool_$iface.txt 2>/dev/null
#     record_check "Ethtool Output for $iface (Manual Review in /tmp/ethtool_$iface.txt)" "not_reviewed"
# done

# # 10) Primary Route Check
# primary_route=$(ip route show default | head -n 1 | awk '{print $3}')
# if [[ -n "$primary_route" ]]; then
#     record_check "Primary Route Detected: $primary_route" "passed"
# else
#     record_check "Primary Route Check" "failed"
# fi

# # 11) Possible Packet Loss Detection
# # if ping -c 5 192.168.209.220 | grep -q '0% packet loss'; then
# #     record_check "No Packet Loss Detected" "passed"
# # else
# #     record_check "Packet Loss Detected" "failed"
# # fi

# check_results="${check_results%,}]"