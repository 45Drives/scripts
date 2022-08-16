#!/bin/bash
#Spencer MacPhee <smacphee@45drives.com>
#ceph.dir.rbytes exporter

#getfattr -n ceph.dir.rbytes

#Usage:
#This script will output a prometheus valid string into a file, in order to do so
#the target CephFS directory for monitoring, as well as the enabled textcollector directory
#this script has no scheduling ability, it is advised to run it through cronjob, or similar tools.

#User defined variables
CephFSDir="/mnt/example/share
NodeExporterDir="/var/lib/node_exporter"

#Processed directory name
CephFSDirName=$(echo $CephFSDir | awk -F/ '{print $NF}')

#Data collection and proper formatting
CephRbyte="$(getfattr -n ceph.dir.rbytes $CephFSDir | awk -F\" '{print $2}')"
PromLine="ceph_dir_size_${CephFSDirName}"
PromData="${PromLine} ${CephRbyte}"

#echo into file/create new file if necessary
echo $PromData > "${NodeExporterDir}/${CephFSDirName}.prom"


