#2024 Mitch Hall 45Drives
# Monitoring script. This script will run for 10 minutes and then kill itself. It is meant to be used
# in conjunction with crontab. Recommend running it at the top of every hour. It will run for 10 minutes and complete
# The script will monitor CPU load average, numastats, memory usage, and disk IO stats over time
# The script will spawn several log files in /var/log - load_average.log, disk_io.log, numa_stats.log
# and memory_usage.log


import psutil
import subprocess
import time
from datetime import datetime
import multiprocessing
import signal
import sys

# Convert bytes to GiB
def bytes_to_gib(bytes):
    return bytes / (1024 ** 3)

def log_numa_stats(stop_event):
    while not stop_event.is_set():
        with open('/var/log/numa_stats.log', 'a') as f:
            f.write(subprocess.getoutput('numastat -v'))
        time.sleep(1)

def log_memory_usage(stop_event):
    header = "timestamp,total_memory,available_memory,used_memory,free_memory\n"
    line_count = 0
    while not stop_event.is_set():
        if line_count % 60 == 0:
            with open('/var/log/memory_usage.log', 'a') as f:
                f.write(header)
        mem = psutil.virtual_memory()
        timestamp = datetime.now().strftime('%a %b %d %I:%M:%S %p %Z %Y')
        with open('/var/log/memory_usage.log', 'a') as f:
            f.write(f"{timestamp},{mem.total},{mem.available},{mem.used},{mem.free}\n")
        line_count += 1
        time.sleep(1)

def log_disk_io(stop_event):
    header = "timestamp,read_count,write_count,read_gib,write_gib\n"
    line_count = 0
    while not stop_event.is_set():
        if line_count % 60 == 0:
            with open('/var/log/disk_io.log', 'a') as f:
                f.write(header)
        io = psutil.disk_io_counters()
        read_gib = bytes_to_gib(io.read_bytes)
        write_gib = bytes_to_gib(io.write_bytes)
        timestamp = datetime.now().strftime('%a %b %d %I:%M:%S %p %Z %Y')
        with open('/var/log/disk_io.log', 'a') as f:
            f.write(f"{timestamp},{io.read_count},{io.write_count},{read_gib:.6f},{write_gib:.6f}\n")
        line_count += 1
        time.sleep(1)

def log_load_average(stop_event):
    header = "timestamp,load1,load5,load15\n"
    line_count = 0
    while not stop_event.is_set():
        if line_count % 60 == 0:
            with open('/var/log/load_average.log', 'a') as f:
                f.write(header)
        with open('/proc/loadavg', 'r') as f:
            load_avg = f.read().strip().split()[:3]
        timestamp = datetime.now().strftime('%a %b %d %I:%M:%S %p %Z %Y')
        with open('/var/log/load_average.log', 'a') as f:
            f.write(f"{timestamp},{load_avg[0]},{load_avg[1]},{load_avg[2]}\n")
        line_count += 1
        time.sleep(1)

def terminate_after_timeout(timeout, stop_event):
    time.sleep(timeout)
    stop_event.set()

def handle_interrupt(signum, frame, stop_event):
    stop_event.set()
    sys.exit(0)

def start_logging():
    stop_event = multiprocessing.Event()

    # Handle SIGINT to gracefully exit
    signal.signal(signal.SIGINT, lambda s, f: handle_interrupt(s, f, stop_event))

    processes = [
        multiprocessing.Process(target=log_numa_stats, args=(stop_event,)),
        multiprocessing.Process(target=log_memory_usage, args=(stop_event,)),
        multiprocessing.Process(target=log_disk_io, args=(stop_event,)),
        multiprocessing.Process(target=log_load_average, args=(stop_event,)),
        multiprocessing.Process(target=terminate_after_timeout, args=(600, stop_event))  # 10 minutes
    ]

    for p in processes:
        p.start()

    for p in processes:
        try:
            p.join()
        except KeyboardInterrupt:
            stop_event.set()
            for p in processes:
                p.join()
            print("\nScript terminated gracefully.")
            break

if __name__ == "__main__":
    start_logging()

