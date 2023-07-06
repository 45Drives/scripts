#!/bin/bash
# Mitch Hall
# 45Drives
# Version 1.0 - July 6/23

# which cluster and dir to shard?
read -p 'Which top level directory do you want to shard? (This will loop through all sub dirs and pin each to a different MDS) ' topdir

# get the max_mds setting
max_mds=`ceph fs dump --format json 2>/dev/null | jq .filesystems[0].mdsmap.max_mds`

# cd to the dir to shard
cd $topdir

# iterate over the subdirs and pin them
for dir in `find . -mindepth 1 -maxdepth 1 -type d | sort`
do

    # wait for health ok
    until ceph health 2>/dev/null | grep -q HEALTH_OK
    do
       echo Waiting 10s for HEALTH_OK...
       sleep 10
    done

    # do a consistent hash(${dir}) modulo max_mds
    pin=`echo ${dir} | cksum | awk -v m=${max_mds} '{ print $1 % m }'`

    # substitute -1 for 0 -- assuming the parent is already pinned to 0
    if [ $pin == 0 ]
    then
        pin=-1
    fi
    # pin the dir
    echo Pinning ${dir} to ${pin}
    setfattr -n ceph.dir.pin -v ${pin} ${dir}

    sleep 1
done