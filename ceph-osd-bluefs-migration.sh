#!/bin/bash
#bluefs migration

for i in $(ceph osd ls-tree $(hostname -s)); do
    echo "Migrating BlueFS from slow to db on OSD $i"
    OSD_DIR="/var/lib/ceph/osd/ceph-$i";
    if [ ! -d "$OSD_DIR" ]; then
        echo "$OSD_DIR does not exist on $(hostname -s), skipping"
        continue
    fi
    echo "$OSD_DIR exists on $(hostname -s), running BlueFS migration from slow to db"
    set -x
    systemctl stop ceph-osd@$i
    ceph-bluestore-tool bluefs-bdev-migrate --path $OSD_DIR --devs-source $OSD_DIR/block --dev-target $OSD_DIR/block.db
    systemctl start ceph-osd@$i
    set +x
done

echo "It is recommended to run an OSD compaction after this process on each OSD"
