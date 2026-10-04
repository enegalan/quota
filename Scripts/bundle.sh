#!/usr/bin/env bash
#
# Assembles Quota.app from the built executable.
#
# SwiftPM produces a bare Mach-O executable. A macOS menu bar application needs a
# bundle with an Info.plist, a bundle identifier, and a place to keep the packaged
# providers, so this script lays the bundle out and reports where it put it.
#
# Usage: Scripts/bundle.sh [--debug|--release] [--sign "Developer ID Application: ..."]
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_DIR="${REPO_ROOT}/.build"
readonly APP_NAME="Quota"
readonly BUNDLE_DIR="${BUILD_DIR}/${APP_NAME}.app"
readonly CONTENTS_DIR="${BUNDLE_DIR}/Contents"
readonly MACOS_DIR="${CONTENTS_DIR}/MacOS"
readonly RESOURCES_DIR="${CONTENTS_DIR}/Resources"

readonly EXIT_INVALID_ARGUMENT=2

configuration="debug"
signing_identity="-"

usage() {
    cat <<'USAGE'
Usage: Scripts/bundle.sh [options]

Options:
  --debug              Build the debug configuration (default).
  --release            Build the release configuration.
  --sign <identity>    Sign with the given identity. Defaults to ad-hoc ("-"),
                       which is enough to run locally but not to distribute.
  -h, --help           Show this message.
USAGE
}

log() { printf '%s\n' "==> $*"; }
fail() { printf '%s\n' "error: $*" >&2; exit "${EXIT_INVALID_ARGUMENT}"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
    --debug)
        configuration="debug"
        shift
        ;;
    --release)
        configuration="release"
        shift
        ;;
    --sign)
        [[ $# -ge 2 ]] || fail "--sign requires an identity"
        signing_identity="$2"
        shift 2
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        fail "unknown argument '$1'"
        ;;
    esac
done

swift build --package-path "${REPO_ROOT}" -c "${configuration}" --product "${APP_NAME}"

# A bundled provider ships as a gzipped tar rather than a directory: the app
# bundle is read-only, and packaging it means the install path for a bundled
# provider and a downloaded one is the same code.
#
# The list of providers is the list of plugin packages, and the file each one is
# discovered as is the executable's own name. A provider whose package did not
# build is a packaging failure, not something to ship quietly, so this fails
# rather than skipping.
readonly PROVIDERS_DIR_NAME="Providers"
readonly ARTIFACT_FILE_EXTENSION="tar.gz"

package_bundled_providers() {
    local providers_dir="$1"
    mkdir -p "${providers_dir}"
    local scratch="${TMPDIR:-/tmp}/quota-bundled-providers"
    rm -rf "${scratch}"
    mkdir -p "${scratch}"
    shopt -s nullglob
    for plugin_dir in "${REPO_ROOT}"/Plugins/*/; do
        local id
        id="$(basename "${plugin_dir}")"
        local executable="quota-provider-${id}"
        log "Packaging bundled provider ${id}"
        swift build --package-path "${plugin_dir}" -c "${configuration}" \
            --scratch-path "${scratch}/${id}" >/dev/null
        local bin_path
        bin_path="$(swift build --package-path "${plugin_dir}" -c "${configuration}" \
            --scratch-path "${scratch}/${id}" --show-bin-path)"
        [[ -f "${bin_path}/${executable}" ]] \
            || fail "Plugins/${id} built no executable named ${executable}"
        # The staged directory is named for the executable the host looks for, so
        # the archive installs to a version directory the host can start.
        local staged="${scratch}/stage-${id}/${executable}"
        mkdir -p "${staged}"
        cp "${bin_path}/${executable}" "${staged}/${executable}"
        tar -czf "${providers_dir}/${id}.${ARTIFACT_FILE_EXTENSION}" \
            -C "${scratch}/stage-${id}" "${executable}"
    done
    shopt -u nullglob
}
readonly BUILT_EXECUTABLE="${BUILD_DIR}/${configuration}/${APP_NAME}"
[[ -f "${BUILT_EXECUTABLE}" ]] || fail "expected executable not found at ${BUILT_EXECUTABLE}"

log "Assembling ${BUNDLE_DIR}"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BUILT_EXECUTABLE}" "${MACOS_DIR}/${APP_NAME}"
cp "${REPO_ROOT}/App/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${REPO_ROOT}/Sources/App/Resources/quota.png" "${RESOURCES_DIR}/quota.png"

# Dock and Finder read AppIcon.icns. The 1024 master and Icon Composer
# package (App/quota.icon) live in the repository; only the compiled icon
# ships in the bundle.
readonly APP_ICON_PNG="${REPO_ROOT}/App/AppIcon.png"
[[ -f "${APP_ICON_PNG}" ]] || fail "expected app icon at ${APP_ICON_PNG}"
iconset_dir="${TMPDIR:-/tmp}/quota-AppIcon.iconset"
rm -rf "${iconset_dir}"
mkdir -p "${iconset_dir}"
for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${APP_ICON_PNG}" \
        --out "${iconset_dir}/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "${APP_ICON_PNG}" \
        --out "${iconset_dir}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${iconset_dir}" -o "${RESOURCES_DIR}/AppIcon.icns"
rm -rf "${iconset_dir}"

package_bundled_providers "${RESOURCES_DIR}/${PROVIDERS_DIR_NAME}"
printf 'APPL????' >"${CONTENTS_DIR}/PkgInfo"

codesign --force --sign "${signing_identity}" --entitlements "${REPO_ROOT}/App/Quota.entitlements" \
    "${BUNDLE_DIR}"

log "Verifying signature"
codesign --verify --verbose=2 "${BUNDLE_DIR}"

log "Built ${BUNDLE_DIR}"
