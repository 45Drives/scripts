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
CONF_FILE="/etc/vdev_id.conf"
REMOVE_FILES=0

# make script exit when a command fails
set -e

euid=$(id -u)
if [ $euid -ne 0 ]; then
	echo -e "\nYou must be root to run this utility.\n"
    exit 1
fi

Help()
{
    echo ""
    echo "  Help Menu - 45drives_udev_rules.sh"
    echo "  About:  A script that downloads and triggers 45Drives udev rules."
    echo "  options:"
    echo "   -r     remove 45drives udev rules and scripts from the system."
    echo "   -h     Print this menu."
    echo ""
    exit 0
}

while getopts "rh" flag
do
    case "${flag}" in
        r) REMOVE_FILES=1;;
        h | *) 
            Help
            exit 0;;
    esac
done

if [ $REMOVE_FILES -ne 0 ]; then
    echo " Removing Files.."
    if [ -f "$SCRIPT_PATH" ]; then
        echo " removing $SCRIPT_PATH"
        rm -f $SCRIPT_PATH
    fi
    
    if [ -f "$RULES_PATH" ]; then
        echo " removing $RULES_PATH"
        rm -f $RULES_PATH
    fi

    read -p " Files are removed, would you like to re-trigger udev rules? (y/n): " SELECTION
    if [ "$SELECTION" == "y" ]; then
        echo "[Reloading udev rules] -> udevadm control --reload-rules"
        udevadm control --reload-rules
        echo "[Triggering udev rules] -> udevadm trigger"
        udevadm trigger
    fi
    exit 0
fi

if [ ! -f "$CONF_FILE" ]; then
    echo "  WARNING: $CONF_FILE does not exist."
    echo "           45Drives udev rules will have no effect without a valid $CONF_FILE."
    read -p "           Do you want to download/trigger 45Drives udev rules anyway? (y/n): " SELECTION
    if [ "$SELECTION" != "y" ]; then
        echo "  exiting.."
        exit 1
    fi
fi


echo "[Downloading udev rules] -> curl -os "$RULES_PATH" "$RULES_URL""
curl -so "$RULES_PATH" "$RULES_URL"
echo "[Downloading udev script] -> curl -os "$SCRIPT_PATH" "$SCRIPT_URL""
curl -so "$SCRIPT_PATH" "$SCRIPT_URL"
echo "[Making udev script executable] -> chmod +x "$SCRIPT_PATH"" 
chmod +x "$SCRIPT_PATH"
echo "[Reloading udev rules] -> udevadm control --reload-rules"
udevadm control --reload-rules
echo "[Triggering udev rules] -> udevadm trigger"
udevadm trigger
