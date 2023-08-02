#!/usr/bin/env python3
# Mitch Hall
# 45Drives
# Version 1.1 - July 31/23
import os
import json
import time
import argparse
import subprocess
import re

def main():
    parser = argparse.ArgumentParser(description='Shard directories and pin each to a different MDS.')
    parser.add_argument('-d', '--dir', help='The top-level directory to shard.')
    parser.add_argument('-D', '--dry-run', action='store_true', help='Run the script in dry run mode. No actions will be performed.')
    args = parser.parse_args()

    if args.dir:
        # wait for health ok
        while not "HEALTH_OK" in subprocess.check_output("ceph health 2>/dev/null", shell=True).decode():
            print("Waiting 10s for HEALTH_OK...")
            time.sleep(10)

        # get max_mds info
        fs_dump = subprocess.check_output("ceph fs dump --format json 2>/dev/null", shell=True)
        max_mds = json.loads(fs_dump)["filesystems"][0]["mdsmap"]["max_mds"]

        # loop through the dirs and pin to available MDS
        dirs = sorted([d for d in os.listdir(args.dir) if os.path.isdir(os.path.join(args.dir, d))])
        
        next_mds = 0

        for dir in dirs:
            full_dir_path = os.path.join(args.dir, dir)

            # check if MDS already pinned
            pinned_mds = subprocess.check_output(f'getfattr -n ceph.dir.pin "{full_dir_path}" 2>/dev/null', shell=True).decode()

            if "ceph.dir.pin" in pinned_mds:
                current_mds = re.search('ceph.dir.pin="(.*)"', pinned_mds).group(1)
                if current_mds != "-1":
                    print(f"{dir} is already pinned by MDS {current_mds}")
                else:
                    if args.dry_run:
                        # print the action to be performed
                        print(f"Would pin {dir} to {next_mds} - Remove dry run flag to set")
                    else:
                        # pin the dir
                        print(f"Pinning {dir} to MDS {next_mds}")
                        subprocess.run(f'setfattr -n ceph.dir.pin -v {next_mds} "{full_dir_path}"', shell=True)
                    next_mds = (next_mds + 1) % max_mds
                    time.sleep(1)
            else:
                if args.dry_run:
                    # print the action to be performed
                    print(f"Would pin {dir} to {next_mds} - Remove dry run flag to set")
                else:
                    # If ceph.dir.pin is not present, pin the dir
                    print(f"Pinning {dir} to MDS {next_mds}")
                    subprocess.run(f'setfattr -n ceph.dir.pin -v {next_mds} "{full_dir_path}"', shell=True)
                next_mds = (next_mds + 1) % max_mds
                time.sleep(1)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()

