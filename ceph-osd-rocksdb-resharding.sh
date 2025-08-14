#!/bin/bash
#rocksdb-resharding

ceph osd set noout

for i in $(ceph osd ls-tree $(hostname -s)); do
    echo "Resharding OSD $i"
    OSD_DIR="/var/lib/ceph/osd/ceph-$i";
    if [ ! -d "$OSD_DIR" ]; then
        echo "$OSD_DIR does not exist on $(hostname -s), skipping"
        continue
    fi
    echo "$OSD_DIR exists on $(hostname -s), running reshard"
    set -x
    systemctl stop ceph-osd@$i
    ceph-bluestore-tool --path $OSD_DIR fsck
    ceph-bluestore-tool --path $OSD_DIR --sharding="m(3) p(3,0-12) O(3,0-13)=block_cache={type=binned_lru} L P" reshard
    ceph-bluestore-tool --path $OSD_DIR show-sharding
    ceph-bluestore-tool --path $OSD_DIR fsck
    systemctl start ceph-osd@$i
    set +x
done
ceph osd unset noout
