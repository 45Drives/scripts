#!/bin/bash

# Define paths
bin_files_path="/root/ToolBin/openSeaChest/bin-build/22.07.26/Lin64"
log_parser_path="/root/ToolBin/openSeaChest_LogParser/bin_Build/21.01.13/Lin64"

# Change to the directory with the log parser tool
cd "$log_parser_path"

# Make the log parser tool executable
chmod +x ./openSeaChest_LogParser_1_3_2-1_1_3_x86_64

# Loop through each .bin file in the bin_files_path directory
for bin_file in "${bin_files_path}"/*_FARM_*.bin; do
    # Extract the serial number from the file name
    serial_number=$(basename "$bin_file" | cut -d'_' -f1)

    # Check if the serial number is non-empty and not starting with an underscore
    if [[ -n "$serial_number" && "$serial_number" != _* ]]; then
        # Define the output log file path
        log_file="${bin_files_path}/${serial_number}_FARM.log"

        echo "Processing: $bin_file"
        # Run the log parser tool and redirect output to the log file
        ./openSeaChest_LogParser_1_3_2-1_1_3_x86_64 --inputLog "$bin_file" --logType farmLog --outputLog "$log_file"

        # Check if parsing was successful or encountered a memory failure
        if grep -q "Memory Failure" "$log_file"; then
            echo "Memory Failure occurred while processing $bin_file"
        else
            echo "Parsing successful for $bin_file"
        fi
    else
        echo "Skipping non-conforming file: $bin_file"
    fi
done

echo "Operation complete. Check the '${bin_files_path}' directory for .log files."