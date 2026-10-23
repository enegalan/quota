#!/usr/bin/env bash
# Install the SwiftFormat version this repo formats against.
#
# GitHub-hosted macOS runners often already have an older Homebrew bottle.
# `brew install` then no-ops, and `brew upgrade` without `brew update` keeps
# that older bottle — so CI lints with a different formatter than the one that
# wrote the tree. Updating the tap first, then forcing the upgrade, makes the
# runner match a maintainer who just ran `brew upgrade swiftformat`.
set -euo pipefail

version="${1:?usage: install-formatter.sh X.Y.Z}"

if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew is required" >&2
    exit 1
fi

brew update
brew install swiftformat
brew upgrade swiftformat

installed="$(swiftformat --version)"
if [[ "${installed}" != "${version}" ]]; then
    echo "error: expected SwiftFormat ${version}, got ${installed}" >&2
    echo "error: format the tree with that version, or bump the pin in the Makefile." >&2
    exit 1
fi

echo "SwiftFormat ${installed}"
