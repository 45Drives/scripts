#!/bin/bash

#Matthew Hutchinson <mhutchinson@45drives.com>

# Detect OS and install jq
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "ubuntu" ]]; then
        echo "Detected Ubuntu. Installing jq..."
        apt update && apt install -y jq
    elif [[ "$ID" == "rocky" || "$ID_LIKE" == *"rhel"* ]]; then
        echo "Detected Rocky Linux. Installing jq..."
        dnf install -y jq
    else
        echo "Unsupported OS. Please install jq manually."
        exit 1
    fi
else
    echo "/etc/os-release not found. Cannot detect OS."
    exit 1
fi

# Timestamp: YYYY-MM-DD_HH:MM
timestamp=$(date +"%Y-%m-%d_%H:%M")

# Output file with timestamp
output_file="rbd_report_${timestamp}.csv"

# Header for CSV
echo "Image,Size,Used Size,Watcher IPs" > "$output_file"

# Function to convert bytes to MB, GB, or TB
convert_bytes() {
    local bytes=$1
    if [[ "$bytes" -ge 1099511627776 ]]; then
        awk "BEGIN {printf \"%.2f TB\", $bytes/1099511627776}"
    elif [[ "$bytes" -ge 1073741824 ]]; then
        awk "BEGIN {printf \"%.2f GB\", $bytes/1073741824}"
    else
        awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}"
    fi
}

# Get list of pools using jq
pools=$(ceph osd lspools -f json | jq -r '.[].poolname')

for pool in $pools; do
    images=$(rbd ls "$pool")

    for image in $images; do
        full_image="$pool/$image"

        # Get image total size via rbd info
        size=$(rbd info "$full_image" --format json | jq -r '.size')
        size_human=$(convert_bytes "$size")

        # Get used size via rbd du
        used_bytes=$(rbd du "$full_image" --format json | jq -r '.images[0].used_size // 0')
        used_size_human=$(convert_bytes "$used_bytes")

        # Get watchers using jq
        status=$(rbd status "$full_image" --format json)
        watcher_ips=$(echo "$status" | jq -r 'if .watchers == null or (.watchers | length == 0) then "UNUSED" else .watchers | map(.address) | join("; ") end')

        # Append to CSV
        echo "$image,$size_human,$used_size_human,$watcher_ips" >> "$output_file"
    done
done

echo "Report saved to $output_file"
