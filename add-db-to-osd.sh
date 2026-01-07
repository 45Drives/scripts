#!/bin/bash
# Brett Kelly Oct 2021
# Anthony D'Atri 2025-04-15
# 45Drives
# Version 1.4 stable

usage() { # Help
cat << EOF
    Usage:	
        [-b] Block DB size. Required. Allowed suffixes K,M,G,T
        [-d] Device to use for DB+WAL. Required. Aliased Device name should be used /dev/X-Y
        [-f] Bypass OSD per DB warning
        [-o] OSDs to which to add DB+WAL. Required. Comma separated list of osd.id. <0,1,2,3>
        [-r] Number of OSDs to share a given WAL+DB offload device, default is 5, which is
             appropriate for SAS/SATA SSD offload devices.  A value of 10 is usually reasonable
             for NVMe offload devices, but note that this number of OSDs will fail when the
             offload device fails.
        [-h] Displays this message
EOF
    exit 0
}

add_lv_tags(){
    get_lv_uuid(){
        local LV_UUID=$(lvs -o uuid $BLOCK_LV_DEVICE --no-headings | awk '{$1=$1};1')
        echo "$LV_UUID"
    }
    # Add block.db tags to existing block device
    lvchange --addtag "ceph.db_device=$DB_LV_DEVICE" $BLOCK_LV_DEVICE
    lvchange --addtag "ceph.db_uuid=$(get_lv_uuid $DB_LV_DEVICE)" $BLOCK_LV_DEVICE

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
	        echo "The required utility: ${SCRIPT_DEPENDENCIES[i]} is not installed"
            echo "The jq and bc utilities are required"
	        exit 1
        fi
    done
}

# Quit if we encounter any error, so to not make anything even worse
set -e

SCRIPT_DEPENDENCIES=(bc jq)
FORCE="false"
PHYSICAL_EXTENT_SIZE_BYTES=4194304
OSD_PER_DB_LIMIT=5

while getopts 'b:fo:d:hr:' OPTION; do
    case ${OPTION} in
    b)
        BLOCK_DB_SIZE=${OPTARG}
        BLOCK_DB_SIZE_BYTES=$(numfmt --from=iec $BLOCK_DB_SIZE)
        ;;
    d)
        DB_DEVICE=${OPTARG}
        if [ ! -b $DB_DEVICE ];then
            echo "Error: DB_DEVICE=$DB_DEVICE is not a block device"
            exit 1
        fi
        ;;
    f)
        FORCE="true"
        ;;
    o)
        OSD_LIST_=${OPTARG}
        IFS=',' read -r -a OSD_LIST <<< "$OSD_LIST_"
        ;;
    r)
	OSD_PER_DB_LIMIT=${OPTARG}
        case $OSD_PER_DB_LIMIT in
          ''|*[!0-9]*) echo "OSDs per DB device ratio must be an integer" ; exit 1 ;;
        esac
	;;
    h)
        usage
        ;;
    esac
done

# Check if correct input was given
if [ -z $OSD_LIST ] || [ -z $DB_DEVICE ] || [ -z $BLOCK_DB_SIZE_BYTES ]; then
    echo "Input required. See ./`basename "$0"` -h for usage details"
    exit 1
fi

# Check CLI depandencies
check_dependencies

BLOCK_DB_SIZE_EXTENTS=$(bc <<< "$BLOCK_DB_SIZE_BYTES/$PHYSICAL_EXTENT_SIZE_BYTES")
OSD_COUNT="${#OSD_LIST[@]}"
TOTAL_DB_SIZE_BYTES=$(bc <<< "$BLOCK_DB_SIZE_BYTES*$OSD_COUNT")
DB_DEVICE_SIZE_BYTES=$(blockdev --getsize64 $DB_DEVICE)

# Check if LVM info is already present on DB_DEVICE

# check with wipefs that device has LVM data present
DB_DEVICE_SIGNATURE=$(wipefs "$DB_DEVICE" --json | jq -r '.signatures | .[0].type // empty')
# If this is empty the disk is assumed new.
# If this is LVM2_member the disk is assumed to already have a DB LV present it
# If anything else the disk is assumed to have something else on it and should be wiped. Quit with warning
if [ -z "$LVM_JSON_DEVICE" ] || [ "$DB_DEVICE_SIGNATURE" == "LVM2_member" ]; then
    :
else
    echo "Device is neither empty nor an LV device. Wipe the device and run again"
    exit 1
fi

# Get PV info for the specific disk we want
LVM_JSON=$(pvs --units B --nosuffix -o name,vg_name,lv_name,lv_count,lvsize,vg_free --reportformat json ) 
LVM_JSON_DEVICE=$(echo $LVM_JSON | jq --arg disk "$DB_DEVICE" '.[] |.[].pv | .[] | select(.pv_name==$disk)')

# Ensure that we are using the correct device
# if DB_DEVICE_SIGNATURE is LVM2_member and LVM_JSON_DEVICE is empty, then the wrong disk name was used (sd name instead of alias). Quit with warning 
if [ "$DB_DEVICE_SIGNATURE" == "LVM2_member" ] && [ -z "$LVM_JSON_DEVICE" ];then
    echo "WARNING: device selected ($DB_DEVICE) has an LVM signature, but could not get LVM info."
    echo "Wrong device name was most likely provided, use the device alias name instead of the Linux device name"
    exit 1
fi

# Are we using an existing DB device or a new device? if LVM_JSON_DEVICE is empty and DB_DEVICE_SIGNATURE is empty we have an empty device
if [ -z "$LVM_JSON_DEVICE" ] && [ -z "$DB_DEVICE_SIGNATURE" ];then
    DB_VG_NAME="ceph-$(uuidgen)"
else
    # If not how do we get db_VG ? Derive from device given
    DB_VG_NAME="$(echo $LVM_JSON_DEVICE | jq -r '.vg_name' | awk 'NR==1')"
    # If there is no DB Volume group quit with warning. The disk has a LVM2_memebr signature but no volume group. Wipe device and run again.
    if [ -z $DB_VG_NAME ];then
        echo "WARNING: Device selected ($DB_DEVICE) has an LVM2_member signature, but no volume group"
        echo "Wipe the device and run again"
        exit 1
    fi
    # Count how many LV DBs are present, add that to input OSDs and compare to OSD_LIMIT
    EXISTING_DB_COUNT=$(echo $LVM_JSON_DEVICE | jq -r '.lv_count' | awk 'NR==1')
    echo "WARNING: device currently has $EXISTING_DB_COUNT dbs present"
    OSD_COUNT=$(bc <<< "${#OSD_LIST[@]}+$EXISTING_DB_COUNT")
    # set DB total device size to the amount of free Bytes in the volume group
    DB_DEVICE_DISK_SIZE_BYTES=$(echo $LVM_JSON_DEVICE | jq -r '.vg_free' | awk 'NR==1')
fi

# Check if OSD_COUNT is greater than OSD_PER_DB_LIMIT, exit with warning. 
# If -f flag present the ignore OSD_PER_DB_LIMIT
if [ "$FORCE" == "false" ] ; then
    if [ "$OSD_COUNT" -gt "$OSD_PER_DB_LIMIT" ];then
        echo "Warning: OSD_COUNT is greater than OSD_PER_DB_LIMIT=$OSD_PER_DB_LIMIT. Use -f to bypass"
        exit 1
    fi
fi

# Check if total size of DBs to be created will fit on DB device
if [ "$TOTAL_DB_SIZE_BYTES" -gt "$DB_DEVICE_SIZE_BYTES" ] ; then
    echo "Warning: total size of db will not fit on device $DB_DEVICE"
    exit 1
fi

# Check each OSD to see if it present on host
# Check each OSD to see if it already has a DB device
# Check current BlueStore DB size and compare to supplied DB size
# Gather ceph-volume output before entering loop as it takes a while to run

CEPH_VOLUME_JSON=$(ceph-volume lvm list --format json)
for i in "${!OSD_LIST[@]}"; do
    OSD_ID=${OSD_LIST[i]}
    OSD_JSON=$(echo $CEPH_VOLUME_JSON | jq -r --arg id "$OSD_ID" '.[] | .[] | select(.tags["ceph.osd_id"]==$id)')
    if [ -z "$OSD_JSON" ]; then
        echo "Can't find osd.$OSD_ID on this host"
        exit 1
    fi
    DB_CHECK=$(echo $OSD_JSON | jq 'select(.tags["ceph.db_device"])');
    if [ ! -z "$DB_CHECK" ]; then
        echo "Warning: osd.$OSD_ID already has a DB device attached"
        exit 1
    fi
    CURRENT_BLOCK_DB_USED_BYTES=$(ceph daemon osd.$OSD_ID perf dump | jq '.bluefs | .db_used_bytes')
    if [[ "$CURRENT_BLOCK_DB_USED_BYTES" -ge "$BLOCK_DB_SIZE_BYTES" ]];then
        echo "Warning: osd.$OSD_ID has CURRENT_BLOCK_DB_USED_BYTES($(numfmt --to=iec $CURRENT_BLOCK_DB_USED_BYTES)). This must be less than BLOCK_DB_SIZE_BYTES($(numfmt --to=iec $BLOCK_DB_SIZE_BYTES))"
        exit 1
    fi
done

# Make sure the admin keyring is present with correct permissions
# Remove "set -e" so we can check ceph status error code
# Then turn it back on

set +e
ceph status > /dev/null 2>&1 ; rc=$?
set -e
if [[ "$rc" -ne 0 ]];then
    echo "Warning: permisson denied accessing cluster, admin keyring must be present"
    exit 1
fi

# If we got this far then all checks passed, so start the migration process

if [ -z "$LVM_JSON_DEVICE" ] && [ -z "$DB_DEVICE_SIGNATURE" ];then
    pvcreate $DB_DEVICE
    vgcreate $DB_VG_NAME $DB_DEVICE
fi

for i in "${!OSD_LIST[@]}"; do
    OSD_ID=${OSD_LIST[i]}
    OSD_JSON=$(echo $CEPH_VOLUME_JSON | jq -r --arg id "$OSD_ID" '.[] | .[] | select(.tags["ceph.osd_id"]==$id)')
    OSD_FSID=$(echo $OSD_JSON | jq -r '.tags["ceph.osd_fsid"]')

    DB_LV_UUID=$(uuidgen)
    DB_LV_DEVICE="/dev/$DB_VG_NAME/osd-db-$DB_LV_UUID"
    BLOCK_LV_DEVICE="$(echo $OSD_JSON | jq -r '.lv_path')"

    lvcreate -l $BLOCK_DB_SIZE_EXTENTS -n osd-db-$DB_LV_UUID $DB_VG_NAME

    chown -h ceph:ceph $DB_LV_DEVICE
    chown -R ceph:ceph $(realpath $DB_LV_DEVICE)

    # Don't continue unless the cluster is healthy

    CEPH_STATUS=$(ceph health --format json | jq -r '.status')
    while [ "$CEPH_STATUS" != "HEALTH_OK" ]; do
        echo "Warning: Cluster is not in HEALTH_OK state"
        sleep 2
        CEPH_STATUS=$(ceph health --format json | jq -r '.status')
    done

    OK_TO_STOP=$(ceph osd ok-to-stop $OSD_ID)
    if [[ $OK_TOP_STOP -ne 0 ]]; then
       echo "Error: stopping osd.$OSD_ID would result in data unavailability"
       exit 1
    fi

    echo "Set noout"
    ceph osd set noout
    echo "Stop OSD.$OSD_ID"
    systemctl stop ceph-osd@$OSD_ID
    echo "Create new DB"
    CEPH_ARGS="--bluestore-block-db-size $BLOCK_DB_SIZE_BYTES" ceph-bluestore-tool bluefs-bdev-new-db --path /var/lib/ceph/osd/ceph-$OSD_ID/ --dev-target $DB_LV_DEVICE
    echo "Migrate old DB to new DB"
    ceph-bluestore-tool bluefs-bdev-migrate --path /var/lib/ceph/osd/ceph-$OSD_ID/ --devs-source /var/lib/ceph/osd/ceph-$OSD_ID/block --dev-target /var/lib/ceph/osd/ceph-$OSD_ID/block.db
    echo "Update LV tags on block and DB devices"
    add_lv_tags
    echo "unmount OSD.$OSD_ID"
    umount /var/lib/ceph/osd/ceph-$OSD_ID/
    echo "Activate OSD.$OSD_ID"
    ceph-volume lvm activate $OSD_ID $OSD_FSID
    echo "Unset noout"
    ceph osd unset noout
    echo "Verify OSD is up before continuing"
    OSD_STATE=$(ceph osd tree --format json | jq --arg id "$OSD_ID" -r '.nodes[] | select(.id == ($id |tonumber)) | .status')
    echo "OSD_STATE:  $OSD_STATE"
    while [ "$OSD_STATE" != "up" ]; do
        echo "Warning: OSD.$OSD_ID is not UP yet. Waiting..."
        sleep 2
        OSD_STATE=$(ceph osd tree --format json | jq --arg id "$OSD_ID" -r '.nodes[] | select(.id == ($id |tonumber)) | .status')
        echo "OSD_STATE:  $OSD_STATE"
    done
done
