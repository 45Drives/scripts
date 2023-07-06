import os
import json
import time
import subprocess
from hashlib import sha1

# which cluster and dir to shard?
topdir = input('Which top level directory do you want to shard? (This will loop through all sub dirs and pin each to a different MDS) ')

# get the max_mds setting
fs_dump = subprocess.check_output("ceph fs dump --format json 2>/dev/null", shell=True)
max_mds = json.loads(fs_dump)["filesystems"][0]["mdsmap"]["max_mds"]

# iterate over the immediate subdirs and pin them
for dir in sorted(os.listdir(topdir)):
    full_dir_path = os.path.join(topdir, dir)

    if not os.path.isdir(full_dir_path):
        continue

    # wait for health ok
    while not "HEALTH_OK" in subprocess.check_output("ceph health 2>/dev/null", shell=True).decode():
        print("Waiting 10s for HEALTH_OK...")
        time.sleep(10)

    # do a consistent hash(${dir}) modulo max_mds
    dir_hash = int(sha1(dir.encode()).hexdigest(), 16)
    pin = dir_hash % max_mds

    # substitute -1 for 0 -- assuming the parent is already pinned to 0
    if pin == 0:
        pin = -1

    # pin the dir
    print(f"Pinning {dir} to {pin}")
    subprocess.run(f'setfattr -n ceph.dir.pin -v {pin} {full_dir_path}', shell=True)

    time.sleep(1)

