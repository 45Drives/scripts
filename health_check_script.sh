#!/bin/bash

# Generate system information
filename="$(hostname)_report.json"  
if command -v zfs &> /dev/null; then
    tool_version=$(zfs --version | head -n 1 | awk '{print $2}' | cut -d'-' -f1)
elif command -v lsb_release &> /dev/null; then
    tool_version=$(uname -r | cut -d'-' -f1)  
else
    tool_version="Unknown"
fi
platform=$(lsb_release -d | awk -F'\t' '{print $2}')
start_time=$(date -u +"%Y-%m-%dT%H:%M:%S")

# Dummy test results (Replace with actual logic)
total_checks=500
passed=$(shuf -i 200-400 -n 1)
failed=$((total_checks - passed))
not_applicable=$(shuf -i 10-50 -n 1)
duration=$(shuf -i 1-10 -n 1)  # Simulating a process time

# Get CPU and RAM info
total_cores=$(nproc)
ram_usage=$(free -m | awk '/Mem:/ { printf "%.2f", $3/$2 * 100 }')
disk_usage=$(df -h --total | grep 'total' | awk '{print $5}' | sed 's/%//')

# Get Network Information
ip_address=$(hostname -I | awk '{print $1}')
default_gateway=$(ip route | grep default | awk '{print $3}')
network_speed="Unknown"  # Placeholder (use ethtool if needed)

# Print JSON directly to the output
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
    "total_checks": $total_checks
  },
  "system": {
    "total_cores": $total_cores,
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
