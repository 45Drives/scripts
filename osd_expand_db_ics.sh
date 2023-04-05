usage() { # Help
cat << EOF
    Usage:	
        [-o] Encrypted OSDs to expand DBs. List separted by commas, i.e. 2,3,4,5.
        [-h] Displays this message
EOF
    exit 0
}


while getopts ":o:h" OPTION; do
    case ${OPTION} in 
    o) 
        OSD_LIST_=${OPTARG}
        IFS=',' read -r -a OSD_LIST <<< "$OSD_LIST_"
        ;;
    h)
        usage
        ;;
    esac
done

for i in "${!OSD_LIST[@]}"; do

    OSD_ID=${OSD_LIST[i]}

    CEPH_STATUS=$(ceph health --format json | jq -r '.status')
    while [ "$CEPH_STATUS" != "HEALTH_OK" ]; do
        echo "Warning: Cluster is not in HEALTH_OK state"
        sleep 2
        CEPH_STATUS=$(ceph health --format json | jq -r '.status')
    done

    echo "Set noout flag"
    ceph osd set noout

    echo "Stopping OSD.$OSD_ID"
    systemctl stop ceph-osd@$OSD_ID

    echo "Expanding journal DB size"
    ceph-bluestore-tool bluefs-bdev-expand --path /var/lib/ceph/osd/ceph-$OSD_ID/

    echo "Migrating data from block device to DB"
    ceph-bluestore-tool bluefs-bdev-migrate --path /var/lib/ceph/osd/ceph-$OSD_ID/ --devs-source /var/lib/ceph/osd/ceph-$OSD_ID/block --dev-target /var/lib/ceph/osd/ceph-$OSD_ID/block.db

    echo "Starting OSD.$OSD_ID"

    systemctl start ceph-osd@$OSD_ID
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
done