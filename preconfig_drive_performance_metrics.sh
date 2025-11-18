#!/usr/bin/env bash

########## THIS IS A WORK IN PROGRESS; NOT READY FOR PRODUCTION YET. DON'T USE ON CUSTOMER SYSTEMS YET ##########
# Curtis LeBlanc
# Date created: 17 November 2025
# 45Drives
# Rev 0.1.0
# This script uses fio to gather performance metrics on empty drives. Currently, it checks random read, sequential read, and sequential write performance.
# Intended for checking drives before configuration to verify they're operating at expected parameters.

OUTPUT_DIR="/var/log/storage_bench"
JSON_OUTPUT="$OUTPUT_DIR/results.json"

mkdir -p "$OUTPUT_DIR"

###############################################
# Determine all devices used by the boot/root
###############################################
get_boot_disks() {
    (
        # Direct mountpoints (/, /boot, /boot/efi)
        lsblk -no PKNAME "$(findmnt -no SOURCE / 2>/dev/null)" 2>/dev/null
        lsblk -no PKNAME "$(findmnt -no SOURCE /boot 2>/dev/null)" 2>/dev/null
        lsblk -no PKNAME "$(findmnt -no SOURCE /boot/efi 2>/dev/null)" 2>/dev/null

        # If PKNAME empty, fall back to base device
        lsblk -no NAME "$(findmnt -no SOURCE / 2>/dev/null)" 2>/dev/null
        lsblk -no NAME "$(findmnt -no SOURCE /boot 2>/dev/null)" 2>/dev/null
        lsblk -no NAME "$(findmnt -no SOURCE /boot/efi 2>/dev/null)" 2>/dev/null

        # If LVM is used for root, include PVs
        pvs --no-headings -o pv_name 2>/dev/null | sed 's/[0-9]*$//' | sed 's|/dev/||'

    ) | sed 's/^\s*//;s/\s*$//' | sort -u | grep -v '^$'
}

BOOT_DISKS=$(get_boot_disks)

###############################################
# Detect non-boot block devices
###############################################
get_devices() {
    lsblk -dn -o NAME,TYPE | while read -r name type; do
        [[ "$type" != "disk" ]] && continue

        # Skip boot disks
        if echo "$BOOT_DISKS" | grep -qw "$name"; then
            continue
        fi

        echo "/dev/$name"
    done
}

###############################################
# FIO test (read-only)
###############################################
run_fio_test() {
    local dev="$1"
    local log="$2"

    echo "Running fio benchmark on $dev" | tee -a "$log"

    fio --name=randread \
        --filename="$dev" \
        --direct=1 \
        --rw=randread \
        --bs=4k \
        --iodepth=32 \
        --numjobs=1 \
        --size=4G \
        --runtime=20 \
        --time_based \
        --ioengine=libaio \
        --group_reporting >> "$log" 2>&1
}

###############################################
# Parse FIO result
###############################################
append_json() {
    local dev="$1"
    local log="$2"

    local iops=$(grep -m1 "IOPS=" "$log" | sed 's/.*IOPS=\([0-9\.kK]\+\).*/\1/')
    local bw=$(grep -m1 "BW=" "$log" | sed 's/.*BW=\([0-9A-Za-z\/]\+\).*/\1/')

    jq -n \
        --arg dev "$dev" \
        --arg iops "$iops" \
        --arg bw "$bw" \
        '{
            device: $dev,
            benchmark: {
                read_iops: $iops,
                read_bandwidth: $bw
            }
        }'
}

###############################################
# MAIN
###############################################
echo "[" > "$JSON_OUTPUT"
FIRST=1

echo "Boot devices detected and skipped:" 
echo "$BOOT_DISKS" | sed 's/^/  - /'

for dev in $(get_devices); do
    log="$OUTPUT_DIR/$(basename $dev).log"

    echo "===============================================" | tee "$log"
    echo "Benchmarking raw device: $dev" | tee -a "$log"
    echo "Log: $log" | tee -a "$log"
    echo "===============================================" | tee -a "$log"

    run_fio_test "$dev" "$log"

###############################################
# Sequential READ
###############################################
echo "Running sequential READ benchmark on $dev" | tee -a "$log"
fio --name=seqread \
    --filename="$dev" \
    --rw=read \
    --bs=128k \
    --iodepth=32 \
    --ioengine=libaio \
    --numjobs=1 \
    --direct=1 \
    --runtime=20 \
    --time_based=1 >> "$log" 2>&1

###############################################
# Sequential WRITE
###############################################
echo "Running sequential WRITE benchmark on $dev" | tee -a "$log"
fio --name=seqwrite \
    --filename="$dev" \
    --rw=write \
    --bs=128k \
    --iodepth=32 \
    --ioengine=libaio \
    --numjobs=1 \
    --direct=1 \
    --runtime=20 \
    --time_based=1 >> "$log" 2>&1

    if [[ $FIRST -eq 0 ]]; then echo "," >> "$JSON_OUTPUT"; fi
    FIRST=0

    append_json "$dev" "$log" >> "$JSON_OUTPUT"
done

echo "]" >> "$JSON_OUTPUT"

echo "All tests complete."
echo "JSON written to: $JSON_OUTPUT"
