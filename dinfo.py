#!/usr/local/bin/python3


# dinfo
# gather info about drive errors and power cycle counts, outputting the drives id name and slot
# Copyright 2021, Mike McPhee <mmcphee@45drives.com>
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.############


import subprocess
import re
import sys

class drive:
    device = None
    serial = None
    row = None
    slot = None
    sas3ircuRow = None
    sas3ircuSlot = None
    pwrcycl = None
    offline = None
    pending = None
    
    def __init__(self, device):
        self.device = device
        
        #grabbing serial
        serialLine = subprocess.check_output("smartctl -i /dev/"+device+" | grep -i 'serial number'", shell=True, encoding='utf-8').strip('\n')
        serial = serialLine.split()
        self.serial = serial[2]
        
        infolist = subprocess.check_output("smartctl -x /dev/"+device+" | grep -i 'power_cycle_count\|offline_uncorrectable\|current_pending_sector' | awk '{print $8}'", shell=True, encoding = 'utf-8').split('\n')
        del infolist[len(infolist)-1]
        self.pwrcycl = infolist[0]
        self.offline = infolist[1]
        self.pending = infolist[2]
    
    def findSlotS3(self):
     
        cardIOController = subprocess.check_output("lspci | grep -i 'LSI SAS'", shell=True, encoding = 'utf-8')
        cardIOController = subprocess.check_output("lspci | grep -i 'SAS3'", shell=True, encoding = 'utf-8')
        cardIOController = re.search("(SAS3224)", cardIOController).group()
        
        if cardIOController != None:
            controllercards = subprocess.check_output("sas3ircu list | grep -i index -A2 | awk '{print $1}' | grep '[0-9]$'", shell=True, encoding = 'utf-8').split('\n')
            del controllercards[len(controllercards)-1]
            
            cardnumber = None
            s3slot = None
            slotnumber = None
        
            
            #finding slot using sas3ircu command
            for y in controllercards:
                s3slot = subprocess.check_output("sas3ircu "+y+" display | grep -i "+self.serial+" -B10 | grep -i slot | awk '{print $4}'", shell=True, encoding = 'utf-8').strip('\n')
                
                
                if s3slot != "":
                    cardnumber = int(y)+1
                    slotnumber = int(s3slot)+1
                    s3slot = None
                    break
        
        
            self.sas3ircuRow = cardnumber
            self.sas3ircuSlot = slotnumber
            
        else: 
            #print("Controller card model not supported. SAS 9305 required to run 'sas3ircu'.")
            return
    
    
    def findSlotCC(self, boardtype):
        camslot = None
        camrow = None
        cam = subprocess.check_output("camcontrol devlist | grep -v ada | grep -i "+self.device+"", shell=True, encoding = 'utf-8').strip('\n')
        scbus = re.search("scbus(\S+)", cam).group()
        target = int(float(re.search("target (\d+)", cam).group(1)))
        if scbus != None:  
            if boardtype == "X10DRL-i":
                if scbus == "scbus0":
                    camrow = 1
                    camslot = int(target)+1
                
                if scbus == "scbus11":
                    camrow = 2
                    camslot = int(target)+1
                    
                if scbus == "scbus12":
                    camrow = 3
                    camslot = int(target)+1
                
                if scbus == "scbus13":
                    camrow = 4
                    camslot = int(target)+1
              
            elif boardtype == "X11SPL-f" or boardtype == "X11SPL-F":  
                if scbus == "scbus8":
                    camrow = 1
                    camslot = int(target)+1
                
                if scbus == "scbus9":
                    camrow = 2
                    camslot = int(target)+1
                    
                if scbus == "scbus10":
                    camrow = 3
                    camslot = int(target)+1
                
                if scbus == "scbus11":
                    camrow = 4
                    camslot = int(target)+1
                    
            else:
                
                camrow = None   
                camslot = None

            self.row = camrow
            self.slot = camslot
            
    def print(self):
        print(f"\n*----------------------------------dinfo---------------------------------------*\nDevice: {self.device} \nsas3ircu Slot: {self.sas3ircuRow} --> {self.sas3ircuSlot}\ncamcontrol Slot: {self.row} --> {self.slot}\nSerial Number: {self.serial}\nPower Cycle Count: {self.pwrcycl}\nOffline Uncorrectable Sector Count: {self.offline}\nCurrent Pending Sector Count: {self.pending}\n\n")


supportedBoards = ['X10DRL-I', 'X11SPL-F']

print("\n*----------------------------------dinfo---------------------------------------*\nGathers info about drive errors and power cycle counts, along with the drive's device identifier and physical slot.\n");
#print(sys.argv[1])
boardtype = subprocess.check_output("ipmitool fru | grep -i 'board product' | awk '{print $4}'", shell=True, encoding = 'utf-8').strip('\n')
boardtype = str(boardtype).strip(" ")

if supportedBoards.count(boardtype.upper())>0:
        
    print(f"Motherboard model number: {boardtype}")
    
    devlist = subprocess.check_output("ls /dev | grep -i da | grep -v 'p[0-9]$' | grep -v ada", shell =True, encoding = 'utf-8').split('\n')
    del devlist[len(devlist)-1]
    
    if len(sys.argv)>2:
        if sys.argv[1]== "list" :
            
            
            if sys.argv[2] == "devices":
                print("\nDevices Found: ")
                
                for a in devlist:
                    print(f"{a}")
                
            
            if sys.argv[2] == "all":
                
            
                
                # Looping through each device found in /dev 
                
                
                for x in devlist:
                    
                    currentdrive = drive(x)
                    currentdrive.findSlotS3()
                    currentdrive.findSlotCC(boardtype)
                    currentdrive.print()
            
            
            elif devlist.count(sys.argv[2]):
                output = drive(sys.argv[2])
                output.findSlotS3()
                output.findSlotCC(boardtype)
                output.print()
            
            else:
                print("\nInvalid arguments used. Device does not exist.")
                
        else:
             print("\nInvalid arguments used. Must use 'list all' or 'list da#'." )
             
            
    else:
        print("\nInvalid arguments used. dinfo accepts: \n\nlist devices --> lists devices found in /dev.\n\nlist all --> list info for all devices.\n\nlist *device id (da#)*: --> lists info for specific device.\n*------------------------------------------------------------------------------*\n")


else:
    print("\nBoard not supported. ")
