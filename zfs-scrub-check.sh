#!/bin/bash
#
# Checks all ZFS pools for the date of their last scrub.
# If a pool hasn't been scrubbed in 35+ days, scrub it.

MAX_AGE_DAYS=35

# Get the list of all imported ZFS pools
POOLS=$(zpool list -H -o name)
if [ -z "$POOLS" ]; then
  echo "No ZFS pools found (or none imported). Exiting."
  exit 0
fi

echo "Checking ZFS pools: $POOLS"

for POOL in $POOLS; do
  echo "-------------------------------------"
  echo "POOL: $POOL"

  # Grab the single line containing 'scan:' from the pool status
  LINE=$(zpool status "$POOL" | grep "scan:")

  # The line typically looks like:
  #   scan: scrub repaired 0B in 00:01:23 with 0 errors on Mon Jan 12 23:22:00 2025
  # We want to extract everything after "on " => the date string.
  SCRUB_DATE=$(echo "$LINE" | sed -n 's/.* on //p')

  if [ -z "$SCRUB_DATE" ]; then
    echo "  No last scrub date found (scrub never completed?)"
    echo "  -> Initiating scrub now..."
    zpool scrub "$POOL"
    continue
  fi

  # Convert last scrub date to epoch seconds
  SCRUB_EPOCH=$(date -d "$SCRUB_DATE" +%s 2>/dev/null)
  if [ -z "$SCRUB_EPOCH" ]; then
    echo "  Could not parse the last scrub date: $SCRUB_DATE"
    echo "  -> Skipping pool..."
    continue
  fi

  NOW_EPOCH=$(date +%s)
  DIFF_DAYS=$(( (NOW_EPOCH - SCRUB_EPOCH) / 86400 ))

  if [ "$DIFF_DAYS" -ge "$MAX_AGE_DAYS" ]; then
    echo "  Last scrub was $DIFF_DAYS days ago."
    echo "  -> Initiating new scrub..."
    zpool scrub "$POOL"
  else
    echo "  Last scrub was $DIFF_DAYS days ago (< $MAX_AGE_DAYS)."
    echo "  -> Skipping scrub."
  fi
done

echo "All pools checked."
