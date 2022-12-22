#!/usr/bin/env python3

import time
import json
import argparse
import subprocess
import sys
import os
from prometheus_client import start_http_server
from prometheus_client.core import CollectorRegistry, CounterMetricFamily, REGISTRY
from logcounter import processLog2

class SMBAuditCollector(object):
	def __init__(self):
		pass
	
	def collect(self):
		smb_audit_entry = CounterMetricFamily('smb_audit_entry', 'Number of times each username/machine/ip combination appears in the smb audit log.', labels=['ip', 'machine', 'user'])
		# smb_audit_entry.add_metric(['1.1.1.1', '45dr-mmcphee', 'user'], 6)

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
		#print("#HELP smb_audit_log_count Number of times each username/machine/ip combination appears in the smb audit log")
		#print("#TYPE smb_audit_log_count counter\n")
		for ip in connectionActions:
			machines = connectionActions[ip]
			#print("\n",json.dumps(key, indent=4))
			#print("\n",ip )
			for machine in machines:
				users = machines[machine]
				for user in users:
					data = users[user]
					
					#print(f"smb_audit_log_count{{IP={ip},MACHINE={machine},USER={user}}} {data['count']}")
					smb_audit_entry.add_metric([ip, machine, user], data['count'])
					# for key in data["paths"]:
					#    print(f"\t{key} {data['paths'][key]}")


		yield smb_audit_entry

def parse_args():
	parser = argparse.ArgumentParser(description = 'Prometheus metrics exporter for smb_audit.')
	parser.add_argument('-p', '--port', required = True, help = 'Port for server')
	return parser.parse_args()

def main():
	try:
		args = parse_args()
		port = None
		try:
			port = int(args.port)
		except ValueError:
			print('Invalid port: ', args.port)
			sys.exit(1)
		if port > 65535 or port <= 1023:
			print('Invalid port range: ', args.port)
			sys.exit(1)
		print('Serving smb_audit metrics to :{}'.format(port))
		registry = CollectorRegistry()
		start_http_server(port, registry=registry)
		registry.register(SMBAuditCollector())

		while True:
			time.sleep(45 * 24 * 60 * 60)
	except KeyboardInterrupt:
		print('Interrupted.')
		sys.exit(0)

if __name__ == '__main__':
	main()
