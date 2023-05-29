#!/usr/bin/env python3

#Brett Kelly <bkelly@45drives.com> 2023

import sys
import argparse
import concurrent.futures
import subprocess
import json
import os
import re

def process_inode(inode, pool_name):
    if validate_inode(inode):
        obj = inode + ".00000000"
        command = f"rados -p {pool_name} getxattr {obj} parent | ceph-dencoder type inode_backtrace_t import - decode dump_json"
        result = subprocess.run(command, shell=True, stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if result.returncode == 0:
            inode_backtrace_json = json.loads(result.stdout)
            file_path_json = inode_backtrace_json['ancestors']
            num_elements = len(file_path_json)
            path_elements = []
            itr = num_elements - 1
            while itr >= 0:
                path_elements.append(file_path_json[itr]['dname'])
                itr -= 1
            file_path = os.path.join('/', *path_elements)
            print(file_path)
        else:
            print("Object " + "'"+ obj + "'" + " has no backtrace info present", file=sys.stderr)
    else:
        print("Inode " + "'"+ inode + "'" + " is not in valid format (11 digit hex), ignoring...", file=sys.stderr)

def distribute_inodes(file_path, num_threads, pool_name):
    with open(file_path, 'r') as file:
        inodes = file.readlines()
        inodes = [inode.strip() for inode in inodes]

    with concurrent.futures.ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = [executor.submit(process_inode, inode, pool_name) for inode in inodes]
        concurrent.futures.wait(futures)

def validate_inode(inode):
    pattern = r"^[0-9A-Fa-f]{11}$"
    return re.match(pattern, inode)

if __name__ == '__main__':
    if os.geteuid() != 0:
        print("This script requires root privileges", file=sys.stderr)
        sys.exit(1)

    parser = argparse.ArgumentParser(description='Distribute inodes across threads.')
    parser.add_argument('-i', '--input_file', help='File path, Required if not using -o')
    parser.add_argument('-o', '--object_name', help='Object Name, Required if not using -i')
    parser.add_argument('-n', '--num_threads', type=int, help='Number of threads, Optional defaults to 16')
    parser.add_argument('-p', '--pool_name', help='Name of RADOS pool, Required')

    args = parser.parse_args()

    if not args.input_file and not args.object_name or not args.pool_name:
        parser.print_help()
        sys.exit(1)

    if not args.num_threads:
        num_threads = 16
    else:
        num_threads = args.num_threads
    
    pool_name = args.pool_name

    if not os.path.isfile("/etc/ceph/ceph.client.admin.keyring"):
        print("This script requires ceph admin.keyring be present", file=sys.stderr)
        sys.exit(1)

    if args.input_file:
        file_path = args.input_file
        distribute_inodes(file_path, num_threads, pool_name)
    if args.object_name:
        # If given a single object name, split into inode and chunk and process_inode directly bypass threading
        object_name = args.object_name
        inode = object_name.split('.')
        process_inode(inode[0], pool_name)

