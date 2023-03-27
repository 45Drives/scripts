#!/bin/bash
#Spencer MacPhee <smacphee@45drives.com>
#ceph.dir.rbytes exporter

#user defined variables
export_dir="/var/lib/node_exporter"
export_file="default.prom"

#ensure tmp files are empty 
> totaldirs.txt
> workfile.txt
> ${export_dir}/${export_file}


#Finding top level dirs. 
cephfs-shell ls | tr ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^[[:space:]]*$' | sed 's/\///g' | sed 's/\x1b\[[0-9;]*m//g' > workfile.txt
while read line; do
  cephfs-shell ls $line | tr ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^[[:space:]]*$' | sed 's/\///g' | sed 's/\x1b\[[0-9;]*m//g' | sed "s|^|$line/|" >> totaldirs.txt
done < workfile.txt

#finding one sub dir level
while read line; do
  rbyte=$(cephfs-shell getxattr "$line" ceph.dir.rbytes 2>/dev/null)
  echo "ceph_dir_rbyte{directory=\"${line}\"} ${rbyte}" >> "${export_dir}/${export_file}"
done < totaldirs.txt
sed -i '/^[^0-9]*$/d' "${export_dir}/${export_file}"
#> totaldirs.txt