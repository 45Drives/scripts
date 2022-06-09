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

while getopts 'b:fo:d:h' OPTION; do
    case ${OPTION} in
    b)
        DB_NEW_SIZE=${OPTARG}
        DB_NEW_SIZE_BYTES=$(numfmt --from=iec $DB_NEW_SIZE)
        ;;
    d)
        DB_DEVICE=${OPTARG}
        if [ ! -b $DB_DEVICE ];then
            echo "Error: DB_DEVICE=$DB_DEVICE is not a block device"
            exit 1
        fi
        ;;
    # o)
    #     OSD_LIST_=${OPTARG}
    #     IFS=',' read -r -a OSD_LIST <<< "$OSD_LIST_"
    #     ;;
    h)
        usage
        ;;
    esac
done


echo $DB_NEW_SIZE_BYTES
echo $DB_DEVICE
# check if device has any lv devices and if they belong to an osd
# for each lv device get osd id and add to array

# get 