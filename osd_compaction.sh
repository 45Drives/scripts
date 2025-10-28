#!/usr/bin/bash

# Matthew hutchinson <mhutchinson@45drives.com>

# Trigger compaction on all OSDs belonging to this host.
set -euo pipefail

HOST="$(hostname -s)"
OSDS=$(ceph osd ls-tree "$HOST")

if [ -z "$OSDS" ]; then
    echo "No OSDs found for host $HOST."
    exit 0
fi

echo "Starting compaction on OSDs for host: $HOST"
for osd in $OSDS; do
    echo "Running compaction on osd.${osd}..."
    if ceph tell osd."${osd}" compact; then
        echo "Compaction triggered successfully for osd.${osd}"
    else
        echo "Failed to trigger compaction on osd.${osd}"
    fi
    echo
done

echo "All compaction requests have been sent for host: $HOST"
