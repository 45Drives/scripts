#!/usr/bin/env python3

# Written by Mike McPhee, Dec 2022. 
# 45Drives 

import re
import os
import sys
import json
import syslog
import subprocess

def processLog2(userdict: dict, connectionActions: dict):

    #obj = {}
    username = userdict["username"]
    localmachine = userdict["localmachine"]
    ipaddress = userdict["ipaddress"]

    
    if ipaddress not in connectionActions:
        connectionActions[ipaddress]={}


    # if username not in obj:
    #     obj[username] = {}

    if localmachine not in connectionActions[ipaddress]:
        connectionActions[ipaddress][localmachine] = {}

    if username not in connectionActions[ipaddress][localmachine]:
        connectionActions[ipaddress][localmachine][username] = {}
        connectionActions[ipaddress][localmachine][username]["count"]= 0
        connectionActions[ipaddress][localmachine][username]["actions"]= []
        connectionActions[ipaddress][localmachine][username]["paths"]={}

        
    connectionActions[ipaddress][localmachine][username]["count"]+=1
    connectionActions[ipaddress][localmachine][username]["actions"].append({
        "sharename":userdict["sharename"],
        "action":userdict["action"].strip('\n'),
        "date":userdict["date"]
    })

    raw = userdict["action"].strip('\n').split('|')
    #print(raw)
    for path in raw:
        path = path.strip('\n')

        #we only want filepaths beginning with "/"
        #if "/" in path:  
        if path.startswith("/"):
            #print(path)
            if path not in connectionActions[ipaddress][localmachine][username]["paths"]:
                connectionActions[ipaddress][localmachine][username]["paths"][path]=0
            connectionActions[ipaddress][localmachine][username]["paths"][path]+=1

    


def main():

    linelist = []
    connectionActions = {}

    process = subprocess.Popen("cat /var/log/samba/smb_audit.log | grep 'openat|ok|w'", stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8', shell=True)
    #process = subprocess.Popen("cat /var/log/samba/smb_audit.log | awk '{$1print $6, $8, $10, $12, $14, $16}'", stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8', shell=True)

    line = process.stdout.readline()
    #if line is not null, process it into a dict object
    while line:
        #print(line)
        #example output: IP:192.168.209.99 USER:user MACHINE:45dr-mmcphee SHARENAME:share DATE:2022/12/14 ACTION:|create_file|ok|0x80|file|open|/tank/samba/share
        
        line = line.split('???')
        entry = {"ipaddress":None, "username": None, "localmachine": None, "sharename": None, "date": None, "action": None}
        
        entry["ipaddress"]=line[1]
        entry["username"]=line[2]
        entry["localmachine"]=line[3]
        entry["sharename"]=line[4]
        entry["date"]=line[5]
        entry["action"]=line[6]
        

        linelist.append(entry)
        #linelist.append(filepaths)#

        line = process.stdout.readline()



    for line in linelist:
        #print("processing log\n")

        processLog2(line, connectionActions)
        
    #print("\n",json.dumps(connectionActions, indent=4))
    print("#HELP smb_audit_log_count Number of times each username/machine/ip combination appears in the smb audit log")
    print("#TYPE smb_audit_log_count counter\n")
    for ip in connectionActions:
        machines = connectionActions[ip]
        #print("\n",json.dumps(key, indent=4))
        #print("\n",ip )
        for machine in machines:
            users = machines[machine]
            for user in users:
                data = users[user]
                
                print(f"smb_audit_log_count{{IP={ip},MACHINE={machine},USER={user}}} {data['count']}")
                # for key in data["paths"]:
                #    print(f"\t{key} {data['paths'][key]}")
                

    

if __name__ == "__main__":
    main()