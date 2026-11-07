#!/usr/bin/env bash
# Install the exact SwiftFormat release used by the repository into the build directory.
set -euo pipefail

version="${1:?usage: install-formatter.sh X.Y.Z}"
tools_dir="$(pwd)/.build/tools"
mkdir -p "${tools_dir}"
if [[ -x "${tools_dir}/swiftformat" ]] && [[ "$("${tools_dir}/swiftformat" --version)" == "${version}" ]]; then
    exit 0
fi
archive="$(mktemp -t quota-swiftformat)"
trap 'rm -f "${archive}"' EXIT
curl -fsSL "https://github.com/nicklockwood/SwiftFormat/releases/download/${version}/swiftformat.zip" -o "${archive}"
unzip -oq "${archive}" -d "${tools_dir}"
installed="$("${tools_dir}/swiftformat" --version)"
if [[ "${installed}" != "${version}" ]]; then
    echo "error: expected SwiftFormat ${version}, got ${installed}" >&2
    exit 1
fi
echo "SwiftFormat ${installed}"
