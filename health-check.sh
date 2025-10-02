#!/bin/bash

# Harmin Patel
# Date created: 10 March 2025
# 45Drives

timestamp=$(date +"%Y%m%d_%H%M%S")
out_dir="/tmp/health-check_$timestamp"
mkdir -p "$out_dir"
mkdir -p "$out_dir/ceph"
mkdir -p "$out_dir/ceph/device_health"
ctdb_dir="$out_dir/ctdb"
mkdir -p "$ctdb_dir"
logfile="$out_dir/ctdb/report.log"
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
