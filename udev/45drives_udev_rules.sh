#! /bin/bash

# This script will download and store the necessary rules files and scripts
# to apply the drive aliases as configured in /etc/vdev_id.conf
# It will also reload udev rules and trigger them. 
# this will result in drives appearing in 
# /dev/<whatever_your_alias_was_set_to> and /dev/disk/by-vdev/<whatever_your_drive_alias_was_set_to>

RULES_PATH="/usr/lib/udev/rules.d/68-vdev.rules"
SCRIPT_PATH="/usr/lib/udev/vdev_id_45drives"
RULES_URL="https://scripts.45drives.com/udev/68-vdev.rules"
SCRIPT_URL="https://scripts.45drives.com/udev/vdev_id_45drives"

set -e

euid=$(id -u)
if [ $euid -ne 0 ]; then
	echo -e '\nYou must be root to run this utility.\n'
    exit 1
fi

echo "Downloading udev rules"
curl -o "$RULES_PATH" "$RULES_URL"
echo "Downloading udev script"
curl -o "$SCRIPT_PATH" "$SCRIPT_URL"
echo "Making script executable"
chmod +x "$SCRIPT_PATH"
echo "Reloading udev rules"
udevadm control --reload-rules
echo "Triggering udev rules"
udevadm trigger
