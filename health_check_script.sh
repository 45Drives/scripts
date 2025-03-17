#!/bin/bash

# Harmin Patel
# Date created: 10 March 2025
# 45Drives

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

# Disk usage (in use and free)
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
disk_free=$(awk "BEGIN {printf \"%.2f\", 100 - $disk_usage}")

# RAM usage (in use and free)
ram_usage=$(free -m | awk '/Mem:/ { printf "%.2f", $3/$2 * 100 }')
ram_free=$(awk "BEGIN {printf \"%.2f\", 100 - $ram_usage}")

# Total Cores & Threads
total_cores=$(lscpu | awk '/^Core\(s\) per socket:/ {print $4}')
sockets=$(lscpu | awk '/^Socket\(s\):/ {print $2}')
threads_per_core=$(lscpu | awk '/^Thread\(s\) per core:/ {print $4}')

# Ensure values exist, otherwise set defaults
if [[ -z "$total_cores" || -z "$sockets" ]]; then
    total_cores=$(nproc --all)
    sockets=1  
fi
if [[ -z "$threads_per_core" ]]; then
    threads_per_core=1  
fi

total_cores=$((total_cores * sockets))  # Adjust for multi-socket CPUs
total_threads=$((total_cores * threads_per_core))  # Adjust for SMT/Hyperthreading

# Get CPU usage percentage using mpstat
cpu_idle=$(mpstat 1 1 | awk '/Average/ {print $NF}')
cpu_usage=$(awk "BEGIN {printf \"%.2f\", 100 - $cpu_idle}")

# Estimate threads and cores in use based on CPU load
threads_in_use=$(awk "BEGIN {printf \"%.0f\", ($cpu_usage * $total_threads / 100)}")
threads_free=$((total_threads - threads_in_use))

cores_in_use=$(awk "BEGIN {printf \"%.0f\", ($cpu_usage * $total_cores / 100)}")
cores_free=$((total_cores - cores_in_use))

# Ensure values don't go negative
threads_in_use=$((threads_in_use < 0 ? 0 : threads_in_use))
threads_free=$((threads_free < 0 ? 0 : threads_free))
cores_in_use=$((cores_in_use < 0 ? 0 : cores_in_use))
cores_free=$((cores_free < 0 ? 0 : cores_free))

# Dummy test results (Replace with actual logic)
total_checks=500
passed=$(shuf -i 200-400 -n 1)
failed=$((total_checks - passed))
not_applicable=$(shuf -i 10-50 -n 1)

# Get Network Information
ip_address=$(hostname -I | awk '{print $1}')
default_gateway=$(ip route | grep default | awk '{print $3}')
network_speed="Unknown"  

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
  "network": {
    "ip_address": "$ip_address",
    "default_gateway": "$default_gateway",
    "network_speed": "$network_speed"
  }
}
EOF
