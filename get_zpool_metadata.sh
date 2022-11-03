#!/bin/bash

if [ $# -eq 0 ]; then
    echo "No arguments provided"
    echo "Use pool name as input, bash get_zfs_metadata.sh poolname"
    exit 1
fi

POOL_NAME=$1

if zpool status $POOL_NAME &>/dev/null; then
	echo "pool exists continueing"
else
	echo "pool does nto exists"
	exit 1
fi

zdb -PLbbbs $POOL_NAME | tee ~/$POOL_NAME.zdb

cat ~/$1.zdb \
| grep -B 9999 'L1 Total' \
| grep -A 9999 'ASIZE' \
| grep -v \
 -e 'L1 object array' -e 'L0 object array' \
 -e 'L1 bpobj' -e 'L0 bpobj' \
 -e 'L2 SPA space map' -e 'L1 SPA space map' -e 'L0 SPA space map' \
 -e 'L5 DMU dnode' -e 'L4 DMU dnode' -e 'L3 DMU dnode' -e 'L2 DMU dnode' -e 'L1 DMU dnode' -e 'L0 DMU dnode' \
 -e 'L0 ZFS plain file' -e 'ZFS plain file' \
 -e 'L2 ZFS directory' -e 'L1 ZFS directory' -e 'L0 ZFS directory' \
 -e 'L3 zvol object' -e 'L2 zvol object' -e 'L1 zvol object' -e 'L0 zvol object' \
 -e 'L1 SPA history' -e 'L0 SPA history' \
 -e 'L1 deferred free' -e 'L0 deferred free' \
| awk \
 '{sum+=$4} \
 END {printf "\nTotal Metadata\n %.0f Bytes\n" " %.2f GiB\n",sum,sum/1073741824}' \
