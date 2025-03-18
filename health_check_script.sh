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
threads_in_use=$(awk "BEGIN {printf \"%.0f\", ($cpu_usage * $total_threads / 100)}")
threads_free=$((total_threads - threads_in_use))
cores_in_use=$(awk "BEGIN {printf \"%.0f\", ($cpu_usage * $total_cores / 100)}")
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
uptime_check=$(uptime -p)
if [[ -n "$uptime_check" ]]; then
    record_check "System Uptime" "passed"
else
    record_check "System Uptime" "failed"
fi

drive_hours=$(smartctl -A /dev/sda | awk '/Power_On_Hours/ {print $10}')
if [[ -n "$drive_hours" ]]; then
    record_check "Drive Age Available" "passed"
else
    record_check "Drive Age Available" "failed"
fi

if command -v zfs &> /dev/null; then
    zpool status &> /dev/null && record_check "ZFS Status" "passed" || record_check "ZFS Status" "failed"
elif command -v ceph &> /dev/null; then
    ceph -s &> /dev/null && record_check "Ceph Status" "passed" || record_check "Ceph Status" "failed"
else
    record_check "Storage System Check" "not_applicable"
fi

snapshots_enabled=$(zfs list -t snapshot 2>/dev/null | wc -l)
if [[ "$snapshots_enabled" -gt 0 ]]; then
    record_check "Snapshots Enabled" "passed"
else
    record_check "Snapshots Enabled" "failed"
fi

systemctl is-active --quiet alertmanager && record_check "AlertManager Running" "passed" || record_check "AlertManager Running" "failed"
ping -c 2 8.8.8.8 &> /dev/null && record_check "Network Connectivity" "passed" || record_check "Network Connectivity" "failed"

packet_errors=$(netstat -i | awk '{if ($5 > 0) print $0}')
if [[ -z "$packet_errors" ]]; then
    record_check "Packet Errors" "passed"
else
    record_check "Packet Errors" "failed"
fi

[[ -f /etc/systemd/system/iscsi.service ]] && record_check "iSCSI Fix Applied" "passed" || record_check "iSCSI Fix Applied" "not_applicable"

updates_available=$(apt list --upgradable 2>/dev/null | wc -l)
if [[ "$updates_available" -gt 1 ]]; then
    record_check "Updates Pending" "failed"
else
    record_check "Updates Pending" "passed"
fi

touch /tmp/testfile && echo "test" > /tmp/testfile && rm /tmp/testfile && record_check "Read/Write Test" "passed" || record_check "Read/Write Test" "failed"

# Close check_results JSON array
check_results="${check_results%,}]"

# FINAL JSON output
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
  "check_results": $check_results,
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
  }
}
EOF
