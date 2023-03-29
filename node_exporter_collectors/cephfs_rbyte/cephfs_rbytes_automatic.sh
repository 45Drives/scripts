#!/bin/bash
#ceph.dir.rbytes exporter
#Gets top level directories, and one layer lower to monitor for ceph dir sizes. 

#user defined variables
export_dir="/var/lib/node_exporter"
export_file="default.prom"

#ensure prometheus dir is empty 
> ${export_dir}/${export_file}

prev_top_level_dirs="prev_top_level.txt"

#Finding top level dirs. 
cephfs-shell ls | tr ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^[[:space:]]*$' | sed 's/\///g' | sed 's/\x1b\[[0-9;]*m//g' > workfile.txt

# If the previous top level file exists and the contents match, print a message
if [ -f "$prev_top_level_dirs" ] && diff -q "$prev_top_level_dirs" "workfile.txt" > /dev/null; then
    echo "Top level list hasn't changed."
else
    # If the contents don't match, process the list and update the previous top level file
    while read top_dir; do
      cephfs-shell ls $top_dir | tr ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^[[:space:]]*$' | sed 's/\///g' | sed 's/\x1b\[[0-9;]*m//g' | sed "s|^|$top_dir/|" >> totaldirs.txt
    done < workfile.txt
    # Update the previous top level list
    cp "workfile.txt" "$prev_top_level_dirs"
fi

#finding one sub dir level size
while read sub_dir; do
  rbyte=$(cephfs-shell getxattr "$sub_dir" ceph.dir.rbytes 2>/dev/null)
  echo "ceph_dir_rbyte{directory=\"${sub_dir}\"} ${rbyte}" >> "${export_dir}/${export_file}"
done < totaldirs.txt
sed -i '/^[^0-9]*$/d' "${export_dir}/${export_file}"