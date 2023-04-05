#!/bin/bash
#Spencer MacPhee <smacphee@45drives.com>
#ceph.dir.rbytes exporter

#Usage: Define a series of cephFS directories to monitor size over time. 

#List of directories to monitor (User inputted)
dirs=("/path/example" "/path/example")

#Define where to output (typically a node_exporter text directory)
output_file="/var/lib/node_exporter/cephdir.prom"

#Ensure file is empty before writing (prevents duplicate entries into metris)
> "$output_file"

for dir in "${dirs[@]}"
do
    #format ceph rbyte into prometheus data format
    output=$(getfattr -n ceph.dir.rbytes "$dir")

    file=$(echo "$output" | awk -F ": " '/file:/ {print "\"" $2 "\""}')
    value=$(echo "$output" | awk -F "=" '/ceph.dir.rbytes/ {print $2}' | tr -d '"' )

    echo "ceph_dir_size{directory=$file} $value" >> "$output_file"
done
