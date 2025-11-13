#!/bin/bash

# Harmin Patel, Zachary Perry, Curtis LeBlanc, Mitchell Hall
# Date created: 10 March 2025
# 45Drives
# Rev 0.7.0
timestamp=$(date +"%Y%m%d_%H%M%S")
out_dir="/tmp/health-check_$timestamp"
mkdir -p "$out_dir"
mkdir -p "$out_dir/ceph"
mkdir -p "$out_dir/ceph/device_health"
ctdb_dir="$out_dir/ctdb"
mkdir -p "$ctdb_dir"
logfile="$out_dir/ctdb/report.log"
output_file="config_summary_$(date +'%Y%m%d_%H%M%S').txt"
warnings=""
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

# Extract valid remote hostnames from /etc/hosts
remote_hosts=$(awk '$1 ~ /^[0-9]+(\.[0-9]+){3}$/ && $2 !~ /localhost/ {print $2}' /etc/hosts | sort -u)

if [ -z "$remote_hosts" ]; then
    remote_hosts=$(hostname)
fi

collect_from_all_hosts() {
    local cmd="$1"
    local file_prefix="$2"
    local out_file="$out_dir/${file_prefix}.txt"

    > "$out_file"

    for host in $remote_hosts; do
        if [ "$host" = "$(hostname)" ]; then
            # Local host
            echo "[$(hostname)]" >> "$out_file"
            eval "$cmd" >> "$out_file" 2>&1
        else
            # Remote host
            if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "true" 2>/dev/null; then
                echo "[$host]" >> "$out_file"
                ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "$cmd" >> "$out_file" 2>&1
            else
                echo "[$host]" >> "$out_file"
                echo "" >> "$out_file"
            fi
        fi
        echo "" >> "$out_file"
    done
}

# Get the current tuned profile
collect_from_all_hosts '
if ! command -v tuned-adm &> /dev/null; then
    echo "Tuned is not installed."
else
    tuned-adm active
fi
' "tuned"

# Get the current SELinux mode
collect_from_all_hosts '
if ! command -v sestatus &> /dev/null; then
    echo "sestatus not found."
else
    sestatus
    mode=$(sestatus 2>/dev/null | awk "/Current mode:/ {print \$3}")
    if [[ "$mode" == "enforcing" ]]; then
        echo "WARNING: SELinux is in enforcing mode. This may interfere with some operations."
    fi
fi
' "selinux"

# RAM usage
collect_from_all_hosts "free -h" "memory"

# Swap usage
collect_from_all_hosts "free -m && echo && used_swap=\$(free -m | awk '/Swap:/ {print \$3}') && [ \"\$used_swap\" -gt 500 ] && echo WARNING: High swap usage detected" "swap"

# SMART Drive Summary
collect_from_all_hosts '
for i in $(ls /dev | grep -i "^sd" | grep -v "[0-9]$"); do
    echo -e "\nDevice: /dev/$i"
    echo -n "Slot: "
    if [[ -d /dev/disk/by-vdev ]]; then
        ls -l /dev/disk/by-vdev/ | grep -wi "$i" | awk "{print \$9}" || echo "Not labeled"
    else
        echo "Not labeled"
    fi
    smartctl -x /dev/$i 2>/dev/null | grep -iE "serial number|reallocated_sector_ct|power_cycle_count|reported_uncorrect|command_timeout|offline_uncorrectable|current_pending_sector"
done
' "smartctl"

# Drive Age
collect_from_all_hosts '
for i in $(ls /dev | grep -i "^sd[a-z]$"); do
    echo -e "\nDevice: /dev/$i"
    power_on_hours=$(smartctl -A /dev/$i 2>/dev/null | awk "/Power_On_Hours/ {print \$10}")
    if [[ -n "$power_on_hours" ]]; then
        echo "Power-On Hours: $power_on_hours"
    else
        echo "Power-On Hours not available."
    fi
done
' "drive_age"

# Snapshots (by dataset)
collect_from_all_hosts '
datasets=$(zfs list -H -o name -t filesystem,volume 2>/dev/null)
for ds in $datasets; do
    echo "Dataset: $ds"
    zfs list -H -t snapshot -o name -s creation -r "$ds" 2>/dev/null | tail -n 25
done
' "zfs_dataset_snapshots"

# Snapshots
collect_from_all_hosts '
zpools=$(zpool list -H -o name 2>/dev/null)
for pool in $zpools; do
    echo "Pool: $pool"
    zfs list -H -t snapshot -o name -s creation -r "$pool" 2>/dev/null | tail -n 25
done
' "zfs_snapshots"

# NIC packet errors
collect_from_all_hosts '
for iface in $(ls /sys/class/net); do
    if [ "$iface" = "lo" ] || [ ! -d "/sys/class/net/$iface/statistics" ]; then
        continue
    fi
    rx=$(cat "/sys/class/net/$iface/statistics/rx_errors" 2>/dev/null || echo "NA")
    tx=$(cat "/sys/class/net/$iface/statistics/tx_errors" 2>/dev/null || echo "NA")
    echo "$iface: RX $rx  TX $tx"
done
' "packet_errors"

# ZFS
collect_from_all_hosts '
echo "# ZFS Status"
zpool status 2>/dev/null
echo "# ZFS Failed Drives Detected"
zpool status 2>/dev/null | grep -iE "DEGRADED|FAULTED|OFFLINE" || echo "No failed drives detected"
echo "# ZFS Autotrim Status"
zpool get autotrim 2>/dev/null
echo "# ZFS Pool Capacity"
zpool list -H -o name,capacity 2>/dev/null
' "zfs_summary"

# ZFS: Pool Errors
collect_from_all_hosts '
echo "# ZFS Pool Errors"
zpool status 2>/dev/null | grep -E "errors:|read:|write:|cksum:"
' "zfs_pool_errors"

# Additional files:
collect_from_all_hosts "uptime" "uptime"
collect_from_all_hosts "uname -a" "kernel_version"
collect_from_all_hosts "lspci -nnk" "pci_devices"
collect_from_all_hosts "ss -tuln" "open_ports"
collect_from_all_hosts "systemctl --failed" "failed_units"
collect_from_all_hosts "systemd-analyze" "boot_time"
collect_from_all_hosts "ip route show default" "default_route"
collect_from_all_hosts "cat /etc/os-release" "linux_distribution"
collect_from_all_hosts "last reboot" "reboot_history"
collect_from_all_hosts "systemctl status winbind" "winbind_status"
collect_from_all_hosts "apt list --upgradable" "updates"

ceph -s > "$out_dir/ceph_status.txt" 2>/dev/null

collect_from_all_hosts '
systemctl status alertmanager --no-pager --lines=20 2>/dev/null \
  | sed "/\/usr\/libexec\/podman\/conmon/ s/ .*/ .../" \
  || echo "alertmanager service not found"
' "alertmanager_status"

# Config Files
collect_from_all_hosts "cat /etc/samba/smb.conf 2>/dev/null || echo '/etc/samba/smb.conf not found'" "samba_conf"
collect_from_all_hosts "cat /etc/exports.d/cockpit-file-sharing.exports 2>/dev/null || echo '/etc/exports.d/cockpit-file-sharing.exports not found'" "nfs_exports"
collect_from_all_hosts "cat /etc/scst.conf 2>/dev/null || echo '/etc/scst.conf not found'" "iscsi_conf"

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

# Ceph commands
ceph status > "$out_dir/ceph/status" 2>/dev/null
ceph -v > "$out_dir/ceph/version" 2>/dev/null
ceph versions > "$out_dir/ceph/versions" 2>/dev/null
ceph features > "$out_dir/ceph/features" 2>/dev/null
ceph fsid > "$out_dir/ceph/fsid" 2>/dev/null
collect_from_all_hosts "cat /etc/ceph/ceph.conf 2>/dev/null || echo '/etc/ceph/ceph.conf not found'" "ceph_conf"
ceph config dump > "$out_dir/ceph/config" 2>/dev/null
ceph health > "$out_dir/ceph/health_summary" 2>/dev/null
ceph health detail > "$out_dir/ceph/health_detail" 2>/dev/null
ceph report > "$out_dir/ceph/health_report" 2>/dev/null
ceph df > "$out_dir/ceph/health_df" 2>/dev/null
if grep -qE 'HEALTH_WARN|HEALTH_ERR' "$out_dir/ceph/health_detail"; then
    echo "Ceph cluster has warnings or errors:"
    cat "$out_dir/ceph/health_detail"
fi
if command -v lsb_release &> /dev/null; then
    collect_from_all_hosts "lsb_release -a" "lsb_release"
fi
ceph mon stat > "$out_dir/ceph/mon_stat" 2>/dev/null
ceph mon dump > "$out_dir/ceph/mon_dump" 2>/dev/null
ceph mon getmap -o "$out_dir/ceph/mon_map" 2>/dev/null
ceph mon metadata > "$out_dir/ceph/mon_metadata" 2>/dev/null
ceph osd tree > "$out_dir/ceph/osd_tree" 2>/dev/null
ceph osd df > "$out_dir/ceph/osd_df" 2>/dev/null
ceph osd dump > "$out_dir/ceph/osd_dump" 2>/dev/null
ceph osd stat > "$out_dir/ceph/osd_stat" 2>/dev/null
ceph osd getcrushmap -o "$out_dir/ceph/osd_crushmap" 2>/dev/null
ceph osd getmap -o "$out_dir/ceph/osd_map" 2>/dev/null
ceph osd metadata > "$out_dir/ceph/osd_metadata" 2>/dev/null
ceph osd perf > "$out_dir/ceph/osd_perf" 2>/dev/null
ceph pg stat > "$out_dir/ceph/pg_stat" 2>/dev/null
ceph pg dump > "$out_dir/ceph/pg_dump" 2>/dev/null
ceph pg dump_stuck > "$out_dir/ceph/pg_dump_stuck" 2>/dev/null
ceph mds metadata > "$out_dir/ceph/mds_metadata" 2>/dev/null
ceph mds dump > "$out_dir/ceph/mds_dump" 2>/dev/null
ceph mds stat > "$out_dir/ceph/mds_stat" 2>/dev/null
ceph fs dump > "$out_dir/ceph/fs_dump" 2>/dev/null
ceph fs status > "$out_dir/ceph/fs_status" 2>/dev/null
ceph device check-health > "$out_dir/ceph/check-health" 2>/dev/null
ceph device ls > "$out_dir/ceph/device_ls" 2>/dev/null

# Per-device health metrics
if command -v ceph &> /dev/null && ceph device ls &> /dev/null; then
    for dev in $(ceph device ls 2>/dev/null | awk '{print $1}' | grep -v NAME); do
        osd_id=$(ceph osd metadata -f json 2>/dev/null | jq -r ".[] | select(.device_ids[]? == \"$dev\") | .id" | head -n 1)

        if [[ -n "$osd_id" && "$osd_id" != "null" ]]; then
            filename="osd.$osd_id.txt"
        else
            safe_dev=$(echo "$dev" | tr '/ ' '__')
            filename="device_health_$safe_dev.txt"
        fi

        ceph device get-health-metrics "$dev" > "$out_dir/ceph/device_health/$filename" 2>/dev/null
    done
fi

# CTDB detection and gathering
for host in $remote_hosts; do
  echo "[$host]" | tee -a "$logfile"
  ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" 'systemctl is-active --quiet ctdb' 2>/dev/null

  if [ $? -eq 0 ]; then
    echo "CTDB is running on $host. Gathering status..." | tee -a "$logfile"

    # Save CTDB output to file
    {
      echo "===== ctdb status ($host) ====="
      ssh "$host" 'ctdb status' 2>&1
      echo

      echo "===== ctdb ip ($host) ====="
      ssh "$host" 'ctdb ip' 2>&1
    } > "$ctdb_dir/$host.txt"

  else
    echo "CTDB not running on $host." | tee -a "$logfile"
  fi
done

# Tarball folder
if tar -czf "$out_dir.tar.gz" -C "$(dirname "$out_dir")" "$(basename "$out_dir")"; then
  rm -rf "$out_dir"
fi

echo "=== SMART Health Warnings $(date) ==="

for dev in $(ls /dev | grep -E "^sd[a-z]$"); do
    device="/dev/$dev"

    # Collect info
    serial=$(smartctl -i "$device" 2>/dev/null | grep -i "Serial Number" | awk -F: '{print $2}' | xargs)
    smartout=$(smartctl -a "$device" 2>/dev/null)

    # Quick health assessment
    health=$(echo "$smartout" | grep -i "SMART overall-health" | awk -F: '{print $2}' | xargs)

    # Extract key values
    realloc=$(echo "$smartout" | grep -i "Reallocated_Sector_Ct" | awk '{print $10}')
    pending=$(echo "$smartout" | grep -i "Current_Pending_Sector" | awk '{print $10}')
    offline_uncorr=$(echo "$smartout" | grep -i "Offline_Uncorrectable" | awk '{print $10}')
    crc=$(echo "$smartout" | grep -i "UDMA_CRC_Error_Count" | awk '{print $10}')
    reserved=$(echo "$smartout" | grep -i "Available_Reservd_Space" | awk '{print $10}')

    # Print warnings only
    if [[ "$health" == "FAILED" ]]; then
        echo "[$device | $serial] SMART overall health test FAILED!"
    fi
    if [[ -n "$realloc" && "$realloc" -gt 0 ]]; then
        echo "[$device | $serial] Reallocated sectors detected: $realloc"
    fi
    if [[ -n "$pending" && "$pending" -gt 0 ]]; then
        echo "[$device | $serial] Pending sectors detected: $pending"
    fi
    if [[ -n "$offline_uncorr" && "$offline_uncorr" -gt 0 ]]; then
        echo "[$device | $serial] Offline uncorrectable sectors detected: $offline_uncorr"
    fi
    if [[ -n "$crc" && "$crc" -gt 0 ]]; then
        echo "[$device | $serial] CRC interface errors detected: $crc"
    fi
    if [[ -n "$reserved" && "$reserved" -lt 100 ]]; then
        echo "[$device | $serial] SSD spare blocks low: $reserved%"
    fi
done

# Check for hardware-related problems in dmesg output

# List of keywords that usually indicate hardware issues
keywords=("I/O error" "failed" "hardware error" "buffer I/O" "uncorrectable" "CRC error" "sense key" "end_request" "link reset" "error handler" "device offlined" "S.M.A.R.T. error")

# Get recent dmesg output
dmesg_output=$(dmesg --ctime --color=never 2>/dev/null)

# Initialize flag
found_issue=false

# Search for each keyword (case-insensitive)
for kw in "${keywords[@]}"; do
    if echo "$dmesg_output" | grep -i -q "$kw"; then
        echo "⚠️  Possible hardware issue detected: \"$kw\" found in dmesg logs"
        found_issue=true
    fi
done

# If no issues found, print confirmation
if [ "$found_issue" = false ]; then
    echo "✅ No hardware-related problems detected in dmesg output."
else
    echo "🔍 Review 'dmesg' output above for details. Recommend checking SMART data or system health."
fi


if systemctl is-active --quiet zfs.target; then
    zpool_parse_script="zpool_parse.py"
    if [ ! -f "$zpool_parse_script" ]; then
      echo "zpool_parse.py not found. Attempting to download..."
      curl -o "$zpool_parse_script" https://raw.githubusercontent.com/45Drives/scripts/main/parse_zpool.py
      if [ ! -f "$zpool_parse_script" ]; then
        echo "Error: Unable to download zpool_parse.py. The script cannot continue."
        echo "Please download zpool_parse.py manually from https://raw.githubusercontent.com/45Drives/scripts/main/parse_zpool.py and place it in the working directory."
        exit 1
      fi
    fi

    # Function to get raw ZFS pool status
    get_raw_zpool_status() {
      echo "Raw ZFS Pool Status:" >> $output_file
      zpool status >> $output_file
      echo "" >> $output_file
      echo "Raw ZFS Pool Status:"
      echo ""
    }

    # Function to get ZFS version
    get_zfs_version() {
      echo "ZFS Version:" >> $output_file
      zfs version | head -n 1 >> $output_file
      echo "" >> $output_file
    }

    # Function to get ZFS ARC stats
    get_zfs_arc_stats() {
      echo "ZFS ARC Stats:" >> $output_file
      arc_hits=$(awk '/^hits / {print $3}' /proc/spl/kstat/zfs/arcstats)
      arc_misses=$(awk '/^misses / {print $3}' /proc/spl/kstat/zfs/arcstats)
      total_accesses=$((arc_hits + arc_misses))

      if [ $total_accesses -gt 0 ]; then
        arc_hit_ratio=$(awk "BEGIN {printf \"%.2f\", ($arc_hits/$total_accesses)*100}")
        arc_miss_ratio=$(awk "BEGIN {printf \"%.2f\", ($arc_misses/$total_accesses)*100}")
      else
        arc_hit_ratio=0
        arc_miss_ratio=0
      fi

      echo "ARC Hits: $arc_hits" >> $output_file
      echo "ARC Misses: $arc_misses" >> $output_file
      echo "ARC Hit Ratio: $arc_hit_ratio%" >> $output_file
      echo "ARC Miss Ratio: $arc_miss_ratio%" >> $output_file
      echo "" >> $output_file
    }

    # Function to check dataset configurations
    get_datasets_info() {
      echo "Datasets Info:" >> $output_file
      zpools=$(zpool list -H -o name)
      for pool in $zpools; do
        datasets=$(zfs list -H -o name -r $pool)
        if [ -z "$datasets" ]; then
          echo "No datasets found for pool: $pool" >> $output_file
        else
          for dataset in $datasets; do
            echo "Dataset: $dataset" >> $output_file
            compression=$(zfs get -H -o value compression $dataset)
            sync=$(zfs get -H -o value sync $dataset)
            xattr=$(zfs get -H -o value xattr $dataset)
            aclinherit=$(zfs get -H -o value aclinherit $dataset)
            acltype=$(zfs get -H -o value acltype $dataset)
            echo "Compression: $compression" >> $output_file
            if [ "$compression" == "off" ]; then
              warning_msg="Warning: Dataset $dataset has compression disabled. Enabling lz4 compression allows for great space savings, and in many workloads, actually improves performance. If this workload is 100% video, you may want to keep it disabled, otherwise please consider enabling it"
              echo -e "\e[43m\e[30m$warning_msg\e[0m" >> $output_file
              warnings+="\n$warning_msg"
            fi
            echo "Sync: $sync" >> $output_file
            if [ "$sync" == "disabled" ]; then
              warning_msg="Warning: Dataset $dataset has sync disabled completely. This means clients that use sync IO will be getting an acknowledgement before the data is safely stored. This can make sense for some workloads, but please make sure this is proper and intentional before going forward"
              echo -e "\e[43m\e[30m$warning_msg\e[0m" >> $output_file
              warnings+="\n$warning_msg"
            fi
            echo "xattr: $xattr" >> $output_file
            echo "aclinherit: $aclinherit" >> $output_file
            echo "acltype: $acltype" >> $output_file
            if [ -f /etc/redhat-release ]; then
              aclmode=$(zfs get -H -o value aclmode $dataset)
              echo "aclmode: $aclmode" >> $output_file
            fi
            echo "" >> $output_file
          done
        fi
        echo "" >> $output_file
      done
    }

    # Function to check for snapshots
    check_snapshots() {
      echo "Snapshots Info:" >> $output_file
      zpools=$(zpool list -H -o name)
      for pool in $zpools; do
        echo "Pool: $pool" >> $output_file
        snapshots=$(zfs list -H -t snapshot -o name -r $pool)
        if [ -z "$snapshots" ]; then
          echo "No snapshots found for pool: $pool" >> $output_file
        else
          for snapshot in $snapshots; do
            echo "Snapshot: $snapshot" >> $output_file
          done
        fi
        echo "" >> $output_file
      done
    }

    # ZFS VDEV Checking Functions
    get_zpool_status() {
      json_output=$(python3 zpool_parse.py)

      pool_name=$(echo "$json_output" | jq -r 'keys[]')
      state=$(echo "$json_output" | jq -r --arg pool "$pool_name" '.[$pool].state')
      data_vdevs=$(echo "$json_output" | jq -r --arg pool "$pool_name" '.[$pool].data_vdevs')
      helper_vdevs=$(echo "$json_output" | jq -r --arg pool "$pool_name" '.[$pool].helper_vdevs')

      vdev_types=()
      vdev_disk_counts=()

      while IFS= read -r vdev; do
        vdev_type=$(echo "$vdev" | jq -r '.type' | awk '{print $1}')
        vdev_disks=$(echo "$vdev" | jq -r '.disks | length')
        vdev_types+=("$vdev_type")
        vdev_disk_counts+=("$vdev_disks")
      done < <(echo "$data_vdevs" | jq -c '.[]')

      echo "Data VDEVs:" >> $output_file
      for i in "${!vdev_types[@]}"; do
        echo "Type: ${vdev_types[$i]}, Disks: ${vdev_disk_counts[$i]}" >> $output_file
      done

      normalized_vdev_types=()
      for vdev_type in "${vdev_types[@]}"; do
        normalized_vdev_type=$(echo "$vdev_type" | awk -F'-' '{print $1}')
        normalized_vdev_types+=("$normalized_vdev_type")
      done

      unique_vdev_types=($(echo "${normalized_vdev_types[@]}" | tr ' ' '\n' | sort | uniq))

      if [ "${#unique_vdev_types[@]}" -gt 1 ]; then
        warning_msg="Warning: The ZPOOL has mismatched VDEVs consisting of different types. Rebuild the pool to reconfigure properly"
        echo -e "\e[41m\e[30m$warning_msg\e[0m" >> $output_file
        warnings+="\n$warning_msg"
        echo "VDEV Types and Counts:" >> $output_file
        echo "Pool: $pool_name" >> $output_file
        for i in "${!vdev_types[@]}"; do
          echo "VDEV: ${vdev_types[$i]} has ${vdev_disk_counts[$i]} disks" >> $output_file
        done
      fi

      for vdev_type in "${unique_vdev_types[@]}"; do
        disk_counts=()
        for i in "${!normalized_vdev_types[@]}"; do
          if [ "${normalized_vdev_types[$i]}" == "$vdev_type" ]; then
            disk_counts+=("${vdev_disk_counts[$i]}")
          fi
        done

        unique_disk_counts=($(echo "${disk_counts[@]}" | tr ' ' '\n' | sort | uniq))

        if [ "${#unique_disk_counts[@]}" -gt 1 ]; then
          warning_msg="Warning: VDEVS of type $vdev_type in this pool don't have matching number of disks. Rebuild with proper configuration"
          echo -e "\e[41m\e[30m$warning_msg\e[0m" >> $output_file
          warnings+="\n$warning_msg"
          echo "VDEV Types and Counts:" >> $output_file
          echo "Pool: $pool_name" >> $output_file
          for i in "${!normalized_vdev_types[@]}"; do
            if [ "${normalized_vdev_types[$i]}" == "$vdev_type" ]; then
              echo "VDEV: ${vdev_types[$i]} has ${vdev_disk_counts[$i]} disks" >> $output_file
            fi
          done
        fi
      done

      declare -A helper_vdev_map
      helper_vdev_map=( ["special"]="No proper redundancy detected in helper VDEV SPECIAL. To ensure data integrity, add a mirror to this device." ["logs"]="No proper redundancy detected in helper VDEV LOG. To ensure data integrity, add a mirror to this device." ["cache"]="Cache vdev's do not require redundancy. You may want to consider rebuilding with single disk, and re-use remaining disks elsewhere" )

      while IFS= read -r helper_vdev; do
        helper_vdev_type=$(echo "$helper_vdev" | jq -r '.type' | awk '{print $1}')
        vdevs=$(echo "$helper_vdev" | jq -r '.vdevs[]')

        echo "Helper VDEV Type: $helper_vdev_type" >> $output_file

        if [ "$helper_vdev_type" == "special" ] || [ "$helper_vdev_type" == "logs" ]; then
          has_mirror=false
          while IFS= read -r vdev; do
            vdev_type=$(echo "$vdev" | jq -r '.type' | awk -F'-' '{print $1}')
            echo "  VDEV Type in $helper_vdev_type: $vdev_type" >> $output_file
            if [[ "$vdev_type" == "mirror" ]]; then
              has_mirror=true
              break
            fi
          done < <(echo "$vdevs" | jq -c '.')

          if [ "$has_mirror" = false ]; then
            warning_msg="Warning: ${helper_vdev_map[$helper_vdev_type]}"
            echo -e "\e[41m\e[30m$warning_msg\e[0m" >> $output_file
            warnings+="\n$warning_msg"
          fi
        elif [ "$helper_vdev_type" == "cache" ]; then
          has_redundancy=false
          while IFS= read -r vdev; do
            vdev_type=$(echo "$vdev" | jq -r '.type' | awk -F'-' '{print $1}')
            echo "  VDEV Type in $helper_vdev_type: $vdev_type" >> $output_file
            if [[ "$vdev_type" == "mirror" || "$vdev_type" =~ raidz[1-3] ]]; then
              has_redundancy=true
              break
            fi
          done < <(echo "$vdevs" | jq -c '.')

          if [ "$has_redundancy" = true ]; then
            warning_msg="Warning: ${helper_vdev_map[$helper_vdev_type]}"
            echo -e "\e[43m\e[30m$warning_msg\e[0m" >> $output_file
            warnings+="\n$warning_msg"
          fi
        fi
      done < <(echo "$helper_vdevs" | jq -c '.[]')
    }

    # Run functions and output to screen and file
    get_raw_zpool_status
    get_zpool_status
    get_zfs_version
    get_zfs_arc_stats
    get_datasets_info
    check_snapshots
else
    echo "zfs.target not running on this host."
fi

# Function to get network bond information
get_bond_info() {
  bonds=$(ls /proc/net/bonding 2>/dev/null)
  if [ -z "$bonds" ]; then
    warning_msg="Warning: There is no bond created, all network traffic will be flowing through a single network interface with no redundancy. If this is acceptable and intentional, you may continue. Otherwise, go back and create the bond. Once complete, re-run this script"
    echo -e "\e[43m\e[30m$warning_msg\e[0m" >> $output_file
    warnings+="\n$warning_msg"
  else
    for bond in $bonds; do
      echo "Bond: $bond" >> $output_file
      bond_type=$(grep "Bonding Mode" /proc/net/bonding/$bond | awk -F: '{print $2}')
      link_speed=$(ethtool $bond | grep "Speed:" | awk '{print $2}')
      ip_addr=$(ip -o -f inet addr show $bond | awk '{print $4}')
      gw=$(ip route show dev $bond | grep default | awk '{print $3}')
      netmask=$(ip -o -f inet addr show $bond | awk '{print $4}' | cut -d/ -f2)
      echo "Type: $bond_type" >> $output_file
      echo "Link Speed: $link_speed" >> $output_file
      echo "IP Address: $ip_addr" >> $output_file
      echo "Default Gateway: $gw" >> $output_file
      echo "Subnet Mask: $netmask" >> $output_file

      # Check if the default gateway is within the subnet range
      if [ -n "$gw" ]; then
        IFS='/' read -r ip subnet <<< "$ip_addr"
        IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
        IFS='.' read -r g1 g2 g3 g4 <<< "$gw"

        # Calculate the network address
        network=$(( (i1 << 24 | i2 << 16 | i3 << 8 | i4) & ((1 << 32) - (1 << (32 - subnet))) ))
        gateway=$(( g1 << 24 | g2 << 16 | g3 << 8 | g4 ))

        if (( network != (gateway & ((1 << 32) - (1 << (32 - subnet)) )) )); then
          warning_msg="Warning: $bond has an IP address set for a default gateway that does not fall within its subnet range. Verify the proper default gateway and reconfigure."
          echo -e "\e[41m\e[30m$warning_msg\e[0m" >> $output_file
          warnings+="\n$warning_msg"
        fi
      fi

      interfaces=$(grep "Slave Interface" /proc/net/bonding/$bond | awk '{print $3}')
      for iface in $interfaces; do
        driver=$(ethtool -i $iface | grep "driver:" | awk '{print $2}')
        version=$(ethtool -i $iface | grep "version:" | awk '{print $2}')
        echo "Interface: $iface" >> $output_file
        echo "Driver: $driver" >> $output_file
        echo "Driver Version: $version" >> $output_file
      done
      echo "" >> $output_file
    done
  fi
}

# Function to get network interface information and check for default gateway within subnet
get_interface_info() {
  interfaces=$(ls /sys/class/net | grep -v 'lo\|bond')
  for iface in $interfaces; do
    if [ -d "/sys/class/net/$iface" ] && [ -e "/sys/class/net/$iface/carrier" ] && [ $(cat /sys/class/net/$iface/carrier) -eq 1 ]; then
      link_speed=$(ethtool $iface | grep "Speed:" | awk '{print $2}')
      ip_addr=$(ip -o -f inet addr show $iface | awk '{print $4}')
      gw=$(ip route show dev $iface | grep default | awk '{print $3}')
      netmask=$(ip -o -f inet addr show $iface | awk '{print $4}' | cut -d/ -f2)
      driver=$(ethtool -i $iface | grep "driver:" | awk '{print $2}')
      version=$(ethtool -i $iface | grep "version:" | awk '{print $2}')
      echo "Interface: $iface" >> $output_file
      echo "Link Speed: $link_speed" >> $output_file
      echo "IP Address: $ip_addr" >> $output_file
      echo "Default Gateway: $gw" >> $output_file
      echo "Subnet Mask: $netmask" >> $output_file
      echo "Driver: $driver" >> $output_file
      echo "Driver Version: $version" >> $output_file
      echo "" >> $output_file

      # Check if the default gateway is within the subnet range
      if [ -n "$gw" ]; then
        IFS='/' read -r ip subnet <<< "$ip_addr"
        IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
        IFS='.' read -r g1 g2 g3 g4 <<< "$gw"

        # Calculate the network address
        network=$(( (i1 << 24 | i2 << 16 | i3 << 8 | i4) & ((1 << 32) - (1 << (32 - subnet))) ))
        gateway=$(( g1 << 24 | g2 << 16 | g3 << 8 | g4 ))

        if (( network != (gateway & ((1 << 32) - (1 << (32 - subnet)) )) )); then
          warning_msg="Warning: $iface has an IP address set for a default gateway that does not fall within its subnet range. Verify the proper default gateway and reconfigure."
          echo -e "\e[41m\e[30m$warning_msg\e[0m" >> $output_file
          warnings+="\n$warning_msg"
        fi
      fi
    fi
  done
}

# Function to get the current active tuned profile
get_tuned_profile() {
  echo "Tuned Profile:" >> $output_file
  current_profile=$(tuned-adm active | grep "Current active profile:" | awk -F: '{print $2}' | xargs)
  echo "Current active profile: $current_profile" >> $output_file
  if [[ "$current_profile" != "network-latency" && "$current_profile" != "throughput-performance" ]]; then
    warning_msg="Warning: It is highly recommended to use throughput-performance or network-latency as your tuned profile, as these make sure the CPU remains outside of lower sleep states, and improves responsiveness and performance. If this server is running VM's or databases over the network, please select network-latency. If this server is acting as a file server for many users, please select throughput performance"
    echo -e "\e[43m\e[30m$warning_msg\e[0m" >> $output_file
    warnings+="\n$warning_msg"
  fi
  echo "" >> $output_file
}

# Function to get RAM information
get_ram_info() {
  echo "RAM Information:" >> $output_file
  total_ram=$(free -h | grep "Mem:" | awk '{print $2}')
  used_ram=$(free -h | grep "Mem:" | awk '{print $3}')
  cached_ram=$(free -h | grep "Mem:" | awk '{print $6}')
  echo "Total RAM: $total_ram" >> $output_file
  echo "Used RAM: $used_ram" >> $output_file
  echo "Cached RAM: $cached_ram" >> $output_file
  echo "" >> $output_file
}

# Function to get SELinux status
get_selinux_status() {
  echo "SELinux Status:" >> $output_file
  selinux_status=$(sestatus | grep "SELinux status:" | awk '{print $3}')
  current_mode=$(sestatus | grep "Current mode:" | awk '{print $3}')
  echo "SELinux status: $selinux_status" >> $output_file
  echo "Current mode: $current_mode" >> $output_file
  if [ "$current_mode" == "enforcing" ]; then
    warning_msg="SELinux is currently set to enforcing. Please set this to permissive or disabled unless you aim to actively set SELinux configurations for your applications"
    echo -e "\e[43m\e[30m$warning_msg\e[0m" >> $output_file
    warnings+="\n$warning_msg"
  fi
  echo "" >> $output_file
}

# Function to run lsdev -cdt and output its result
run_lsdev() {
  echo "lsdev -cdt Output:" >> $output_file
  lsdev -cdt >> $output_file
  echo "" >> $output_file
}

# Function to output the content of /etc/45drives/server_info/server_info.json
output_server_info() {
  echo "Server Info:" >> $output_file
  cat /etc/45drives/server_info/server_info.json >> $output_file
  echo "" >> $output_file
}

echo "Network Configuration:" >> $output_file
get_bond_info
get_interface_info

echo "System Configuration:" >> $output_file
get_tuned_profile
get_ram_info

# Check if running on RHEL-based system before getting SELinux status
if [ -f /etc/redhat-release ]; then
  get_selinux_status
fi

run_lsdev
output_server_info

# Output all warnings at the end
echo -e "\nWarnings Summary:" >> $output_file
echo -e "$warnings" >> $output_file

# Output the results to the screen
cat $output_file
