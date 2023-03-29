#!/usr/bin/env bash

echo Fixing cockpit fonts

mkdir -p /usr/share/cockpit/base1/fonts

curl -sSL https://scripts.45drives.com/cockpit_font_fix/fonts/fontawesome.woff -o /usr/share/cockpit/base1/fonts/fontawesome.woff
curl -sSL https://scripts.45drives.com/cockpit_font_fix/fonts/glyphicons.woff -o /usr/share/cockpit/base1/fonts/glyphicons.woff
curl -sSL https://scripts.45drives.com/cockpit_font_fix/fonts/patternfly.woff -o /usr/share/cockpit/base1/fonts/patternfly.woff

echo Done
