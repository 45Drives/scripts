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

check_dependancies(){
    for i in "${!SCRIPT_DEPENDANCIES[@]}"; do
        if ! command -v ${SCRIPT_DEPENDANCIES[i]} >/dev/null 2>&1;then
	        echo "cli utility: ${SCRIPT_DEPENDANCIES[i]} is not installed"
            echo "jq, and bc are required"
	        exit 1
        fi
    done
}

SCRIPT_DEPENDANCIES=(bc jq)
PHYSICAL_EXTENT_SIZE_BYTES=4194304 # REPLACE WITH CHECK JUST IN CASE THIS IS DIFFERENT  
AUTO_MODE="true"

while getopts 'b:fo:d:h' OPTION; do
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
    h)
        usage
        ;;
    esac
done

if [ -z $DB_DEVICE ]; then
    echo "Input required. See ./`basename "$0"` -h for usage details"
    exit 1
fi

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
    fi
    # If there are lvs and the lv name formats are not "osd-db-*" then skip 
    
    

    DB_DEVICE_PV_JSON=$(pvs --noheadings --reportformat json --devices $device -o pv_pe_count,pv_pe_alloc_count)
    TOTAL_PHYSICAL_EXTENTS=$(echo $DB_DEVICE_PV_JSON | jq -r '.report | .[].pv | .[].pv_pe_count')
    ALLOCATED_PHYSICAL_EXTENTS=$(echo $DB_DEVICE_PV_JSON | jq -r '.report | .[].pv | .[].pv_pe_alloc_count')

    if $AUTO_MODE ;then
        # if max allowed space
        # take count of lvs on db device
        # take total of extents of db_device divide by count of lvs on db device, this is the new size for each lv

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
        # if user specified
        # take count of lvs on db device
        # convert user spec. size to lv extents
        # multiply desired lv extents by number of lvs on device, compare to total available, fail if doesnt fit
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

    #Loop through each lv on the device
    #need to get LV name
    #need to get VG name
    #need to get OSD.id

    # extend lv /dev/vg_name/lv_name to either max allowed space or user specified

    # i=0
    # while [ $i -lt $DB_LV_COUNT ]; do
    #     UPLOAD_ID=$(echo $MPU_JSON | jq -r .Uploads[$i].UploadId)
    #     UPLOAD_KEY=$(echo $MPU_JSON | jq -r .Uploads[$i].Key)
done