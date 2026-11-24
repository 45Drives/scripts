#!/usr/bin/env bash
#
# Script to print hard drive voltage rails as table using FARM logs
#
# Joshua Boudreau 2026 <jboudreau@45drives.com>

set -o pipefail

usage() {
    printf 'Usage: %s [ -c | -n ] [ DEVICE... ]\n' "$0"
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
        usage >&2
        exit 2
        ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -eq 0 ]; then
    DEVS=(/dev/disk/by-vdev/*)
else
    DEVS=("$@")
fi

HEADERS=("Device" "Current 12 volts" "Minimum 12 volts" "Maximum 12 volts" "Current 5 volts" "Minimum 5 volts" "Maximum 5 volts")
HEADERS_CSV="$(IFS=, ; echo "${HEADERS[*]}")"

_read_voltages() (
    set -euo pipefail
    dev=$1
    if [ ! -b "$dev" ] && [ ! -c "$dev" ]; then
        echo "Device $dev not found." >&2
        return 1
    fi
    
    smartctl -l farm "$dev" -j | jq -r '
    .seagate_farm_log.page_4_environment_statistics |
    [ .current_12v_in_mv, .minimum_12v_in_mv, .maximum_12v_in_mv, .current_5v_in_mv, .minimum_5v_in_mv, .maximum_5v_in_mv ] |
    map(if . == null then "N/A" else . / 1000.0 end) |
    [ "'"$dev"'" ] + . |
    join(",")
    '
)

read_voltages() {
    _read_voltages "$@"
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
        echo "$1,N/A,N/A,N/A,N/A,N/A,N/A"
    fi
}

TOL_ERR=0.10
TOL_WARN=0.05

if $COLOR; then
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
        if ($2 == "N/A") {
            $2 = $2
        } else if ($2 > (12 * (1+TOL_ERR)) || $2 < (12 * (1-TOL_ERR))) {
            $2 = $2 " **"
        } else if ($2 > (12 * (1+TOL_WARN)) || $2 < (12 * (1-TOL_WARN))) {
            $2 = $2 " *"
        } else {
            $2 = $2
        }
        if ($5 == "N/A") {
            $5 = $5
        } else if ($5 > (5 * (1+TOL_ERR)) || $5 < (5 * (1-TOL_ERR))) {
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
