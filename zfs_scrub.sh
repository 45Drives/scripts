#!/bin/sh -eu

# Scrub all healthy pools.
zpool list -H -o health,name 2>&1 | \
        awk 'BEGIN {FS="\t"} {if ($1 ~ /^ONLINE/) print $2}' | \
while read pool
do
        systemctl enable --now zfs-scrub-monthly@$pool.timer
done
