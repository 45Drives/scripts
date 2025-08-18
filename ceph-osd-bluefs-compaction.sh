#!/bin/bash
#bluefs migration

for i in $(ceph osd ls-tree $(hostname -s)); do
    echo "Migrating BlueFS compaction on OSD $i"
    OSD_DIR="/var/lib/ceph/osd/ceph-$i";
    if [ ! -d "$OSD_DIR" ]; then
        echo "$OSD_DIR does not exist on $(hostname -s), skipping"
        continue
    fi
    echo "$OSD_DIR exists on $(hostname -s), running BlueFS compaction"
    set -x
    systemctl stop ceph-osd@$i
    ceph-kvstore-tool bluestore-kv $OSD_DIR compact
    systemctl start ceph-osd@$i
    set +x
done
