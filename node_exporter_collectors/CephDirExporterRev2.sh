#!/bin/bash
#Spencer MacPhee <smacphee@45drives.com>
#ceph.dir.rbytes exporter

#getfattr -n ceph.dir.rbytes

#Usage:
#This script will output a prometheus valid string into a file, in order to do so
#the target cephfs directory must be passed as an argument, and the node exporter dir will be changed if it is not the default. 
#this script has no scheduling ability, it is advised to run it through cronjob, or similar tools.

#User defined variables
CephFSDir="$1"

#error handling if the input isnt given/ dir doesnt exist
if [ -z $CephFSDir ]; then
    echo "Undefined directory"
    exit 1
fi

if [ ! -d "$CephFSDir" ]; then
    echo "directory doesnt exist"
    exit 1
fi
NodeExporterDir="/var/lib/node_exporter"

#Processed directory name
CephFSDirName=$(echo $CephFSDir | awk -F/ '{print $NF}')

#Data collection and proper formatting
CephRbyte="$(getfattr -n ceph.dir.rbytes $CephFSDir | awk -F\" '{print $2}')"
PromLine="ceph_dir_size_${CephFSDirName}"
PromData="${PromLine} ${CephRbyte}"

#echo into file/create new file if necessary
echo $PromData > "${NodeExporterDir}/${CephFSDirName}.prom"