#!/bin/bash
# Nov 2022
# 45Drives

usage() { # Help
cat << EOF
    Usage:	
        [-b] New Block DB size. Optional. Allowed suffixes K,M,G,T. Should be larger than 60G to avoid BlueFS spillover. This is the size of the Ceph LVMs created by ceph-volume. 
        [-d] Old DB device. Required. /dev/sdX
        [-o] OSD(s) on the old DB device we want to migrate. Required. Comma separated list of osd.id. <0,1,2,3>
        [-n] New DB device to migrate journal partitions to. /dev/sdY
        [-h] Displays this message
EOF
    #[-s] Partition starting sector
    #[-e] Partition ending sector
    exit 0
}

welcome() {
	#local response
	cat <<EOF
Welcome to the

 /##   /## /#######  /#######            /##                              
| ##  | ##| ##____/ | ##__  ##          |__/                              
| ##  | ##| ##      | ##  \ ##  /######  /## /##    /## /######   /#######
| ########| ####### | ##  | ## /##__  ##| ##|  ##  /##//##__  ## /##_____/
|_____  ##|_____  ##| ##  | ##| ##  \__/| ## \  ##/##/| ########|  ###### 
      | ## /##  \ ##| ##  | ##| ##      | ##  \  ###/ | ##_____/ \____  ##
      | ##|  ######/| #######/| ##      | ##   \  #/  |  ####### /#######/
      |__/ \______/ |_______/ |__/      |__/    \_/    \_______/|_______/

                        PetaSAN - Ceph journal partition migration script.

    This script will take the data from PetaSAN-created journal partitions
    and migrate it to logical volumes in a volume group on a new device. 

    
EOF

	#read -p "Are you sure you want to continue? [y/N]: " response

	#case $response in
	#	[yY]|[yY][eE][sS])
	#		echo
	#		;;
	#	*)
	#		echo "Exiting..."
	#		exit 0
	#		;;
	#esac

	return 0
}


confirm_db_devices(){
    echo -e "\nOLD DB Device selected: $DB_DEVICE"
    echo "NEW DB Device selected: $NEW_DB_DEVICE"
    echo -e "\nVerifying journal data for OSDs ${OSD_LIST[@]} exists on $DB_DEVICE..."
    for i in "${!OSD_LIST[@]}"; do
        OSD_ID=${OSD_LIST[i]}
        OSD_JSON=$(echo $CEPH_VOLUME_JSON | jq -r --arg id "$OSD_ID" '.[] | .[] | select(.tags["ceph.osd_id"]==$id) | select(.tags["ceph.type"]=="block")')
        OSD_DB_DEVICE=$(echo $OSD_JSON | jq -r '.tags["ceph.db_device"]') # /dev/sda2 || /dev/ceph-2599ab8a-14d5-42c6-990f-726248fda5e7/osd-db-f67b107c-cf3d-4465-a6b9-8393c56b2904
        if `lvs | grep $(echo $OSD_DB_DEVICE | cut -d/ -f4) &>/dev/null`; then 
            DB_REALDEVICE=/dev/$(ls /sys/block/$(realpath $OSD_DB_DEVICE | cut -d/ -f3)/slaves | sed 's/[0-9]*//g;s/ //g')
            if [ "$DB_REALDEVICE" == "$DB_DEVICE" ]; then
                echo "$DB_DEVICE matches osd.$OSD_ID"
            else 
                echo "$DB_DEVICE is not associated with osd.$OSD_ID. Exiting..."
                exit 1
            fi
        else
            OSD_DB_RAW=$(echo $OSD_DB_DEVICE | sed 's/[0-9]*//g')
            if [ "$OSD_DB_RAW" == "$DB_DEVICE" ]; then
                echo "$DB_DEVICE matches osd.$OSD_ID"
            else 
                echo "$DB_DEVICE is not associated with osd.$OSD_ID. Exiting..."
                exit 1
            fi
        fi
    done

    #NEW DB DEVICE CHECK
    #----------------------------------------------------------------------------------------------------------
    #need to confirm new db is empty

    NEW_DB_PARTITIONS=()
    NEW_DB_PARTITIONS=($(fdisk -l $NEW_DB_DEVICE | awk 'NR>=10,NR<=100 {print $1}'))
    NEW_DB_PART_NUM=(${#NEW_DB_PARTITIONS[@]})

    #echo "New DB device number of partitions: $NEW_DB_PART_NUM"
    #exit 1
    if [ $NEW_DB_PART_NUM -eq 0 ]; then
        echo -e "\nNo existing partitions found on $NEW_DB_DEVICE. OK to continue."
        #exit 1    
    else
        echo -e "\nPartitions exist on new DB device $NEW_DB_DEVICE. It must be wiped before use. Exiting..."
        exit 1
    fi

    #if NEW_DB_DEVICE is empty, is it large enough to hold old db partitions?
    
    OLD_DB_PARTITION_LIST=()
    OLD_DB_SIZE_NEEDED=0
    IFS=$'\n' #add elements by newline only
    OLD_DB_PARTITION_LIST=($(fdisk -l $DB_DEVICE | awk 'NR>=10,NR<=100 {print $1, $5}'))
    #echo "Existing DB has ${#PETASAN_DB_PARTITION_LIST[@]} PetaSAN partitions."
    OLD_DB_PARTITION_NUM=${#OLD_DB_PARTITION_LIST[@]}
    PHYSICAL_EXTENT_SIZE_BYTES=4194304
    DB_DEVICE_PARTITION_SIZE_SUM=0
    
    if [ -z "$BLOCK_DB_SIZE_BYTES" ]; then
        BLOCK_DB_SIZE=0
    fi
    BLOCK_DB_SIZE_BYTES=$(echo $BLOCK_DB_SIZE | numfmt --from=iec)

    for i in ${OLD_DB_PARTITION_LIST[@]}; do 
        CURRENT_PARTITION=$(echo $i | cut -d' ' -f1)
        CURRENT_PARTITION_SIZE_BYTES=$(echo $i | cut -d' ' -f2 | numfmt --from=iec )
 
        DB_DEVICE_PARTITION_SIZE_SUM_EXTENTS=$(($DB_DEVICE_PARTITION_SIZE_SUM+$(bc <<< "$CURRENT_PARTITION_SIZE_BYTES/$PHYSICAL_EXTENT_SIZE_BYTES")))
        #echo $DB_DEVICE_PARTITION_SIZE_SUM_EXTENTS

        done
    #echo "Required minimum new DB device size: $DB_DEVICE_PARTITION_SIZE_SUM_EXTENTS extents."

    NEW_DB_DEVICE_SIZE_BYTES=($(fdisk -l $NEW_DB_DEVICE | awk 'NR==1 {print $3 $4}' | sed 's/.$//' | numfmt --from=iec-i --suffix=B | sed 's/.$//'))
    NEW_DB_DEVICE_SIZE_GB=($(echo $NEW_DB_DEVICE_SIZE_BYTES | numfmt --to=iec))
    NEW_DB_DEVICE_SIZE_EXTENTS=$(bc <<< "$NEW_DB_DEVICE_SIZE_BYTES/$PHYSICAL_EXTENT_SIZE_BYTES")

    echo -e "\nNew DB device has $NEW_DB_DEVICE_SIZE_GB ($(($NEW_DB_DEVICE_SIZE_EXTENTS-1)) extents) avail."
    if [ "$BLOCK_DB_SIZE_BYTES" -gt "0" ]; then
        echo -e "Required extents is $(($BLOCK_DB_SIZE_BYTES/$PHYSICAL_EXTENT_SIZE_BYTES*5))."
    fi

    # if new DB device is large enough to contain existing DB partitions at their existing size, then
    if [ $NEW_DB_DEVICE_SIZE_EXTENTS>$DB_DEVICE_PARTITION_SIZE_SUM_EXTENTS ]; then
        #echo "$(($BLOCK_DB_SIZE_BYTES*$OLD_DB_PARTITION_NUM))"
        #echo "$NEW_DB_DEVICE_SIZE_BYTES"
        # and if new DB device is large enough to contain: user-specified new DB partition size multiplied by # of partitions, then
        if [ "$(($BLOCK_DB_SIZE_BYTES*$OLD_DB_PARTITION_NUM))" -le "$(($NEW_DB_DEVICE_SIZE_BYTES -1 ))" ]; then
            if [ -z "$BLOCK_DB_SIZE_BYTES" ] || [ "$BLOCK_DB_SIZE_BYTES" -eq "0" ]; then
                echo -e "\nNew DB device $NEW_DB_DEVICE should be large enough to hold at least $OLD_DB_PARTITION_NUM 60G DB partitions. OK to continue. "
            else
                echo -e "\nNew DB device $NEW_DB_DEVICE IS large enough to hold $OLD_DB_PARTITION_NUM $BLOCK_DB_SIZE DB partitions. OK to continue. "
                #exit 1
            fi   
        else
            #echo "New DB device $NEW_DB_DEVICE IS NOT large enough to hold $OLD_DB_PARTITION_NUM DB partitions. Exiting..."
            echo -e "\nNew DB device $NEW_DB_DEVICE IS NOT large enough to hold the existing $OLD_DB_PARTITION_NUM DB partitions from $DB_DEVICE at the specified size. Exiting..."
            exit 1 
        fi
    else
        echo -e "\nNew DB device $NEW_DB_DEVICE IS NOT large enough to hold the existing $OLD_DB_PARTITION_NUM DB partitions from $DB_DEVICE at the specified size. Exiting..."
        exit 1 
    fi

    # check if pvs shows anything. If there is an inactive PV it won't show in fdisk/lsblk
    NEW_DB_DEVICE_PVS=$(pvs | grep -i $NEW_DB_DEVICE | awk '{print $1}')
    if [ -z "$NEW_DB_DEVICE_PVS" ]; then
        echo -e "\nNo existing physical volume(s) or volume group(s) found on  $NEW_DB_DEVICE. OK to continue. "
    else
        echo -e "\nPhysical volume(s)/volume group(s) exist on new DB device $NEW_DB_DEVICE. They must be cleared before use. Exiting..."
        exit 1
    fi
    
    #----------------------------------------------------------------------------------------------------------
}


add_lv_tags(){
    get_lv_uuid(){
        local LV_UUID=$(lvs -o uuid $DB_LV_DEVICE --no-headings | awk '{$1=$1};1')
        echo "$LV_UUID"
    }
    # Add block.db tags to existing block device
    # echo $DB_LV_DEVICE
    # echo $(get_lv_uuid $DB_LV_DEVICE)
    lvchange --addtag "ceph.db_device=$DB_LV_DEVICE" $BLOCK_LV_DEVICE
    lvchange --addtag "ceph.db_uuid=$(get_lv_uuid $DB_LV_DEVICE)" $BLOCK_LV_DEVICE

    # Remove old block.db tags from block device before copying over to db lvs 
    OSD_JSON=$(echo $CEPH_VOLUME_JSON | jq -r --arg id "$OSD_ID" '.[] | .[] | select(.tags["ceph.osd_id"]==$id) | select(.tags["ceph.type"]=="block")')
    OLD_DB_PARTITION=$(echo $OSD_JSON | jq -r '.tags["ceph.db_device"]')
    OLD_DB_UUID=$(echo $OSD_JSON | jq -r '.tags["ceph.db_uuid"]')
    lvchange --deltag "ceph.db_device=$OLD_DB_PARTITION" $BLOCK_LV_DEVICE
    lvchange --deltag "ceph.db_uuid=$OLD_DB_UUID" $BLOCK_LV_DEVICE
    # echo $OLD_DB_PARTITION
    # echo $OLD_DB_UUID


    # Get all tags from existing block device and write them to new block.db
    # Both device should match except ceph.type=db and ceph.type=block

    BLOCK_LV_TAGS_STRING=$(lvs -o lv_tags --no-headings $BLOCK_LV_DEVICE | awk '{$1=$1};1')
    IFS=',' read -r -a BLOCK_LV_TAGS <<< "$BLOCK_LV_TAGS_STRING"
    for index in "${!BLOCK_LV_TAGS[@]}" ; do
        lvchange --addtag "${BLOCK_LV_TAGS[index]}" $DB_LV_DEVICE
    done
    lvchange --deltag "ceph.type=block" $DB_LV_DEVICE
    lvchange --addtag "ceph.type=db" $DB_LV_DEVICE
 }

check_dependencies(){
    for i in "${!SCRIPT_DEPENDENCIES[@]}"; do
        if ! command -v ${SCRIPT_DEPENDENCIES[i]} >/dev/null 2>&1;then
	        echo "cli utility: ${SCRIPT_DEPENDENCIES[i]} is not installed"
            echo "jq, and bc are required"
	        exit 1
        fi
    done
}

#ask user if they want to continue - can be called wherever needed 
ask_to_continue() {
    read -p "Do you want to continue? (yes/no): " yesno
    case "$yesno" in 
        [yY]|[yY][eE][sS]) 
            return 0 ;; # Continue
        [nN]|[nN][oO]) 
            echo "User does not want to continue."
            exit 1 ;; 
        *) 
            echo "Invalid choice. Please enter (y)yes or (n)no."
            ask_to_continue ;;
    esac
}



while getopts ":d:o:b:s:e:n:h" OPTION; do
    case ${OPTION} in 
    d)
        DB_DEVICE=${OPTARG}
        if [ ! -b $DB_DEVICE ];then
            echo "Error: DB_DEVICE=$DB_DEVICE is not a block device"
            exit 1
        fi
        ;;
    o) 
        OSD_LIST_=${OPTARG}
        IFS=',' read -r -a OSD_LIST <<< "$OSD_LIST_"
        ;;
    b)
        BLOCK_DB_SIZE=${OPTARG}
        BLOCK_DB_SIZE_BYTES=$(numfmt --from=iec $BLOCK_DB_SIZE)
        ;;
    s)  
        PART_SECTOR_START=${OPTARG}
        ;;
    e)  
        PART_SECTOR_END=${OPTARG}
        ;;
    
    n)
        NEW_DB_DEVICE=${OPTARG}
        ;;
    h)
        usage
        ;;
    esac
done

#p)
    #    PART_NUM=${OPTARG}
    #    ;;

##### START OF SCRIPTING #####

# if encountering any error quit, so to not make a mess
set -e

SCRIPT_DEPENDENCIES=(bc jq)

# confirm dependencies are met
check_dependencies

# welcome
welcome

### CONFIRM OSDS ARE ON HOST ###

# Check if osd is on the same host 
CEPH_VOLUME_JSON=$(ceph-volume lvm list --format json)
for i in "${!OSD_LIST[@]}"; do
    OSD_ID=${OSD_LIST[i]}
    OSD_JSON=$(echo $CEPH_VOLUME_JSON | jq -r --arg id "$OSD_ID" '.[] | .[] | select(.tags["ceph.osd_id"]==$id)')
    if [ -z "$OSD_JSON" ]; then
        echo "Can't find osd.$OSD_ID on this host"
        exit 1
    fi
done

# Confirm osds correspond to specified db device

confirm_db_devices



# Prepare new device for use
echo -e "\nAttempting to wipe new journal device $NEW_DB_DEVICE..."
ask_to_continue
wipefs -a $NEW_DB_DEVICE
echo -e "\nAttempting to create physical volume on $NEW_DB_DEVICE..."
ask_to_continue
pvcreate $NEW_DB_DEVICE #$PART_NUM
echo -e "\nAttempting to create volume group on $NEW_DB_DEVICE..."
ask_to_continue
#need to user DB_VG_NAME later on to make LVM...
DB_VG_NAME=ceph-$(uuidgen)
vgcreate $DB_VG_NAME $NEW_DB_DEVICE

### PV/VG CREATION COMPLETED ###

### JOURNAL MIGRATION LOOP ###

PHYSICAL_EXTENT_SIZE_BYTES=4194304
ONE_THIRD_OF_NEW_DB_BYTES=$(bc <<< "$NEW_DB_DEVICE_SIZE_BYTES/3")
LVM_SUGGESTED_SIZE_BYTES=$(bc <<< "$NEW_DB_DEVICE_SIZE_BYTES/$OLD_DB_PARTITION_NUM")
LVM_SUGGESTED_SIZE_GB=$(echo $LVM_SUGGESTED_SIZE_BYTES | numfmt --to=iec)
#echo "$LVM_SUGGESTED_SIZE_GB"

#if $BLOCK_DB_SIZE_BYTES is null or zero (user didn't use -b)
if [ -z "$BLOCK_DB_SIZE_BYTES" ] || [ "$BLOCK_DB_SIZE_BYTES" -eq "0" ]; then
    BLOCK_DB_SIZE_BYTES=$LVM_SUGGESTED_SIZE_BYTES

    if [ "$LVM_SUGGESTED_SIZE_BYTES" -lt "64424509440" ]; then
        #LVM_SUGGESTED_SIZE_BYTES=$(echo 60G | numfmt --from=iec)
        #LVM_SUGGESTED_SIZE_GB=60
        echo -e "WARNING: specified new DB size of $BLOCK_DB_SIZE is less than 60G. You could experience BlueFS spillover." 
    #If total new db size / num existing journal partitions >= 33% of total new nb device size, suggest 33%.
    elif [ "$LVM_SUGGESTED_SIZE_BYTES" -gt "$ONE_THIRD_OF_NEW_DB_BYTES" ]; then
        echo -e "WARNING: specified new DB size of $BLOCK_DB_SIZE is larger than 1/3 of the overall available space on $NEW_DB_DEVICE. " 
        #LVM_SUGGESTED_SIZE_BYTES=$ONE_THIRD_OF_NEW_DB_BYTES
        #LVM_SUGGESTED_SIZE_GB=$(echo $LVM_SUGGESTED_SIZE_BYTES | numfmt --to=iec)
        #exit 1
    fi

    echo -e "\nAs you have not specified a new size, the new DB partition size will be $LVM_SUGGESTED_SIZE_GB for each OSD in the list."
    ask_to_continue
    #exit 1

else
    #echo "$BLOCK_DB_SIZE_BYTES"
    #echo "$ONE_THIRD_OF_NEW_DB_BYTES"
    #echo "$LVM_SUGGESTED_SIZE_GB"
    #echo "$LVM_SUGGESTED_SIZE_BYTES"
    MINIMUM_SIZE_BYTES=64424509440

    if [ "$BLOCK_DB_SIZE_BYTES" -lt "$MINIMUM_SIZE_BYTES" ]; then
        #LVM_SUGGESTED_SIZE_BYTES=$(echo 60G | numfmt --from=iec)
        #LVM_SUGGESTED_SIZE_GB=60
        echo -e "\nWARNING: specified new DB size of $BLOCK_DB_SIZE is less than 60G. You could experience BlueFS spillover." 
        ask_to_continue
        #exit 1
    elif [ "$BLOCK_DB_SIZE_BYTES" -gt "$ONE_THIRD_OF_NEW_DB_BYTES" ]; then
        echo -e "\nThe user-specified new DB LVM size is larger than 1/3 of the overall new DB device size. We recommend a size of $LVM_SUGGESTED_SIZE_GB."
        ask_to_continue
        LVM_SUGGESTED_SIZE_BYTES=$ONE_THIRD_OF_NEW_DB_BYTES
        LVM_SUGGESTED_SIZE_GB=$(echo $LVM_SUGGESTED_SIZE_BYTES | numfmt --to=iec)
        #exit 1
    else
        echo "New DB partition size will be $(echo $BLOCK_DB_SIZE_BYTES | numfmt --to=iec) for each OSD in the list."
        ask_to_continue
        #exit 1
    fi
fi


BLOCK_DB_SIZE_EXTENTS=$(($(bc <<< "$BLOCK_DB_SIZE_BYTES/$PHYSICAL_EXTENT_SIZE_BYTES")-1))
## Check that the vg has space for the X number of lvs with block db size

#exit 1

for i in "${!OSD_LIST[@]}"; do
    
    OSD_ID=${OSD_LIST[i]}
    OSD_JSON=$(echo $CEPH_VOLUME_JSON | jq -r --arg id "$OSD_ID" '.[] | .[] | select(.tags["ceph.osd_id"]==$id) | select(.tags["ceph.type"]=="block")')
    OSD_DB_DEVICE=$(echo $OSD_JSON | jq -r '.tags["ceph.db_device"]')
    # IS DB DEVICE FOUND FROM TAGS EQAUL TO USER INPUT DB DEVICE MOVE THIS UP.. QUIT COMPELETLY IF SOMETHING IS WRONG BEFORE YOU MAKE CHANGES
    OSD_FSID=$(echo $OSD_JSON | jq -r '.tags["ceph.osd_fsid"]')

    DB_LV_UUID=$(uuidgen)
    DB_LV_DEVICE="/dev/$DB_VG_NAME/osd-db-$DB_LV_UUID"
    BLOCK_LV_DEVICE="$(echo $OSD_JSON | jq -r '.lv_path')"

    # Call ceph health check function dont continue unless cluster healthy
    CEPH_STATUS=$(ceph health --format json | jq -r '.status')
    while [ "$CEPH_STATUS" != "HEALTH_OK" ]; do
        echo "Warning: Cluster is not in HEALTH_OK state - waiting until it is resolved..."
        sleep 2
        CEPH_STATUS=$(ceph health --format json | jq -r '.status')
    done
    echo "Cluster status is HEALTH_OK!"

    #create logical volume
    #echo "$BLOCK_DB_SIZE_EXTENTS"
    #echo "$DB_LV_UUID $DB_VG_NAME"
    lvcreate -l $BLOCK_DB_SIZE_EXTENTS -n osd-db-$DB_LV_UUID $DB_VG_NAME
    chown -h ceph:ceph $DB_LV_DEVICE
    chown -R ceph:ceph $(realpath $DB_LV_DEVICE)

    #set maintenance flags
    echo "Set noout"
    ceph osd set noout

    echo "Stop OSD>$OSD_ID"
    systemctl stop ceph-osd@$OSD_ID

    echo "Flush OSD Journal"
    ceph-osd -i $OSD_ID --flush-journal

    echo "migrate block.db to new device"
    ceph-bluestore-tool bluefs-bdev-migrate --path /var/lib/ceph/osd/ceph-$OSD_ID/ --devs-source /var/lib/ceph/osd/ceph-$OSD_ID/block.db --dev-target $DB_LV_DEVICE

    echo "migrate data from block device to new db device"
    ceph-bluestore-tool bluefs-bdev-migrate --path /var/lib/ceph/osd/ceph-$OSD_ID/ --devs-source /var/lib/ceph/osd/ceph-$OSD_ID/block --dev-target /var/lib/ceph/osd/ceph-$OSD_ID/block.db

    chown -h ceph:ceph $DB_LV_DEVICE
    chown -R ceph:ceph $(realpath $DB_LV_DEVICE)

    echo "migrating lv tags"
    add_lv_tags

    echo "unmount OSD.$OSD_ID"
    umount /var/lib/ceph/osd/ceph-$OSD_ID/
    echo "Activate OSD.$OSD_ID"
    ceph-volume lvm activate $OSD_ID $OSD_FSID
    echo "Unset noout"
    ceph osd unset noout
    echo "Verify osd is back up before continuing"
    OSD_STATE=$(ceph osd tree --format json | jq --arg id "$OSD_ID" -r '.nodes[] | select(.id == ($id |tonumber)) | .status')
    echo "OSD_STATE:  $OSD_STATE"
    while [ "$OSD_STATE" != "up" ]; do
        echo "Warning: OSD.$OSD_ID is not UP yet. Waiting..."
        sleep 2
        OSD_STATE=$(ceph osd tree --format json | jq --arg id "$OSD_ID" -r '.nodes[] | select(.id == ($id |tonumber)) | .status')
        echo "OSD_STATE:  $OSD_STATE"
    done 
    echo "----------------------------------------------------------------------------------"
    echo "OSD $OSD_ID migration complete."
    echo "----------------------------------------------------------------------------------"
done
echo "----------------------------------------------------------------------------------"
echo "Migration complete. The old DB device has NOT been wiped."
echo "----------------------------------------------------------------------------------"
### END OF JOURNAL MIGRATION ###