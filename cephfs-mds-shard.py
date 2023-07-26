#!/usr/bin/env python3
# Mitch Hall
# 45Drives
# Version 1.0 - July 6/23
import os
import json
import time
import subprocess
from hashlib import sha1

# find out which dir to shard
topdir = input('Which top level directory do you want to shard? (This will loop through all sub dirs and pin each to a different MDS) ')

# get max_mds info
fs_dump = subprocess.check_output("ceph fs dump --format json 2>/dev/null", shell=True)
max_mds = json.loads(fs_dump)["filesystems"][0]["mdsmap"]["max_mds"]

# loop through the dirs and pin to available MDS
dirs = sorted([d for d in os.listdir(topdir) if os.path.isdir(os.path.join(topdir, d))])
for i, dir in enumerate(dirs):
    full_dir_path = os.path.join(topdir, dir)

    # wait for health ok
    while not "HEALTH_OK" in subprocess.check_output("ceph health 2>/dev/null", shell=True).decode():
        print("Waiting 10s for HEALTH_OK...")
        time.sleep(10)

    # calculate the MDS rank
    mds_rank = i % max_mds

    # pin the dir
    print(f"Pinning {dir} to {mds_rank}")
    subprocess.run(f'setfattr -n ceph.dir.pin -v {mds_rank} "{full_dir_path}"', shell=True)
    time.sleep(1)
