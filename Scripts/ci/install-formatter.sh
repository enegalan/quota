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
repo="nicklockwood/SwiftFormat"
asset="swiftformat.zip"

download_with_gh() {
    command -v gh >/dev/null 2>&1 || return 1
    gh release download "${version}" \
        --repo "${repo}" \
        --pattern "${asset}" \
        --output "${archive}" \
        --clobber
}

# Authenticated asset API avoids the public release CDN, which is what answers
# 503 to bare curl from some GitHub Actions runners.
download_with_api() {
    [[ -n "${GITHUB_TOKEN:-}" ]] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    local asset_url
    asset_url="$(
        curl -fsSL \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${repo}/releases/tags/${version}" |
            python3 -c '
import json, sys
release = json.load(sys.stdin)
for asset in release.get("assets", []):
    if asset.get("name") == "'"${asset}"'":
        print(asset["url"])
        raise SystemExit(0)
raise SystemExit("asset not listed on the release")
'
    )"
    curl -fsSL \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/octet-stream" \
        -o "${archive}" \
        "${asset_url}"
}

download_with_curl() {
    local url="https://github.com/${repo}/releases/download/${version}/${asset}"
    local attempt
    for attempt in 1 2 3 4 5; do
        if curl -fsSL "${url}" -o "${archive}"; then
            return 0
        fi
        echo "warning: SwiftFormat CDN download failed (attempt ${attempt}/5); retrying…" >&2
        sleep $((attempt * 5))
    done
    return 1
}

downloaded=false
if download_with_gh; then
    downloaded=true
elif download_with_api; then
    downloaded=true
elif download_with_curl; then
    downloaded=true
fi
if [[ "${downloaded}" != true ]]; then
    echo "error: could not download SwiftFormat ${version} (${asset})" >&2
    exit 1
fi

unzip -oq "${archive}" -d "${tools_dir}"
installed="$("${tools_dir}/swiftformat" --version)"
if [[ "${installed}" != "${version}" ]]; then
    echo "error: expected SwiftFormat ${version}, got ${installed}" >&2
    exit 1
fi
echo "SwiftFormat ${installed}"
