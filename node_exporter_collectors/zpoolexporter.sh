#!/bin/bash
#Spencer MacPhee <smacphee@45drives.com>
#zpool health status text collector

#Usage:
#This script will output a prometheus valid string into a file, in order to do so
#the state field of zpool status will be collected and formatted. A text-collector dir will need to be set
#in node_exporters systemd service.

#User defined variables
NodeExporterDir="/var/lib/node_exporter"

#grab a relevant zpool status
status=$(zpool status | grep -o -m 1 "state: DEGRADED\|OFFLINE\|UNAVAIL")
poolstatus=$(echo $status | awk -F: '{print $NF}')
if [ -z "$poolstatus" ]
then
        dvalue="0"
        state="ONLINE"
else
        dvalue="1"
        state=$(echo $poolstatus | awk '{ gsub(/ /,""); print }')
fi

#echo into/create new prom file
echo "zpool_status""{""state=""\"$state\"""}" "$dvalue" > "${NodeExporterDir}/zpool_status.prom"
