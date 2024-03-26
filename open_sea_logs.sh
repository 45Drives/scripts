#!/bin/bash

# Define tool paths
open_sea_path="/root/ToolBin/openSeaChest/bin-build/22.07.26/Lin64"

# Define output directories
output_dir="/root/open_sea_files"
basics_dir="${output_dir}/basics"
logs_dir="${output_dir}/logs"

# Ensure the script is running with root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

# Create output directories if they don't exist
mkdir -p "$basics_dir" "$logs_dir"

# Make the Basics and Logs tools executable
chmod +x "${open_sea_path}/openSeaChest_Basics" "${open_sea_path}/openSeaChest_Logs"

# Perform the scan
cd "${open_sea_path}"
./openSeaChest_Basics --scan

# Gather Basics information and Logs information
cd "${open_sea_path}" # Make sure we're in the correct directory for the tools
for device in /dev/sg*; do
    # Run openSeaChest_Basics to get device info
    basics_output=$(./openSeaChest_Basics -d "$device" -i)

    # Extract the serial number and model number
    serial_number=$(echo "$basics_output" | awk '/Serial Number/ {print $NF}')
    model_number=$(echo "$basics_output" | awk '/Model Number/ {print $NF}')

    # Check for Seagate identifier in basics output
    if [[ "$model_number" == ST* ]]; then
        # Seagate device, proceed with logging
        basics_filename="${device##*/}_basics.log"
        basics_filepath="${basics_dir}/${basics_filename}"
        echo "$basics_output" > "$basics_filepath"

        # Run openSeaChest_Logs and save output to logs directory
        timestamp=$(date +%Y%m%d%H%M%S)
        logs_filename="${serial_number}_FARM_${timestamp}.bin"
        logs_filepath="${logs_dir}/${logs_filename}"
        ./openSeaChest_Logs -d "$device" --farm > "$logs_filepath"
    else
        echo "Skipping non-Seagate device ${device} with Model Number ${model_number}"
    fi
done

echo "Operation complete. Check the '${output_dir}' directory for output."