#!/usr/bin/env bash
#
# A script that:
#  1) Looks up custom-aliased disks in /dev/disk/by-vdev/.
#  2) Only parses lines from the Vendor Specific SMART Attributes table.
#  3) Filters by specific attribute IDs.
#  4) Shows only [ID] [Attribute Name] [Raw Value].
#  5) For attributes 241/242, appends (XX.XX TB) in the Raw Value if numeric.

set -e

VDEV_DIR="/dev/disk/by-vdev"
ATTR_IDS="1|4|5|7|9|12|187|188|190|194|197|198|199|241|242"

# Ensure the /dev/disk/by-vdev directory exists
if [ ! -d "$VDEV_DIR" ]; then
  echo "Directory $VDEV_DIR does not exist or is not accessible."
  exit 1
fi

for link in "$VDEV_DIR"/*; do
  # Skip if it's not a symlink
  [ -L "$link" ] || continue

  # Resolve the symlink to the underlying device (e.g., /dev/sda)
  realdev=$(readlink -f "$link")

  # Check if the resolved path is a block device
  if [ ! -b "$realdev" ]; then
    echo "Skipping '$link' -> '$realdev' (not a block device)."
    continue
  fi

  if [[ "$realdev" =~ [0-9]$ ]]; then
    continue
  fi

  echo "======================================================="
  echo -e "SMART Information for alias:  \e[32m$(basename "$link")\e[0m"
  echo -e "Physical device resolved to:  \e[32m$realdev\e[0m"
  echo "======================================================="

  # 1) Collect lines from Vendor Specific SMART Attributes table
  # 2) Filter for attribute IDs we care about
  smartctl -a "$realdev" 2>/dev/null | \
    awk '
      /Vendor Specific SMART Attributes with Thresholds:/   { in_table=1; next }
      /^ID# +ATTRIBUTE_NAME/                                { in_table=1; next }

      # Turn off capture on blank line or start of other sections
      /^$/                                                  { in_table=0; next }
      /^SMART Error Log Version:/                           { in_table=0; next }
      /^SMART Self-test log/                                { in_table=0; next }

      in_table == 1                                         { print $0 }
    ' | \
    grep -E "^[[:space:]]*($ATTR_IDS)[[:space:]]+" | \
    while read -r line; do
      # Typical line has at least 10 columns:
      #   ID#  ATTRIBUTE_NAME  FLAG  VALUE WORST THRESH  TYPE    UPDATED  WHEN_FAILED  RAW_VALUE...
      #
      # For example:
      #   190 Airflow_Temperature_Cel  0x0022  075 061 040 Old_age Always - 25 (Min/Max 18/30)
      #
      # We want:
      #   attr_id   = fields[0]
      #   attr_name = fields[1]
      #   raw_value = everything from fields[9] onward (combined)

      fields=($line)

      attr_id="${fields[0]}"
      attr_name="${fields[1]}"

      # Rebuild the raw_value from the 10th field onward
      # (because columns 0..8 correspond to ID, NAME, FLAG, VALUE, WORST, THRESH, TYPE, UPDATED, WHEN_FAILED).
      # The raw value could contain parentheses, e.g. "25 (Min/Max 18/30)".
      raw_value=""
      for ((i=9; i<${#fields[@]}; i++)); do
        if [ -z "$raw_value" ]; then
          raw_value="${fields[i]}"
        else
          raw_value="$raw_value ${fields[i]}"
        fi
      done

      # For attributes 241 or 242, if raw_value is purely numeric, compute TB
      tb_append=""
      if [[ "$attr_id" == "241" || "$attr_id" == "242" ]]; then
        # Check if purely numeric
        if [[ "$raw_value" =~ ^[0-9]+$ ]]; then
          # Convert LBAs to TB = raw_value * 512 * 1.0e-12
          tb=$(awk -v val="$raw_value" 'BEGIN { printf "%.2f", val * 512 * 1.0e-12 }')
          tb_append=" (${tb} TB)"
        fi
      fi

      # Print only [ID] [Name] [Raw Value]
      printf "%3s  %-25s  %s%s\n" \
             "$attr_id" \
             "$attr_name" \
             "$raw_value" \
             "$tb_append"
    done

  echo ""
done
