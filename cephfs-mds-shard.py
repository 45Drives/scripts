#!/usr/bin/env python3
# Matthew Hutchinson
# 45Drives
# Version 2 - May 07/24
import os
import json
import time
import argparse
import subprocess
import re
import sys

# Find pinned directories
def find_non_negative_ceph_dir_pin(starting_directory):
    non_negative_dirs = []

    def search_directory(directory):
        try:
            # Get ceph.dir.pin attribute value
            output = subprocess.run(["getfattr", "-n", "ceph.dir.pin", directory], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, check=True)
            pin_value = output.stdout.strip().split("=")[-1]
            if pin_value != '"-1"':
                non_negative_dirs.append((directory, pin_value))
            for sub_dir in os.listdir(directory):
                sub_dir_path = os.path.join(directory, sub_dir)
                if os.path.isdir(sub_dir_path):
                    search_directory(sub_dir_path)
        except subprocess.CalledProcessError as e:
            pass  # Ignore errors for directories without ceph.dir.pin attribute

    # Start the search from the subdirectories of the starting directory
    for sub_dir in os.listdir(starting_directory):
        sub_dir_path = os.path.join(starting_directory, sub_dir)
        if os.path.isdir(sub_dir_path):
            search_directory(sub_dir_path)

    return non_negative_dirs

# Removes pin on Dirs  
def repin_directories(non_negative_directories):
    for directory, pin_value in non_negative_directories:
        print(f"Directory: {directory}, ceph.dir.pin value: {pin_value}")
    if non_negative_directories:
        choice = input("Do you want to remove the pin on these directories? (yes/no): ")
        if choice.lower() == "yes":
            for directory, _ in non_negative_directories:
                subprocess.run(["setfattr", "-n", "ceph.dir.pin", "-v", "-1", directory])
            print("Directories repinned successfully.")
        else:
            print("No changes made.")

# List pinned Dirs
def list_dir(starting_directory):
    non_negative_directories = find_non_negative_ceph_dir_pin(starting_directory)
    if non_negative_directories:
        print("Directories that are already pinned:")
        for directory, pin_value in non_negative_directories:
            print(f"Directory: {directory}, ceph.dir.pin value: {pin_value}")      
    else:
        print("No directories pinned found.")  
    return (non_negative_directories)


# Main fuction to run
def main():
    parser = argparse.ArgumentParser(description='Shard directories and pin each to a different MDS.')
    parser.add_argument('-d', '--dir', help='The top-level directory to shard.')
    parser.add_argument('-D', '--dry-run', action='store_true', help='Run the script in dry run mode. No actions will be performed.')
    parser.add_argument('-F', '--force', action='store_true', help='Ignore existing pins')
    parser.add_argument('-l', '--list', action='store_true', help='Lists pinned directories')
    parser.add_argument('-r', '--remove', action='store_true', help='Remove pin on pinned directories')
    parser.add_argument('-m', '--next_mds', help='Specify the next MDS to start with')
    args = parser.parse_args()

    if args.dir:
        # wait for health ok
        while not "HEALTH_OK" in subprocess.check_output("ceph health 2>/dev/null", shell=True).decode():
            print("Waiting 10s for HEALTH_OK...")
            time.sleep(10)
        # List Pinned Directories
        if args.list and not args.remove:
            dirs_to_repin=list_dir(args.dir)
        # Removed Pins from Dirs 
        if args.remove:
            dirs_to_repin=list_dir(args.dir)
            repin_directories(dirs_to_repin)
        # get max_mds info
        fs_dump = subprocess.check_output("ceph fs dump --format json 2>/dev/null", shell=True)
        max_mds = json.loads(fs_dump)["filesystems"][0]["mdsmap"]["max_mds"]

        # loop through the dirs and pin to available MDS
        dirs = sorted([d for d in os.listdir(args.dir) if os.path.isdir(os.path.join(args.dir, d))])
        
        # Specify what MDS to start with, if none start at 0
        if args.next_mds and int(args.next_mds) < max_mds:
            next_mds = int(args.next_mds) #if args.next_mds > max_mds else 0
        elif args.next_mds: 
            choice = input("MDS defined is higher then Max MDS, Do you want to start at 0? (yes/no): ")
            if choice.lower() == "yes":
                next_mds = 0
            else:
                sys.exit()
        else:
            next_mds = 0

        if not (args.list or args.remove):
            for dir in dirs:
                full_dir_path = os.path.join(args.dir, dir)

                # check if MDS already pinned
                pinned_mds = subprocess.check_output(f'getfattr -n ceph.dir.pin "{full_dir_path}" 2>/dev/null', shell=True).decode()

                if "ceph.dir.pin" in pinned_mds:
                    current_mds = re.search('ceph.dir.pin="(.*)"', pinned_mds).group(1)
                    if current_mds != "-1" and not args.force :
                        print(f"{dir} is already pinned by MDS {current_mds}")
                    else:
                        if args.dry_run:
                        # print the action to be performed
                            print(f"Would pin {dir} to {next_mds} - Remove dry run flag to set")
                        else:
                        # pin the dir
                            print(f"Pinning {dir} to MDS {next_mds}")
                            subprocess.run(f'setfattr -n ceph.dir.pin -v {next_mds} "{full_dir_path}"', shell=True)
                        next_mds = str((int(next_mds) + 1) % max_mds)
                        time.sleep(1)
                else:
                    if args.dry_run:
                    # print the action to be performed
                        print(f"Would pin {dir} to {next_mds} - Remove dry run flag to set")
                    else:
                    # If ceph.dir.pin is not present, pin the dir
                        print(f"Pinning {dir} to MDS {next_mds}")
                        subprocess.run(f'setfattr -n ceph.dir.pin -v {next_mds} "{full_dir_path}"', shell=True)
                    next_mds = str((int(next_mds) + 1) % max_mds)
                    time.sleep(1)    
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
