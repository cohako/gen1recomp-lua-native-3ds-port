#!/bin/sh
# macOS double-click wrapper: runs the shell script next to it and keeps the
# Terminal window open so you can read the result.
cd "$(dirname "$0")" && ./Export-3DS.sh
echo
echo "Press return to close."
read _
