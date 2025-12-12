#!/bin/bash

# Define formatting for the table
printf "%-35s %-22s %-22s %-22s\n" "IMAGE NAME" "CREATED" "ACCESSED (Meta)" "MODIFIED (Meta)"
printf "%-35s %-22s %-22s %-22s\n" "----------" "-------" "---------------" "---------------"

# 1. Find all enabled RBD storages from Proxmox config
pvesm status -content images | awk '$2=="rbd" {print $1}' | while read STOREID; do

    # Get the actual Ceph pool name for this storage
    POOL=$(grep -A5 "rbd: $STOREID" /etc/pve/storage.cfg | grep "pool" | awk '{print $2}')
    
    # Fallback if pool detection fails (default is often 'rbd')
    if [ -z "$POOL" ]; then POOL="rbd"; fi

    # 2. List all images in the pool
    rbd -p "$POOL" --namespace pve ls | while read IMAGE; do
        
        # 3. Get Info from RBD
        # We capture the whole output to a variable to avoid calling rbd info 3 times
        INFO=$(rbd info "$POOL/$IMAGE" --namespace pve 2>/dev/null)
        
        # Extract timestamps
        c_time=$(echo "$INFO" | grep "create_timestamp" | awk -F': ' '{print $2}')
        a_time=$(echo "$INFO" | grep "access_timestamp" | awk -F': ' '{print $2}')
        m_time=$(echo "$INFO" | grep "modify_timestamp" | awk -F': ' '{print $2}')

        # Handle empty results (older Ceph versions might not show all 3)
        if [ -z "$c_time" ]; then c_time="-"; fi
        if [ -z "$a_time" ]; then a_time="-"; fi
        if [ -z "$m_time" ]; then m_time="-"; fi

        # Print row
        printf "%-35s %-22s %-22s %-22s\n" "${IMAGE:0:34}" "$c_time" "$a_time" "$m_time"

    done
done
