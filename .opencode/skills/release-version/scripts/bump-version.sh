#!/usr/bin/env bash
# Set Quota's CFBundleShortVersionString in App/Info.plist.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 X.Y.Z" >&2
    exit 2
fi

version="$1"
root="$(cd "$(dirname "$0")/../../../.." && pwd)"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" \
    "${root}/App/Info.plist"

echo "CFBundleShortVersionString = ${version}"