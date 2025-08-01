#!/usr/bin/env bash
#
# Convert any image into appropriate dimensions and color profile for BIOS splash screen
#
# Josh Boudreau 2025 <jboudreau@45drives.com>

if ! command -v convert >/dev/null; then
    echo "Missing 'convert' from imagemagick!" >&2
    exit 1
fi

usage() {
    printf 'Usage: %s [ -h ] MANUFACTURER IMAGE OUTPUT\n' "$0"
    echo
    echo 'Options:'
    echo '  -h              - Print this message'
    echo '  -b BG_COLOR     - Set background fill color'
    echo '  MANUFACTURER - Mobo manufacturer to auto set W and H'
    echo '  IMAGE           - input image file'
    echo '  OUTPUT          - output image file (extension auto added)'
}

MFR_LUT='
SUPERMICRO 1024 768 truecolor 8 bmp
GIGABYTE 1024 768 truecolor 8 bmp
ASROCK 1024 768 truecolor 8 jpg
AMI 300 300 truecolor 8 bmp
'

BG=black

while getopts 'hb:' opt; do
    case $opt in
    h)
        usage
        exit 0
        ;;
    b)
        BG="$OPTARG"
        ;;
    *)
        usage >&2 # print to stderr
        exit 2 # exit with usage error (2)
        ;;
    esac
done
shift $((OPTIND - 1)) # after this line, $@ will contain remaining non-option arguments

if [ $# -lt 3 ]; then
    echo "Not enough arguments!" >&2
    usage >&2
    exit 2
fi

MFR=$(echo "$1" | tr '[:lower:]' '[:upper:]')
INPUT=$2
OUTPUT=$3

if ! grep "$MFR" >/dev/null <<<"$MFR_LUT"; then
    echo "Invalid manufacturer: $MFR"
    echo "valid manufacturers:"
    awk '/.+/{print $1}' <<<"$MFR_LUT"
    exit 2
fi

WIDTH=$(awk '/^'"$MFR"'/{print $2}' <<<"$MFR_LUT")
HEIGHT=$(awk '/^'"$MFR"'/{print $3}' <<<"$MFR_LUT")
TYPE=$(awk '/^'"$MFR"'/{print $4}' <<<"$MFR_LUT")
DEPTH=$(awk '/^'"$MFR"'/{print $5}' <<<"$MFR_LUT")
EXT=$(awk '/^'"$MFR"'/{print $6}' <<<"$MFR_LUT")

if [[ "$OUTPUT" != *."$EXT" ]]; then
    OUTPUT="$OUTPUT"."$EXT"
fi

convert "$INPUT" -background "$BG" -flatten +matte -resize "${WIDTH}x${HEIGHT}" -gravity center -extent "${WIDTH}x${HEIGHT}" -type "$TYPE" -depth "$DEPTH" "$OUTPUT"
