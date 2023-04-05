#!/usr/bin/env python3

import os
import sys
import threading
from queue import Queue
import xattr

# Function to process each file and directory
def process_file_or_directory(path, output_file, match_string):
    if os.path.isfile(path):
        try:
            ext_attr = xattr.getxattr(path, 'ceph.file.layout.pool')
            ext_attr_value = ext_attr.decode('utf-8')
            if ext_attr_value == match_string:
                with open(output_file, 'a') as f:
                    f.write(f"{path}\n")
        except (OSError, IOError):
            pass
    elif os.path.isdir(path):
        queue.put(path)

# Worker thread function
def worker():
    while True:
        item = queue.get()
        if item is None:
            break
        for entry in os.scandir(item):
            process_file_or_directory(entry.path, output_file, match_string)
        queue.task_done()

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: python script.py <directory_to_scan> <output_file> <num_worker_threads> <match_string>")
        sys.exit(1)

    root_directory = sys.argv[1]
    output_file = sys.argv[2]
    num_worker_threads = int(sys.argv[3])
    match_string = sys.argv[4]

    # Create a Queue to hold the directories to be processed
    queue = Queue()

    # Create and start the worker threads
    threads = []
    for i in range(num_worker_threads):
        t = threading.Thread(target=worker)
        t.start()
        threads.append(t)

    # Add the root directory to the queue
    queue.put(root_directory)

    # Wait for the queue to be empty
    queue.join()

    # Stop the worker threads
    for i in range(num_worker_threads):
        queue.put(None)
    for t in threads:
        t.join()

    print("Finished processing.")
