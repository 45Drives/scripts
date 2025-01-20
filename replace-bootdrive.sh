#!/usr/bin/env bash
#
# Rebuild a failed redundant (mirrored) boot drive, allowing multiple
# partition+RAID mappings via --partition options.
#
# --------------------------------------------------------------------
# WARNING: This script is a template. Running it without customizing
# partition numbers, RAID device names, etc., can cause data loss.
# --------------------------------------------------------------------
#
# Example Usage (as root):
#   ./rebuild_boot_drive.sh /dev/sda /dev/sdb \
#       --partition 1:md0 \
#       --partition 2:md1
#
# Where:
#   /dev/sda = Your existing healthy boot drive (source)
#   /dev/sdb = The new or replacement drive (target)
#   1:md0    = Partition #1 goes to /dev/md0
#   2:md1    = Partition #2 goes to /dev/md1
#
# Requirements:
#   - parted, sgdisk, mdadm, grub-install (or grub2-install) installed
#   - System must be using BIOS or EFI compatible with these commands
#

# Exit on errors or unset variables
set -o errexit
set -o nounset
set -o pipefail

# --------------------------------------------------------------------
# 1. Parse positional arguments (healthy & replacement drives)
#    plus any --partition options
# --------------------------------------------------------------------

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <HEALTHY_DRIVE> <REPLACEMENT_DRIVE> [--partition N:mdX ...]"
  echo "Example: $0 /dev/sda /dev/sdb --partition 1:md0 --partition 2:md1"
  exit 1
fi

HEALTHY_DRIVE="$1"
REPLACEMENT_DRIVE="$2"
shift 2

# This array will hold partition+MD pairs (e.g., "1:md0" "2:md1" ...)
PARTITION_ARRAYS=()

# Parse any additional arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --partition)
      if [[ -n "${2:-}" ]]; then
        PARTITION_ARRAYS+=("$2")
        shift 2
      else
        echo "Error: --partition requires an argument like '1:md0'"
        exit 1
      fi
      ;;
    *)
      echo "Unrecognized option: $1"
      exit 1
      ;;
  esac
done

# If no --partition was specified, warn or handle default
if [[ "${#PARTITION_ARRAYS[@]}" -eq 0 ]]; then
  echo "Warning: No --partition options were provided."
  echo "No RAID arrays will be re-added automatically."
  echo "Press Ctrl+C to cancel or Enter to continue anyway."
  read -r
fi

# --------------------------------------------------------------------
# 2. Confirm the devices exist and are not the same
# --------------------------------------------------------------------
if [[ ! -b "$HEALTHY_DRIVE" ]]; then
  echo "Error: $HEALTHY_DRIVE is not a valid block device."
  exit 1
fi

if [[ ! -b "$REPLACEMENT_DRIVE" ]]; then
  echo "Error: $REPLACEMENT_DRIVE is not a valid block device."
  exit 1
fi

if [[ "$HEALTHY_DRIVE" == "$REPLACEMENT_DRIVE" ]]; then
  echo "Error: Healthy drive and replacement drive cannot be the same."
  exit 1
fi

echo "Healthy Drive:      $HEALTHY_DRIVE"
echo "Replacement Drive:  $REPLACEMENT_DRIVE"

# --------------------------------------------------------------------
# 3. Print existing partition tables (for reference)
# --------------------------------------------------------------------
echo "Partition layout on $HEALTHY_DRIVE:"
parted "$HEALTHY_DRIVE" print || true

echo "Partition layout on $REPLACEMENT_DRIVE (before wipe):"
parted "$REPLACEMENT_DRIVE" print || true

read -rp "Proceed with partition wipe and rebuild? (y/N) " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborting."
  exit 1
fi

# --------------------------------------------------------------------
# 4. Wipe the replacement drive's partition table
# --------------------------------------------------------------------
echo "Wiping partition table on $REPLACEMENT_DRIVE..."
sgdisk --zap-all "$REPLACEMENT_DRIVE"

# --------------------------------------------------------------------
# 5. Replicate partition table from healthy drive to replacement
# --------------------------------------------------------------------
echo "Copying partition table from $HEALTHY_DRIVE to $REPLACEMENT_DRIVE..."
sgdisk --replicate="$REPLACEMENT_DRIVE" "$HEALTHY_DRIVE"

# Optionally randomize new drive's GUIDs if desired:
# sgdisk --randomize-guids "$REPLACEMENT_DRIVE"

# --------------------------------------------------------------------
# 6. Inform OS of partition table changes
# --------------------------------------------------------------------
partprobe "$REPLACEMENT_DRIVE" || true
sleep 2

echo "Partition layout on $REPLACEMENT_DRIVE (after replication):"
parted "$REPLACEMENT_DRIVE" print || true

# --------------------------------------------------------------------
# 7. Re-add the replacement drive’s partitions to the RAID mirror(s)
# --------------------------------------------------------------------
# We'll parse each "Partition#:mdX" pair from PARTITION_ARRAYS
# to run: mdadm --add /dev/mdX <REPLACEMENT_DRIVE><PART#>

if [[ "${#PARTITION_ARRAYS[@]}" -gt 0 ]]; then
  echo "Re-adding partitions to RAID arrays..."
fi

for PART_PAIR in "${PARTITION_ARRAYS[@]}"; do
  # PART_PAIR should be something like "1:md0"
  PART_NUMBER="${PART_PAIR%%:*}"
  MD_DEVICE="${PART_PAIR##*:}"

  # Validate that PART_NUMBER is numeric and MD_DEVICE is not empty
  if [[ ! "$PART_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: Partition number '$PART_NUMBER' is not numeric. Skipping."
    continue
  fi
  if [[ -z "$MD_DEVICE" ]]; then
    echo "Error: MD device is empty for pair '$PART_PAIR'. Skipping."
    continue
  fi

  # If user typed just "md0", assume /dev/md0
  # Or if they typed "/dev/md0", we can handle that too
  if [[ "$MD_DEVICE" != /dev/md* ]]; then
    MD_DEVICE="/dev/${MD_DEVICE}"
  fi

  echo "  -> Adding ${REPLACEMENT_DRIVE}${PART_NUMBER} to $MD_DEVICE ..."
  mdadm --add "$MD_DEVICE" "${REPLACEMENT_DRIVE}${PART_NUMBER}"
done

# --------------------------------------------------------------------
# 8. Wait briefly, show RAID status
# --------------------------------------------------------------------
echo "Waiting briefly for RAID rebuild to start..."
sleep 5

echo "RAID status:"
cat /proc/mdstat || true

# --------------------------------------------------------------------
# (Optional) Wait for full rebuild
# --------------------------------------------------------------------
# Uncomment this loop if you want the script to block until rebuild finishes.
# while grep -qE "resync|recover" /proc/mdstat; do
#   echo "Rebuilding in progress. Current status:"
#   cat /proc/mdstat
#   sleep 30
# done

# --------------------------------------------------------------------
# 9. Reinstall GRUB on the new drive
# --------------------------------------------------------------------
# The method depends on BIOS vs. UEFI. For BIOS systems:
# grub-install --recheck "$REPLACEMENT_DRIVE"
#
# For UEFI-based (with EFI partition), you'll need additional steps:
#   - Possibly mount the EFI partition
#   - grub-install --target=x86_64-efi --efi-directory=/boot/efi ...
#
# For some distros (e.g., CentOS/RHEL):
#   grub2-install --recheck "$REPLACEMENT_DRIVE"
#   grub2-mkconfig -o /boot/grub2/grub.cfg
#
# Below is a typical BIOS-style command:

echo "Installing GRUB on $REPLACEMENT_DRIVE..."
grub-install --recheck "$REPLACEMENT_DRIVE" || echo "Warning: grub-install failed. Check if you're UEFI-based."

# For Debian/Ubuntu:
# update-grub
# For CentOS/RHEL:
# grub2-mkconfig -o /boot/grub2/grub.cfg

# --------------------------------------------------------------------
# 10. Final check
# --------------------------------------------------------------------
echo "Verifying final RAID status..."
cat /proc/mdstat || true

echo "Process complete. Confirm that the rebuild succeeds and that $REPLACEMENT_DRIVE is fully mirrored."
