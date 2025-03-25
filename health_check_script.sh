#!/bin/bash

# Harmin Patel
# Date created: 10 March 2025
# 45Drives

filename="$(hostname)_report.json"  

if command -v zfs &> /dev/null; then
    tool_version=$(zfs --version | head -n 1 | awk '{print $2}' | cut -d'-' -f1)
elif command -v lsb_release &> /dev/null; then
    tool_version=$(uname -r | cut -d'-' -f1)  
else
    tool_version="Unknown"
fi

platform=$(lsb_release -d | awk -F'\t' '{print $2}')

START_TIME_FILE="/tmp/health_check_start_time"
if [[ ! -f "$START_TIME_FILE" ]]; then
    echo "$(date +%s.%N)" > "$START_TIME_FILE"
fi
SCRIPT_START_TIME=$(cat "$START_TIME_FILE")
CURRENT_TIME=$(date +%s.%N)
duration=$(awk "BEGIN {printf \"%.9f\", $CURRENT_TIME - $SCRIPT_START_TIME}")
if (( $(echo "$duration > 10000" | bc -l) )); then
    echo "$(date +%s.%N)" > "$START_TIME_FILE"
    SCRIPT_START_TIME=$(cat "$START_TIME_FILE")
    duration="0.000000000"
fi

start_time=$(date +"%Y-%m-%dT%H:%M:%S%:z")

# Disk & RAM usage
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
disk_free=$(awk "BEGIN {printf \"%.2f\", 100 - $disk_usage}")
ram_usage=$(free -m | awk '/Mem:/ { printf "%.2f", $3/$2 * 100 }')
ram_free=$(awk "BEGIN {printf \"%.2f\", 100 - $ram_usage}")

# CPU cores/threads
total_cores=$(lscpu | awk '/^Core\(s\) per socket:/ {print $4}')
sockets=$(lscpu | awk '/^Socket\(s\):/ {print $2}')
threads_per_core=$(lscpu | awk '/^Thread\(s\) per core:/ {print $4}')
total_cores=$((total_cores * sockets))
total_threads=$((total_cores * threads_per_core))
cpu_idle=$(mpstat 1 1 | awk '/Average/ {print $NF}')
cpu_usage=$(awk "BEGIN {printf \"%.2f\", 100 - $cpu_idle}")
threads_in_use=$(ps -eL -o stat | grep -E 'R|D' | wc -l)
threads_free=$((total_threads - threads_in_use))
if [ $threads_free -lt 0 ]; then
  threads_free=0
fi
cores_in_use=$(mpstat -P ALL 1 1 | awk '$3 ~ /^[0-9]+$/ { if ($12 < 95) count++ } END { print count }')
cores_free=$((total_cores - cores_in_use))

# Check counters and result storage
total_checks=0
passed=0
failed=0
not_applicable=0
not_reviewed=0
check_results="["

# Function to run and record checks
record_check() {
    local name="$1"
    local result="$2"
    check_results+="{\"check\": \"$name\", \"status\": \"$result\"},"
    if [[ "$result" == "passed" ]]; then
        passed=$((passed+1))
    elif [[ "$result" == "failed" ]]; then
        failed=$((failed+1))
    elif [[ "$result" == "not_applicable" ]]; then
        not_applicable=$((not_applicable+1))
    elif [[ "$result" == "not_reviewed" ]]; then
        not_reviewed=$((not_reviewed+1))
    fi
    total_checks=$((total_checks+1))
}

# CHECKS

# 1) Check System Uptime
uptime_check=$(uptime -p)
if [[ -n "$uptime_check" ]]; then
    record_check "System Uptime" "passed"
else
    record_check "System Uptime" "failed"
fi

# 2) Check Drive Age
drive_hours=$(smartctl -A /dev/sda | awk '/Power_On_Hours/ {print $10}')
if [[ -n "$drive_hours" ]]; then
    record_check "Drive Age Available" "passed"
else
    record_check "Drive Age Available" "failed"
fi

# 3) Check Storage System
if command -v zfs &> /dev/null; then
    zpool status &> /dev/null && record_check "ZFS Status" "passed" || record_check "ZFS Status" "failed"
elif command -v ceph &> /dev/null; then
    ceph -s &> /dev/null && record_check "Ceph Status" "passed" || record_check "Ceph Status" "failed"
else
    record_check "Storage System Check" "not_applicable"
fi

# 4) Check Snapshots
print_snapshots_info() {
    echo "Snapshots Info:"
    zpools=$(zpool list -H -o name 2>/dev/null)
    if [[ -z "$zpools" ]]; then
        echo "No zpools found."
        return
    fi
    for pool in $zpools; do
        echo "Pool: $pool"
        snapshots=$(zfs list -H -t snapshot -o name -r $pool 2>/dev/null)
        if [[ -z "$snapshots" ]]; then
            echo "No snapshots found for pool: $pool"
        else
            for snapshot in $snapshots; do
                echo "Snapshot: $snapshot"
            done
        fi
        echo ""
    done
}

snapshots_enabled=$(zfs list -t snapshot 2>/dev/null | wc -l)
if [[ "$snapshots_enabled" -gt 0 ]]; then
    record_check "Snapshots Enabled" "passed"
    print_snapshots_info
else
    record_check "Snapshots Enabled" "failed"
fi

# 5) AlertManager Status
systemctl is-active --quiet alertmanager && record_check "AlertManager Running" "passed" || record_check "AlertManager Running" "failed"

# 6) Network Connectivity
ping -c 2 8.8.8.8 &> /dev/null && record_check "Network Connectivity" "passed" || record_check "Network Connectivity" "failed"

# 7) Packet Errors
packet_errors=$(netstat -i | awk '{if ($5 > 0) print $0}')
if [[ -z "$packet_errors" ]]; then
    record_check "Packet Errors" "passed"
else
    record_check "Packet Errors" "failed"
fi

# 8) iSCSI Fix Applied
[[ -f /etc/systemd/system/iscsi.service ]] && record_check "iSCSI Fix Applied" "passed" || record_check "iSCSI Fix Applied" "not_applicable"

# 9) System Updates Check
updates_available=$(apt list --upgradable 2>/dev/null | wc -l)
if [[ "$updates_available" -gt 1 ]]; then
    record_check "Updates Pending" "failed"
else
    record_check "Updates Pending" "passed"
fi

# 10) Read/Write Test
touch /tmp/testfile && echo "test" > /tmp/testfile && rm /tmp/testfile && record_check "Read/Write Test" "passed" || record_check "Read/Write Test" "failed"

# 11) Check Serial Number  
serial_number=$(cat /sys/class/dmi/id/product_serial 2>/dev/null || echo "not_available")
if [[ "$serial_number" != "not_available" ]]; then
    record_check "System Serial Number Available" "passed"
else
    record_check "System Serial Number Available" "failed"
fi

# 12) Check Amount of RAM  
ram_total=$(free -m | awk '/Mem:/ {print $2}')  
if [[ -n "$ram_total" ]]; then  
    record_check "RAM Reporting Available" "passed"  
else  
    record_check "RAM Reporting Available" "failed"  
fi  

# 13) Check System Install Date (System Age)  
install_date=$(ls -lt --time=cr / | tail -1 | awk '{print $6, $7, $8}')  
if [[ -n "$install_date" ]]; then  
    record_check "System Age Available" "passed"  
else  
    record_check "System Age Available" "not_reviewed"  # Often needs manual check  
fi  

# 14) Check Link Speed for eth0 (or main NIC)  
link_speed=$(ethtool eth0 2>/dev/null | grep "Speed" | awk '{print $2}')  
if [[ -n "$link_speed" ]]; then  
    record_check "Network Link Speed Detected" "passed"  
else  
    record_check "Network Link Speed Detected" "not_applicable"  
fi  
# 15) Test Email Alert (Automatic attempt)
if grep -q 'mail' /etc/aliases || grep -qi 'smtp' /etc/postfix/main.cf 2>/dev/null; then
    record_check "Test Email Alert" "passed"
else
    record_check "Test Email Alert" "not_reviewed"
fi

# 16) AlertManager UI Verification (Attempt automatic check for running web port)
if netstat -tuln | grep -q ':9093'; then
    record_check "AlertManager UI Verification" "passed"
else
    record_check "AlertManager UI Verification" "not_reviewed"
fi

# 17) Winbind Running Check (if domain joined)
if systemctl is-active --quiet winbind; then
    record_check "Winbind Running" "passed"
else
    record_check "Winbind Running" "not_applicable"
fi

# 18) Global MacOS Config Check (Look for related configs)
if grep -i 'macos' /etc/samba/smb.conf 2>/dev/null | grep -q 'global'; then
    record_check "Global MacOS Config" "passed"
else
    record_check "Global MacOS Config" "not_reviewed"
fi

# 19) File Sharing Permissions Check (Look for valid user/group misconfigurations)
if grep -i 'valid users' /etc/samba/smb.conf 2>/dev/null; then
    record_check "File Sharing Permissions" "passed"
else
    record_check "File Sharing Permissions" "not_reviewed"
fi

# 20) Windows ACL with Linux/MacOS Support (Attempt detection)
if grep -iq 'nt acl support = yes' /etc/samba/smb.conf 2>/dev/null; then
    record_check "Windows ACL Config" "passed"
else
    record_check "Windows ACL Config" "not_reviewed"
fi

# 21) Recalls or Power Harness Defect (Manual or external lookup required)
record_check "Hardware Recall Check" "not_reviewed"

# 22) SnapShield Last FireDrill Check (Look for logs or config entry if exists)
if [ -f /var/log/snapshield_firedrill.log ]; then
    record_check "SnapShield Last FireDrill" "passed"
else
    record_check "SnapShield Last FireDrill" "not_reviewed"
fi

# 23) Recommend Actions Summary (to be generated post-checks or flagged for manual summary)
record_check "Recommendation Summary" "not_reviewed"


check_results="${check_results%,}]"

cat <<EOF
{
  "filename": "$filename",
  "tool_version": "$tool_version",
  "platform": "$platform",
  "duration": "$duration",
  "start_time": "$start_time",
  "status": {
    "passed": $passed,
    "failed": $failed,
    "not_applicable": $not_applicable,
    "not_reviewed": $not_reviewed,
    "total_checks": $total_checks
  },
  "system": {
    "total_cores": $total_cores,
    "total_threads": $total_threads,
    "threads_in_use": $threads_in_use,
    "threads_free": $threads_free,
    "cores_in_use": $cores_in_use,
    "cores_free": $cores_free,
    "ram_usage_percent": $ram_usage,
    "ram_free_percent": $ram_free,
    "disk_usage_percent": $disk_usage,
    "disk_free_percent": $disk_free
  },
  "check_results": $check_results
}
EOF
