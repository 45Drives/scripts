#!/bin/bash
# Brett Kelly Jun/21
# 45Drives
# Version 0.1 unstable

usage() { # Help
cat << EOF
    Usage:	
        [-b] Block DB size to expand into. Optional
        [-d] DB device to expand. Required. ?? Comma separated list of block devices. </dev/sda,/dev/1-1,/dev/nvme0n1> ??
        [-h] Displays this message
EOF
    exit 0
}

warning(){
    read -p "This is currently pre-release, use at your own risk. To continue enter 'y' " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]];then
        :
    else
        echo "Exiting..."
        exit 1
    fi
}

check_dependancies(){
    for i in "${!SCRIPT_DEPENDANCIES[@]}"; do
        if ! command -v ${SCRIPT_DEPENDANCIES[i]} >/dev/null 2>&1;then
	        echo "cli utility: ${SCRIPT_DEPENDANCIES[i]} is not installed"
            echo "jq, and bc are required"
	        exit 1
        fi
    done
}

ECHO_IF_DRYRUN=""
SCRIPT_DEPENDANCIES=(bc jq)
PHYSICAL_EXTENT_SIZE_BYTES=4194304 # REPLACE WITH CHECK JUST IN CASE THIS IS DIFFERENT  
AUTO_MODE="true"

while getopts 'b:d:Dh' OPTION; do
    case ${OPTION} in
    b)
        NEW_DB_SIZE=${OPTARG}
        NEW_DB_SIZE_BYTES=$(numfmt --from=iec $NEW_DB_SIZE)
        AUTO_MODE="false"
        ;;
    d)
        _DB_DEVICE=${OPTARG}
        IFS=',' read -r -a DB_DEVICE <<< "$_DB_DEVICE"        
        ;;
    D)
        ECHO_IF_DRYRUN="echo"
        ;;
    h)
        usage
        ;;
    esac
done

if [ -z $DB_DEVICE ]; then
    echo "Input required. See ./`basename "$0"` -h for usage details"
    exit 1
fi

warning 

# Check cli depandancies
check_dependancies

for device in ${DB_DEVICE[@]};do
    if [ ! -b $device ];then
        echo "Error: DB_DEVICE=$device is not a block device"
        continue
    fi

    # VERIFY THAT DEVICE IS A DEDICATED DB DEVICE
    # If there are no lv's present then skip
    # If there are lvs and the lv name formats are not "osd-db-*" then skip 
    DB_DEVICE_LV_JSON=$(lvs --noheadings --reportformat json --devices $device -o lv_name,vg_name)
    DB_LV_COUNT=$(echo $DB_DEVICE_LV_JSON | jq '.report | .[].lv | length')
    if [ "$DB_LV_COUNT" -eq 0 ];then
        echo "Warning: $device is has no Logical Volumes present, skipping"
        continue
    else
        # If there are lvs and the lv name formats are not "osd-db-*" then skip 
        while [ $i -lt $DB_LV_COUNT ]; do
            name=$(echo $DB_DEVICE_LV_JSON | jq -r --arg index $i '.[] | .[].lv | .[$index |tonumber].lv_name')
            if echo $name | grep -v "osd-db" ;then
                echo "Warning: $device has unknown lvs present and therefore is not a dedicated db device, skipping"
                continue 2
            fi
        done
    fi
            
    # If there are lvs and the lv name formats are not "osd-db-*" then skip 

    DB_DEVICE_PV_JSON=$(pvs --noheadings --reportformat json --devices $device -o pv_pe_count,pv_pe_alloc_count)
    TOTAL_PHYSICAL_EXTENTS=$(echo $DB_DEVICE_PV_JSON | jq -r '.report | .[].pv | .[].pv_pe_count')
    ALLOCATED_PHYSICAL_EXTENTS=$(echo $DB_DEVICE_PV_JSON | jq -r '.report | .[].pv | .[].pv_pe_alloc_count')

    if $AUTO_MODE ;then
        echo "AUTO_MODE: Use Maximum Allowed Space"
        echo "DB_DEVICE:                    $device"
        echo "DB_LV_COUNT:                  $DB_LV_COUNT"
        echo "TOTAL_PHYSICAL_EXTENTS:       $TOTAL_PHYSICAL_EXTENTS"
        echo "ALLOCATED_PHYSICAL_EXTENTS:   $ALLOCATED_PHYSICAL_EXTENTS"

        CURRENT_DB_SIZE_EXTENTS=$(bc <<< "$ALLOCATED_PHYSICAL_EXTENTS/$DB_LV_COUNT")
        NEW_DB_SIZE_EXTENTS=$(bc <<< "$TOTAL_PHYSICAL_EXTENTS/$DB_LV_COUNT")
        CURRENT_DB_SIZE_BYTES=$(bc <<< "$PHYSICAL_EXTENT_SIZE_BYTES*$CURRENT_DB_SIZE_EXTENTS")
        NEW_DB_SIZE_BYTES=$(bc <<< "$PHYSICAL_EXTENT_SIZE_BYTES*$NEW_DB_SIZE_EXTENTS")

        echo "CURRENT_DB_SIZE_EXTENTS:      $CURRENT_DB_SIZE_EXTENTS"
        echo "NEW_DB_SIZE_EXTENTS:          $NEW_DB_SIZE_EXTENTS"
        echo "CURRENT_DB_SIZE_BYTES:        $(numfmt --to=iec $CURRENT_DB_SIZE_BYTES)"
        echo "NEW_DB_SIZE_BYTES:            $(numfmt --to=iec $NEW_DB_SIZE_BYTES)"
    else
        echo "MANUAL_MODE: Use User Specified DB SIZE"
        echo "DB_DEVICE:                    $device"
        echo "DB_LV_COUNT:                  $DB_LV_COUNT"
        echo "TOTAL_PHYSICAL_EXTENTS:       $TOTAL_PHYSICAL_EXTENTS"
        echo "ALLOCATED_PHYSICAL_EXTENTS:   $ALLOCATED_PHYSICAL_EXTENTS"

        TOTAL_PHYSICAL_BYTES=$(bc <<< "$TOTAL_PHYSICAL_EXTENTS*$PHYSICAL_EXTENT_SIZE_BYTES")
        CURRENT_DB_SIZE_EXTENTS=$(bc <<< "$ALLOCATED_PHYSICAL_EXTENTS/$DB_LV_COUNT")
        CURRENT_DB_SIZE_BYTES=$(bc <<< "$PHYSICAL_EXTENT_SIZE_BYTES*$CURRENT_DB_SIZE_EXTENTS")
        NEW_DB_SIZE_EXTENTS=$(bc <<< "$NEW_DB_SIZE_BYTES/$PHYSICAL_EXTENT_SIZE_BYTES")
        NEW_TOTAL_DB_SIZE_EXTENTS=$(bc <<< "$NEW_DB_SIZE_EXTENTS*$DB_LV_COUNT")
        NEW_TOTAL_DB_SIZE_BYTES=$(bc <<< "$NEW_TOTAL_DB_SIZE_EXTENTS*$PHYSICAL_EXTENT_SIZE_BYTES")

        echo "CURRENT_DB_SIZE_EXTENTS:      $CURRENT_DB_SIZE_EXTENTS"
        echo "NEW_DB_SIZE_EXTENTS:          $NEW_DB_SIZE_EXTENTS"
        echo "NEW_TOTAL_DB_SIZE_EXTENTS:    $NEW_TOTAL_DB_SIZE_EXTENTS"

        # NEW_DB_SIZE_EXTENTS cant be less than CURRENT_DB_SIZE_EXTENTS
        if [ $NEW_DB_SIZE_EXTENTS -lt $CURRENT_DB_SIZE_EXTENTS ];then
            echo "Warning: New DB Size ($(numfmt --to=iec $NEW_DB_SIZE_BYTES)) cannot be less than Current DB Size ($(numfmt --to=iec $CURRENT_DB_SIZE_BYTES)) "
            exit 1
        fi
        #NEW_TOTAL_DB_SIZE_EXTENTS cant be greater than TOTAL_PHYSICAL_EXTENTS
        if [ $NEW_TOTAL_DB_SIZE_EXTENTS -gt $TOTAL_PHYSICAL_EXTENTS ];then
            echo "Warning: New total DB size ($(numfmt --to=iec $NEW_TOTAL_DB_SIZE_BYTES)) exceeds the total available space on the DB device ($(numfmt --to=iec $TOTAL_PHYSICAL_BYTES))"
            exit 1
        fi
    fi

    # Make sure ceph admin keyring is present hs correct permission
    # Remove "set -e" so we can check ceph status error code
    # Then turn it back on after
    ceph status > /dev/null 2>&1 ; rc=$?
    if [[ "$rc" -ne 0 ]];then
        echo "Warning: permisson denied accessing cluster, admin keyring must be present"
        exit 1
    fi

    CEPH_MAJOR_VERSION=$(ceph version | awk '{print $3}' | cut -d . -f 1)
    if [ $CEPH_MAJOR_VERSION -gt "15" ];then
        echo "Warning: current process is not supported on clusters version 16 and up"
        exit 1
    fi

    i=0
    while [ $i -lt $DB_LV_COUNT ]; do

        LV_NAME=$(echo $DB_DEVICE_LV_JSON | jq -r --arg index $i '.[] | .[].lv | .[$index |tonumber].lv_name')
        VG_NAME=$(echo $DB_DEVICE_LV_JSON | jq -r --arg index $i '.[] | .[].lv | .[$index |tonumber].vg_name')
        OSD_JSON=$(ceph-volume lvm list --format json /dev/$VG_NAME/$LV_NAME)
        OSD_ID=$( echo $OSD_JSON | jq  -r '.[] | .[].tags["ceph.osd_id"]')
        OSD_TYPE=$( echo $OSD_JSON | jq  -r '.[] | .[].type')

        if [ "$OSD_TYPE" == "block" ];then
            echo "Warning: /dev/$VG_NAME/$LV_NAME on device $device is a bluestore block device, skipping"
            continue 2
        fi

        echo "Extending db lv /dev/$VG_NAME/$LV_NAME to $NEW_DB_SIZE_EXTENTS"
        $ECHO_IF_DRYRUN lvextend -l $NEW_DB_SIZE_EXTENTS /dev/$VG_NAME/$LV_NAME

        # Call ceph health check function dont continue unless cluster healthy
        CEPH_STATUS=$(ceph health --format json | jq -r '.status')
        while [ "$CEPH_STATUS" != "HEALTH_OK" ]; do
            echo "Warning: Cluster is not in HEALTH_OK state"
            sleep 2
            CEPH_STATUS=$(ceph health --format json | jq -r '.status')
        done

        echo "Stopping OSD.$OSD_ID"
        $ECHO_IF_DRYRUN ceph osd set noout
        $ECHO_IF_DRYRUN systemctl stop ceph-osd@$OSD_ID

        echo "Expanding bluestore db device to fill new space"
        $ECHO_IF_DRYRUN ceph-bluestore-tool bluefs-bdev-expand --path /var/lib/ceph/osd/ceph-$OSD_ID

        echo "Start OSD again"
        $ECHO_IF_DRYRUN systemctl start ceph-osd@$OSD_ID

        echo "Unset noout"
        $ECHO_IF_DRYRUN ceph osd unset noout

        echo "Verify osd is back up before continuing"

        OSD_STATE=$(ceph osd tree --format json | jq --arg id "$OSD_ID" -r '.nodes[] | select(.id == ($id |tonumber)) | .status')
        echo "OSD_STATE:  $OSD_STATE"
        while [ "$OSD_STATE" != "up" ]; do
            echo "Warning: OSD.$OSD_ID is not UP yet. Waiting..."
            sleep 2
            OSD_STATE=$(ceph osd tree --format json | jq --arg id "$OSD_ID" -r '.nodes[] | select(.id == ($id |tonumber)) | .status')
            echo "OSD_STATE:  $OSD_STATE"
        done

        let i=i+1
    done
done
