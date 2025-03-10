#!/bin/bash

# Harmin Patel, March 2025
# 45Drives

# Output JSON file
json_file="/var/log/config_summary.json"

# Get system information dynamically
filename="system_report.json"
tool_version="1.0"
platform=$(lsb_release -d | awk -F'\t' '{print $2}' || echo "Unknown OS")
start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get the number of checks (Replace with actual logic)
total_checks=500  # Example: Set dynamically based on checks performed
passed=$(shuf -i 200-400 -n 1)  # Random success count (Replace with real logic)
failed=$((total_checks - passed))  # Failed = total - passed
not_applicable=$(shuf -i 10-50 -n 1)  # Example: Get non-applicable cases

# Capture the script duration dynamically
start_timestamp=$(date +%s)
# Simulate process (Replace with actual system scans)
sleep 2  # Simulating script execution time
end_timestamp=$(date +%s)
duration=$(echo "$end_timestamp - $start_timestamp" | bc)  # Compute duration

# Get CPU and RAM info dynamically
total_cores=$(nproc)
total_threads=$(lscpu | awk '/^Thread\(s\) per core:/ {print $NF}')
cores_in_use=$(ps -eo psr | tail -n +2 | sort -u | wc -l)
threads_in_use=$(ps -eo psr | tail -n +2 | wc -l)
cores_free=$((total_cores - cores_in_use))
ram_usage=$(free -m | awk '/Mem:/ { printf "%.2f", $3/$2 * 100 }')

# Get storage usage
disk_usage=$(df -h --total | grep 'total' | awk '{print $5}' | sed 's/%//')

# Get network information
ip_address=$(hostname -I | awk '{print $1}')
default_gateway=$(ip route | grep default | awk '{print $3}')
network_speed=$(ethtool $(ip route | awk '/default/ {print $5}') 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "Unknown")

# Generate JSON output
cat <<EOF > $json_file
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
    "total_checks": $total_checks
  },
  "system": {
    "total_cores": $total_cores,
    "total_threads": $total_threads,
    "cores_in_use": $cores_in_use,
    "threads_in_use": $threads_in_use,
    "cores_free": $cores_free,
    "ram_usage_percent": $ram_usage,
    "disk_usage_percent": $disk_usage
  },
  "network": {
    "ip_address": "$ip_address",
    "default_gateway": "$default_gateway",
    "network_speed": "$network_speed"
  }
}
EOF

echo "JSON report generated at: $json_file"