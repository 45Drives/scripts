#!/bin/bash

#Matthew Hutchinson <mhutchinson@45drives.com>

# Generate timestamp (YYYY-MM-DD_HH:MM)
timestamp=$(date +"%Y-%m-%d_%H:%M")

# Output file with timestamp
output_file="cephfs_client_report_${timestamp}.csv"
mount_point="/mnt/cephroot"
ceph_root=":/"

echo "🔍 Preparing environment..."

# Step 1: Ensure /mnt/cephroot exists
if [[ ! -d "$mount_point" ]]; then
    echo "📁 $mount_point does not exist. Creating it..."
    mkdir -p "$mount_point"
    echo "✅ Created $mount_point"
fi

# Step 2: Check if CephFS is mounted
if ! mountpoint -q "$mount_point"; then
    echo "🔗 $mount_point is not mounted. Attempting to mount CephFS..."
    mount -t ceph "$ceph_root" "$mount_point" -o name=admin
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to mount CephFS at $mount_point"
        exit 1
    fi
    echo "✅ Successfully mounted CephFS at $mount_point"
else
    echo "✅ CephFS is already mounted at $mount_point"
fi

# Step 3: Initialize CSV header
echo '"No","Mount Point Name","Pool Name","Protocol Type","Size","Used Space","Free Space","Client Name","CephFS Path"' > "$output_file"

i=1
declare -A seen_clients  # Track unique hostname:path combinations
all_clients=""

echo "📡 Gathering CephFS client info from all active MDSs..."
# Get all active MDS daemon names
mds_names=$(ceph fs status --format json | jq -r '.mdsmap[] | select(.state=="active") | .name')

if [[ -z "$mds_names" ]]; then
    echo "❌ No active MDS found!"
    exit 1
fi

# Collect all client entries from all MDS daemons
for mds in $mds_names; do
    echo "🔸 Querying mds.$mds ..."
    client_json=$(ceph tell mds."$mds" client ls --format json 2>/dev/null)
    if [[ -n "$client_json" && "$client_json" != "null" && "$client_json" != "[]" ]]; then
        all_clients+=$(echo "$client_json" | jq -c '.[]')$'\n'
    else
        echo "⚠️  No valid client data returned from mds.$mds (skipping)."
    fi
done

# Human-readable size formatter
human_readable() {
    bytes=$1
    awk -v b="$bytes" 'function human(x) {
        s="B KB MB GB TB PB"
        n=split(s,arr)
        for (i=n; i>1; i--) {
            if (x >= 1024^(i-1)) {
                printf "%.1f %s", x/(1024^(i-1)), arr[i]
                return
            }
        }
        printf "%d B", x
    }
    BEGIN {human(b)}'
}

# Deduplicate and write to CSV, skipping entries without client_metadata
echo "$all_clients" | sort | uniq | jq -c 'select(.client_metadata != null)' | while read -r entry; do
    hostname=$(echo "$entry" | jq -r '.client_metadata.hostname // "unknown"')
    cephfs_path=$(echo "$entry" | jq -r '.client_metadata.root // "/"')

    # Build unique key for hostname + path
    key="${hostname}:${cephfs_path}"
    if [[ -n "${seen_clients["$key"]}" ]]; then
        # Already seen, skip
        continue
    fi
    seen_clients["$key"]=1

    # Map to local path
    local_path="${mount_point}${cephfs_path}"
    [[ "$cephfs_path" == "/" ]] && local_path="$mount_point"

    # Get real pool name
    pool=$(getfattr -n ceph.dir.layout.pool "$local_path" --only-values 2>/dev/null)
    if [[ -z "$pool" ]]; then
        pool="cephfs"
    fi

    # Get size details
    if [[ -d "$local_path" ]]; then
        max_bytes=$(getfattr -n ceph.quota.max_bytes "$local_path" --only-values 2>/dev/null)
        rbytes=$(getfattr -n ceph.dir.rbytes "$local_path" --only-values 2>/dev/null)

        if [[ -n "$max_bytes" && "$max_bytes" -ne 0 ]]; then
            size="$max_bytes"
            used="${rbytes:-0}"
            free=$((max_bytes - used))
        else
            df_info=$(df -B1 "$local_path" 2>/dev/null | tail -1)
            size=$(echo "$df_info" | awk '{print $2}')
            used=$(echo "$df_info" | awk '{print $3}')
            free=$(echo "$df_info" | awk '{print $4}')
        fi

        size_h=$(human_readable "$size")
        used_h=$(human_readable "$used")
        free_h=$(human_readable "$free")
    else
        size_h="N/A"
        used_h="N/A"
        free_h="N/A"
    fi

    # Mount Point Name: just the last part
    mp_name=$(basename "$local_path")
    [[ "$mp_name" == "" || "$mp_name" == "/" ]] && mp_name="/"

    echo "\"$i\",\"$mp_name\",\"$pool\",\"cephfs\",\"$size_h\",\"$used_h\",\"$free_h\",\"$hostname\",\"$cephfs_path\"" >> "$output_file"
    ((i++))
done

echo "✅ Report generated: $output_file"
