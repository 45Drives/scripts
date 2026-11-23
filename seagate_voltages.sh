#!/usr/bin/env bash
#
# Wrapper for Seagate openSeaChest tools to check hard drive voltage rails
#
# Joshua Boudreau 2026 <jboudreau@45drives.com>

set -o pipefail

SCRIPT_DIR="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"

cd "$SCRIPT_DIR"

if [ ! -d "ToolBin" ]; then
    (
        set -euo pipefail
        echo "Cloning Seagate ToolBin repository to $SCRIPT_DIR/ToolBin ..."
        git clone --recursive --single-branch https://github.com/Seagate/ToolBin.git
        cd ToolBin
        git checkout f883119d5b0f5bd3568d3696cdb1d69d7ffc18f8 2>/dev/null
    ) >&2 || exit $?
fi

OPEN_SEA_CHEST_PFX=ToolBin/openSeaChest/bin-build/22.07.26/Lin64/
OPEN_SEA_CHEST_LOG_PARSER=ToolBin/openSeaChest_LogParser/bin_Build/21.01.13/Lin64/openSeaChest_LogParser_1_3_2-1_1_3_x86_64

chmod +x $OPEN_SEA_CHEST_PFX/* $OPEN_SEA_CHEST_LOG_PARSER

HEADERS=("Current 12 volts" "Minimum 12 volts" "Maximum 12 volts" "Current 5 volts" "Minimum 5 volts" "Maximum 5 volts")
JQ_FILTER=$(for header in "${HEADERS[@]}"; do echo -n ".\"$header\", "; done)
JQ_FILTER=${JQ_FILTER%, } # remove trailing comma and space
HEADERS_CSV="Device,$(IFS=, ; echo "${HEADERS[*]}")"

_read_voltages() (
    set -euo pipefail
    dev=$1
    if [ ! -b "$dev" ]; then
        echo "Device $dev not found." >&2
        return 1
    fi
    TMP_DIR=$(mktemp -d)
    "$OPEN_SEA_CHEST_PFX/openSeaChest_Logs" -d "$dev" --farm --outputPath "$TMP_DIR" >/dev/null 2>&1
    "$OPEN_SEA_CHEST_LOG_PARSER" --inputLog "$TMP_DIR"/*.bin --logType farmLog >/dev/null 2>&1
    sed -i '0,/"Maximum 5 volts"/s/"Maximum 5 volts"/"Minimum 5 volts"/' "$TMP_DIR"/*_FARM_*.json >/dev/null 2>&1 # fix typo in output

    cat "$TMP_DIR"/*_FARM_*.json 2>/dev/null | jq -r '."Environment Information From Farm Log copy 0" | ['"\"$dev\", $JQ_FILTER"'] | join(",")'
    rm -rf "$TMP_DIR"
)

read_voltages() {
    _read_voltages "$@"
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
        echo "$1,N/A,N/A,N/A,N/A,N/A,N/A"
    fi
}

usage() {
    printf 'Usage: %s [ -h -f -v VALUE ]\n' "$0"
    echo
    echo 'Options:'
    echo '  -h - Print this message'
    echo '  -c - Force colour output'
    echo '  -n - Force no colour output'
}

if [ -t 1 ]; then
    # is tty
    COLOR=true
else
    COLOR=false
fi

while getopts 'hcn' opt; do
    case $opt in
    h)
        usage
        exit 0
        ;;
    c)
        COLOR=true
        ;;
    n)
        COLOR=false
        ;;
    *)

        ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -eq 0 ]; then
    DEVS=(/dev/disk/by-vdev/*)
else
    DEVS=("$@")
fi

TOL_ERR=0.10
TOL_WARN=0.05

if $COLOR; then
    # Enable color output if the terminal supports it
    format_colours() {
        awk -v TOL_ERR="$TOL_ERR" -v TOL_WARN="$TOL_WARN" '
        BEGIN {
            FS=","
            OFS=","
        }
        {
        if (NR==1) {
            for (i = 1; i <= NF; i++) {
                $i = "\033[1m" $i "\033[0m"
            }
            print
            next
        }
        if ($2 == "N/A") {
            $2 = $2
        } else if ($2 > (12 * (1+TOL_ERR)) || $2 < (12 * (1-TOL_ERR))) {
            $2 = "\033[31;1m" $2 "\033[0m"
        } else if ($2 > (12 * (1+TOL_WARN)) || $2 < (12 * (1-TOL_WARN))) {
            $2 = "\033[33;1m" $2 "\033[0m"
        } else {
            $2 = "\033[32;1m" $2 "\033[0m"
        }
        if ($5 == "N/A") {
            $5 = $5
        } else if ($5 > (5 * (1+TOL_ERR)) || $5 < (5 * (1-TOL_ERR))) {
            $5 = "\033[31;1m" $5 "\033[0m"
        } else if ($5 > (5 * (1+TOL_WARN)) || $5 < (5 * (1-TOL_WARN))) {
            $5 = "\033[33;1m" $5 "\033[0m"
        } else {
            $5 = "\033[32;1m" $5 "\033[0m"
        }
        print
        }'
    }
    explain_colours() {
        echo -e "Voltage indicators: \033[31;1m>10% out of tolerance\033[0m \033[33;1m>5% out of tolerance\033[0m \033[32;1mNormal\033[0m"
    }
else
    format_colours() {
        awk -v TOL_ERR="$TOL_ERR" -v TOL_WARN="$TOL_WARN" '
        BEGIN {
            FS=","
            OFS=","
        }
        {
        if (NR==1) {
            print
            next
        }
        if ($2 > (12 * (1+TOL_ERR)) || $2 < (12 * (1-TOL_ERR))) {
            $2 = $2 " **"
        } else if ($2 > (12 * (1+TOL_WARN)) || $2 < (12 * (1-TOL_WARN))) {
            $2 = $2 " *"
        } else {
            $2 = $2
        }
        if ($5 > (5 * (1+TOL_ERR)) || $5 < (5 * (1-TOL_ERR))) {
            $5 = $5 " **"
        } else if ($5 > (5 * (1+TOL_WARN)) || $5 < (5 * (1-TOL_WARN))) {
            $5 = $5 " *"
        } else {
            $5 = $5
        }
        print
        }'
    }
    explain_colours() {
        echo "Voltage indicators:"
        echo "** >10% out of tolerance"
        echo "* >5% out of tolerance"
    }
fi

{
    echo "$HEADERS_CSV"
    {
        for dev in "${DEVS[@]}"; do
            if [[ "$dev" == *-part* ]]; then
                continue
            fi
            read_voltages "$dev" &
        done
    } | sort -V
    
} | format_colours | column -t -s ',' | perl -pne 's/ {2,}/$&\| /g'

explain_colours >&2
