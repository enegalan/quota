#!/bin/bash
# Picks the Xcode the job should build with, and says which one it picked.
#
# The image default is tried first: on the Apple Silicon image that is already the
# compiler the tests are written against, and a loop that searches for a named
# Xcode can only ever downgrade it. Only when the default is too old does this go
# looking, and then only for one that is newer, never older.
#
# Swift 6.3 is the floor, not a preference. The tests are written against it:
# 6.3 accepts a throwing call inside `#expect`, 6.2 does not, and a job on 6.2
# dies after hundreds of lines that point at test bodies rather than at the
# toolchain. An application and its plugins build on either.
#
# Usage: select-xcode.sh [--require-tests]
#   --require-tests  fail when no Xcode here carries Swift 6.3, instead of
#                    settling for an older one and skipping the tests
#
# Exports SWIFT_MAJOR and SWIFT_MINOR, and writes them to $GITHUB_ENV when set.

set -euo pipefail

readonly required_major=6
readonly required_minor=3

require_tests=false
if [[ "${1:-}" == "--require-tests" ]]; then
  require_tests=true
fi

current_version() {
  swift --version 2>/dev/null |
    sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1.\2/p'
}

carries_required() {
  local version="$1" major minor
  [[ -n "${version}" ]] || return 1
  major="${version%%.*}"
  minor="${version##*.}"
  ((major > required_major)) && return 0
  ((major == required_major && minor >= required_minor))
}

report() {
  local version="$1" path="$2"
  echo "Swift ${version} from ${path}"
  echo "SWIFT_MAJOR=${version%%.*}" >>"${GITHUB_ENV:-/dev/null}"
  echo "SWIFT_MINOR=${version##*.}" >>"${GITHUB_ENV:-/dev/null}"
}

# 1. The image default, if it is new enough.
version="$(current_version)"
if carries_required "${version}"; then
  report "${version}" "$(xcode-select -p)"
  exit 0
fi

# 2. Otherwise the newest Xcode here that carries it, newest last.
fallback=""
for app in $(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -V); do
  [[ -d "${app}" ]] || continue
  fallback="${app}"
  sudo xcode-select --switch "${app}"
  version="$(current_version)"
  if carries_required "${version}"; then
    report "${version}" "${app}"
    exit 0
  fi
done

# 3. Nothing here carries it. An older Xcode still builds the application.
if [[ "${require_tests}" == "true" ]]; then
  echo "::error::no Xcode on this image carries Swift ${required_major}.${required_minor} or later, and the test suite needs it"
  exit 1
fi
version="$(current_version)"
if [[ -z "${fallback}" ]]; then
  fallback="$(xcode-select -p)"
fi
report "${version}" "${fallback}"
echo "::warning::Swift ${version} cannot build the test suite; this job verifies the bundle only"
