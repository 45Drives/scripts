#!/bin/bash
# Brett Kelly Jun/21
# 45Drives
# Version 0.1 unstable

usage() { # Help
cat << EOF
    Usage:	
        [-b] Block DB size to expand into. Optional
        [-d] DB device to expand. Required. Comma separated list of block devices. </dev/sda,/dev/1-1,/dev/nvme0n1>
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

set -e

ECHO_IF_DRYRUN=""
SCRIPT_DEPENDANCIES=(bc jq)
PHYSICAL_EXTENT_SIZE_BYTES=4194304
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

    ### VERIFY THAT DEVICE IS A DEDICATED DB DEVICE
    # If there are no lv's present then skip
    # If there are lvs and the lv name formats are not "osd-db-*" then skip

    # We are looking for dedicated db devices deployed with either ceph-volume or add-db-to-osd.sh
    # A dedicated db deployed with either tool will have only 1 volume group with the name ceph-$(uuid)
    # skip device if no vg present
    # skip device if more than 1 vg present
    # skip device if vg does not have name syntax matching ceph-$(uuidgen)

    DB_VG_COUNT=$(pvs --noheadings --reportformat json $device -o vg_name | jq -r '.report | .[].pv | length')
    if [ "$DB_VG_COUNT" -eq 0 ];then
        echo "Warning: $device is has no volume groups present, skipping"
        continue
    elif [ "$DB_VG_COUNT" -gt 1 ];then
        echo "Warning: $device has more than one volume group present, skipping"
        continue
    fi
    DB_VG_NAME=$(pvs --noheadings --reportformat json $device -o vg_name | jq -r '.report | .[].pv | .[0].vg_name')
    if echo $DB_VG_NAME | grep -vqE "ceph-[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89aAbB][a-f0-9]{3}-[a-f0-9]{12}" ;then
        echo "Warning: $device has unknown vg present, skipping"
        continue
    fi
    DB_VG_PHYSICAL_EXTENT=$(pvs --noheadings --reportformat json $device -o vg_extent_size --units B --nosuffix | jq -r '.report | .[].pv | .[0].vg_extent_size')
    if [ "$DB_VG_PHYSICAL_EXTENT" -ne "$PHYSICAL_EXTENT_SIZE_BYTES" ];then
        echo "Warning: Physical Extent size is not the default 4MiB, skipping"
        continue
    fi

    DB_DEVICE_LV_JSON=$(vgs --noheadings --reportformat json -o lv_name,vg_name $DB_VG_NAME)
    DB_LV_COUNT=$(echo $DB_DEVICE_LV_JSON | jq '.report | .[].vg | length')
    if [ "$DB_LV_COUNT" -eq 0 ];then
        echo "Warning: $device is has no Logical Volumes present, skipping"
        continue
    else
        # If there are lvs and the lv name formats are not "osd-db-$(uuidgen)" then skip 
        i=0
        while [ $i -lt $DB_LV_COUNT ]; do
            name=$(echo $DB_DEVICE_LV_JSON | jq -r --arg index $i '.[] | .[].lv | .[$index |tonumber].lv_name')
            if echo $name | grep -qE "osd-db-[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89aAbB][a-f0-9]{3}-[a-f0-9]{12}" ;then
                echo "Warning: $device has non db lvs present and therefore is not a dedicated db device, skipping"
                continue 2
            fi
            let i=i+1
        done
    fi
    ###

    DB_DEVICE_PV_JSON=$(pvs --noheadings --reportformat json $device -o pv_pe_count,pv_pe_alloc_count)
    TOTAL_PHYSICAL_EXTENTS=$(echo $DB_DEVICE_PV_JSON | jq -r '.report | .[].pv | .[].pv_pe_count')
    ALLOCATED_PHYSICAL_EXTENTS=$(echo $DB_DEVICE_PV_JSON | jq -r '.report | .[].pv | .[].pv_pe_alloc_count')

    if $AUTO_MODE ;then
        echo "MODE:                 Use Maximum Allowed Space"
        echo "DB_DEVICE:            $device"   
        NEW_DB_SIZE_EXTENTS=$(bc <<< "$TOTAL_PHYSICAL_EXTENTS/$DB_LV_COUNT")
        NEW_DB_SIZE_BYTES=$(bc <<< "$PHYSICAL_EXTENT_SIZE_BYTES*$NEW_DB_SIZE_EXTENTS")
        echo "NEW_DB_SIZE_BYTES:    $(numfmt --to=iec $NEW_DB_SIZE_BYTES)"
        echo "NEW_DB_SIZE_EXTENTS:  $NEW_DB_SIZE_EXTENTS"
    else
        echo "MODE:                         Use User Specified DB SIZE"
        echo "DB_DEVICE:                    $device"
        NEW_DB_SIZE_EXTENTS=$(bc <<< "$NEW_DB_SIZE_BYTES/$PHYSICAL_EXTENT_SIZE_BYTES")
        TOTAL_PHYSICAL_BYTES=$(bc <<< "$TOTAL_PHYSICAL_EXTENTS*$PHYSICAL_EXTENT_SIZE_BYTES")
        NEW_TOTAL_DB_SIZE_EXTENTS=$(bc <<< "$NEW_DB_SIZE_EXTENTS*$DB_LV_COUNT")
        echo "NEW_DB_SIZE_BYTES:            $NEW_DB_SIZE_BYTES"
        echo "NEW_DB_SIZE_EXTENTS:          $NEW_DB_SIZE_EXTENTS"

        #NEW_TOTAL_DB_SIZE_EXTENTS cant be greater than TOTAL_PHYSICAL_EXTENTS
        if [ $NEW_TOTAL_DB_SIZE_EXTENTS -gt $TOTAL_PHYSICAL_EXTENTS ];then
            echo "Warning: New total DB size ($(numfmt --to=iec $NEW_TOTAL_DB_SIZE_BYTES)) exceeds the total available space on the DB device ($(numfmt --to=iec $TOTAL_PHYSICAL_BYTES))"
            continue 
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

        LV_NAME=$(echo $DB_DEVICE_LV_JSON | jq -r --arg index $i '.[] | .[].vg | .[$index |tonumber].lv_name')
        VG_NAME=$(echo $DB_DEVICE_LV_JSON | jq -r --arg index $i '.[] | .[].vg | .[$index |tonumber].vg_name')
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
        set +e
        CEPH_STATUS=$(ceph health --format json | jq -r '.status')
        set -e
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
