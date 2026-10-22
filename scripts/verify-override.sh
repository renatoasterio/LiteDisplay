#!/bin/bash
# Verifies an installed HiDPI display override.
# Usage: scripts/verify-override.sh <vendorHex> <productHex>   e.g. scripts/verify-override.sh 472 746
set -euo pipefail
VENDOR="${1:?vendor hex}"; PRODUCT="${2:?product hex}"
FILE="/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-${VENDOR}/DisplayProductID-${PRODUCT}"
if [[ ! -f "$FILE" ]]; then echo "MISSING $FILE"; exit 1; fi
echo "== $FILE"; ls -la "$FILE"
plutil -lint "$FILE"
echo "DisplayVendorID=$(plutil -extract DisplayVendorID raw "$FILE") DisplayProductID=$(plutil -extract DisplayProductID raw "$FILE")"
DUMP=$(plutil -p "$FILE")
echo "entries 8 bytes (1x): $(echo "$DUMP" | grep -c 'length = 8,')"
echo "entries 16 bytes (HiDPI): $(echo "$DUMP" | grep -c 'length = 16,')"
