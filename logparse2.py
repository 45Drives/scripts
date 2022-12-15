#!/usr/bin/env python3


import re
import os
import sys
import json
import syslog
import subprocess

def processLog2(userdict: dict, obj: dict) -> list:

    #obj = {}
    username = userdict["username"]
    localmachine = userdict["localmachine"]
    ipaddress = userdict["ipaddress"]
    
    if ipaddress not in obj:
        obj[ipaddress]={}


    # if username not in obj:
    #     obj[username] = {}

    if localmachine not in obj[ipaddress]:
        obj[ipaddress][localmachine] = {}

    if username not in obj[ipaddress][localmachine]:
        obj[ipaddress][localmachine][username] = {}
        obj[ipaddress][localmachine][username]["count"]= 0
        obj[ipaddress][localmachine][username]["actions"]= []
        
    obj[ipaddress][localmachine][username]["count"]+=1
    obj[ipaddress][localmachine][username]["actions"].append({
        "sharename":userdict["sharename"],
        "action":userdict["action"],
        "date":userdict["date"]
    })
    return obj
    


def main():


    #while True:

        #try:
            linelist = []
            obj = {}

            process = subprocess.Popen("cat /var/log/samba/smb_audit.log | awk '{print $6, $8, $10, $12, $14, $16}'", stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8', shell=True)
            line = process.stdout.readline()
            #if line is not null, process it into a dict object
            while line:
                #print(line)
                #example output: IP:192.168.209.99 USER:user MACHINE:45dr-mmcphee SHARENAME:share DATE:2022/12/14 ACTION:|create_file|ok|0x80|file|open|/tank/samba/share
                
                line = line.split(' ')
                entry = {"ipaddress":None, "username": None, "localmachine": None, "sharename": None, "date": None, "action": None}
                
                entry["ipaddress"]=line[0].split(':')[1]
                entry["username"]=line[1].split(':')[1]
                entry["localmachine"]=line[2].split(':')[1]
                entry["sharename"]=line[3].split(':')[1]
                entry["date"]=line[4].split(':')[1]
                entry["action"]=line[5].split(':')[1]
                #entry["action"].append(line[5].split(':')[1])
                #filepaths = []

                linelist.append(entry)
                #linelist.append(filepaths)

                line = process.stdout.readline()


            
            for line in linelist:
                #print("processing log\n")

                obj=processLog2(line, obj)
                
            #print("\n",json.dumps(obj, indent=4))
            print("#HELP smb_audit_log_entry Number of times each username/machine/ip combination appears in the smb audit log")
            print("#TYPE smb_audit_log_entry counter")
            for ip in obj:
                machines = obj[ip]
                #print("\n",json.dumps(key, indent=4))
                #print("\n",ip )
                for machine in machines:
                    users = machines[machine]
                    for user in users:
                        data = users[user]
                        print(f"smb_audit_log_entry{{ip={ip},machine={machine},user={user}}} {data['count']}")

                #break
            
        #except KeyboardInterrupt:
          #  break
    
if __name__ == "__main__":
    main()