#!/bin/bash

# Mitch Hall July 2024
# 45Drives
# Version 1.0 stable
# This script will run through various zpool, network, and system configurations and check for misconfigurations or less ideal configurations and give recommendations for best practice


# Output file
output_file="/var/log/config_summary_$(date +'%Y%m%d_%H%M%S').txt"
warnings=""

# Check if zpool_parse.py exists, if not, attempt to download it
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

# Run functions and output to screen and file
get_raw_zpool_status
get_zpool_status
get_zfs_version
get_zfs_arc_stats
get_datasets_info
check_snapshots

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

