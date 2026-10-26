#!/usr/bin/env bash
#
# Builds "build/Bus Stop.app" from the Swift package, signs it and zips it,
# with the licence and third-party notices beside it, to build/BusStop.zip.
#
# Usage: scripts/build-app.sh
#
# Environment:
#   VERSION        CFBundleShortVersionString. Default: BusStopVersion.string
#                  from Sources/BusStopCore/Version.swift. A leading "v" is
#                  dropped, so a tag name such as v1.2.0 works.
#   BUILD          CFBundleVersion. Default: the number of commits in HEAD.
#   ARCHS          arm64 (default), x86_64, "arm64 x86_64" or universal.
#                  Several architectures are built one by one and merged with
#                  lipo.
#   CONFIGURATION  release (default) or debug.
#   SIGN_IDENTITY  The codesign identity. Default "-", which signs ad hoc. A
#                  Developer ID Application identity (its name or SHA-1 hash)
#                  also gets a secure timestamp, which notarization needs; see
#                  scripts/notarize.sh. With a team's identity (not ad hoc)
#                  both Info.plists get the team ID as BusStopTeamID, and the
#                  app and the extension both claim the App Group
#                  <team>.io.github.static74.busstop, through which the app
#                  hands the widgets their data.
#
# Layout of the bundle:
#   Contents/Info.plist            from Support/Info.plist, version stamped
#   Contents/PkgInfo               "APPL????"
#   Contents/MacOS/BusStop         the BusStopApp product
#   Contents/Helpers/busstop       the command-line tool
#   Contents/PlugIns/BusStopWidgets.appex   the desktop widgets, from
#                                           Support/Widgets-Info.plist
#   Contents/Resources/AppIcon.icns
#   Contents/Resources/LICENSE.txt                Bus Stop's MIT License
#   Contents/Resources/THIRD_PARTY_NOTICES.md     PortScope, WhatPort, WhatCable,
#                                                 USB ID Repository
#
# The CLI lives in Contents/Helpers because Contents/MacOS/busstop and
# Contents/MacOS/BusStop would be the same file on a case-insensitive volume.
#
# The MIT and BSD licences of the projects Bus Stop adapts code and data from
# require their notices in every copy, so the bundle carries them, and the zip
# holds them again next to the app:
#   Bus Stop.app
#   LICENSE.txt
#   THIRD_PARTY_NOTICES.md

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Bus Stop"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
ZIP="$BUILD_DIR/BusStop.zip"
STAGE="$BUILD_DIR/stage"
ZIP_ROOT="$BUILD_DIR/zip-root"
CONFIGURATION="${CONFIGURATION:-release}"
HELPER_IDENTIFIER="io.github.static74.busstop.cli"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'build-app.sh: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "this script needs macOS (it uses codesign, plutil, lipo and ditto)"
for tool in swift codesign plutil lipo ditto xattr; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool was not found; install Xcode 27 or Xcode 26.6"
done
case "$CONFIGURATION" in
    release | debug) ;;
    *) fail "CONFIGURATION must be release or debug, not '$CONFIGURATION'" ;;
esac

# MARK: Version

default_version() {
    sed -nE 's/.*static let string = "([^"]+)".*/\1/p' Sources/BusStopCore/Version.swift | head -n 1
}

VERSION="${VERSION:-$(default_version)}"
VERSION="${VERSION#v}"
[[ -n "$VERSION" ]] || fail "could not read the version from Sources/BusStopCore/Version.swift; set VERSION"
if [[ -z "${BUILD:-}" ]]; then
    BUILD="$(git rev-list --count HEAD 2>/dev/null || true)"
    BUILD="${BUILD:-1}"
fi

# MARK: Architectures

ARCHS="${ARCHS:-arm64}"
if [[ "$ARCHS" == "universal" ]]; then
    ARCH_LIST=(arm64 x86_64)
else
    read -r -a ARCH_LIST <<< "$ARCHS"
fi
(( ${#ARCH_LIST[@]} > 0 )) || fail "ARCHS is empty"
for arch in "${ARCH_LIST[@]}"; do
    case "$arch" in
        arm64 | x86_64) ;;
        *) fail "unsupported architecture '$arch'; use arm64, x86_64 or universal" ;;
    esac
done

log "Bus Stop $VERSION (build $BUILD), $CONFIGURATION, ${ARCH_LIST[*]}"
swift --version

# MARK: Build

# Each architecture is built on its own and its binaries copied out at once:
# the Swift Build system can reuse one output directory for consecutive
# single-architecture builds. A single build for this Mac's own architecture
# leaves out --arch, so it takes the same path as a plain `swift build`.
HOST_ARCH="$(uname -m)"
rm -rf "$STAGE"
for arch in "${ARCH_LIST[@]}"; do
    arch_args=()
    if (( ${#ARCH_LIST[@]} > 1 )) || [[ "$arch" != "$HOST_ARCH" ]]; then
        arch_args=(--arch "$arch")
    fi
    log "Building BusStopApp, busstop and BusStopWidgets for $arch"
    swift build -c "$CONFIGURATION" ${arch_args[@]+"${arch_args[@]}"} --product BusStopApp
    swift build -c "$CONFIGURATION" ${arch_args[@]+"${arch_args[@]}"} --product busstop
    swift build -c "$CONFIGURATION" ${arch_args[@]+"${arch_args[@]}"} --product BusStopWidgets
    bin_path="$(swift build -c "$CONFIGURATION" ${arch_args[@]+"${arch_args[@]}"} --show-bin-path)"
    [[ -x "$bin_path/BusStopApp" ]] || fail "BusStopApp was not found in $bin_path"
    [[ -x "$bin_path/busstop" ]] || fail "busstop was not found in $bin_path"
    [[ -x "$bin_path/BusStopWidgets" ]] || fail "BusStopWidgets was not found in $bin_path"
    # Staged as "app" and "cli": "BusStop" and "busstop" would be one file on
    # a case-insensitive volume.
    mkdir -p "$STAGE/$arch"
    cp "$bin_path/BusStopApp" "$STAGE/$arch/app"
    cp "$bin_path/busstop" "$STAGE/$arch/cli"
    cp "$bin_path/BusStopWidgets" "$STAGE/$arch/widgets"
done

# Copies one staged binary into the bundle, merging architectures with lipo.
install_binary() {
    local name="$1" destination="$2"
    local inputs=()
    for arch in "${ARCH_LIST[@]}"; do
        inputs+=("$STAGE/$arch/$name")
    done
    if (( ${#inputs[@]} == 1 )); then
        cp "${inputs[0]}" "$destination"
    else
        lipo -create -output "$destination" "${inputs[@]}"
    fi
    chmod 755 "$destination"
}

# MARK: Assemble

log "Assembling $APP"
rm -rf "$APP" "$ZIP"
APPEX="$APP/Contents/PlugIns/BusStopWidgets.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

install_binary app "$APP/Contents/MacOS/BusStop"
install_binary cli "$APP/Contents/Helpers/busstop"
install_binary widgets "$APPEX/Contents/MacOS/BusStopWidgets"

cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/Widgets-Info.plist "$APPEX/Contents/Info.plist"
# The extension carries the app's version, or the system may keep an old copy.
for plist in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$plist"
    plutil -replace CFBundleVersion -string "$BUILD" "$plist"
    plutil -lint "$plist"
done

[[ -f Support/AppIcon.icns ]] || fail "Support/AppIcon.icns is missing; run scripts/make-icon.py"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Licence notices. They go in before signing: a file added afterwards would
# break the bundle's seal.
for notice in LICENSE THIRD_PARTY_NOTICES.md; do
    [[ -s "$notice" ]] || fail "$notice is missing or empty; every copy of the app must carry it"
done
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# MARK: Sign

# Extended attributes (quarantine, Finder info) make codesign refuse the bundle.
xattr -cr "$APP"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
sign_args=(--force --options runtime --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    log "Signing ad hoc with the hardened runtime"
else
    # Apple's notary service rejects code without a secure timestamp.
    sign_args+=(--timestamp)
    log "Signing as $SIGN_IDENTITY with the hardened runtime"
fi
codesign "${sign_args[@]}" --identifier "$HELPER_IDENTIFIER" "$APP/Contents/Helpers/busstop"

# The team ID is the signing certificate's OU, which codesign reports as
# TeamIdentifier; an ad hoc signature has none, so there is no App Group either.
TEAM_ID="$(codesign --display --verbose=2 "$APP/Contents/Helpers/busstop" 2>&1 \
    | sed -nE 's/^TeamIdentifier=([A-Z0-9]+)$/\1/p')"
WIDGETS_ENTITLEMENTS="Support/Widgets.entitlements"
app_entitlements=()
APP_GROUP=""
if [[ -n "$TEAM_ID" ]]; then
    APP_GROUP="$TEAM_ID.io.github.static74.busstop"
    log "Team $TEAM_ID: App Group $APP_GROUP"
    for plist in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
        plutil -replace BusStopTeamID -string "$TEAM_ID" "$plist"
    done
    # Since macOS 15 both processes must claim the group, the unsandboxed app included.
    ENTITLEMENTS_DIR="$BUILD_DIR/entitlements"
    rm -rf "$ENTITLEMENTS_DIR"
    mkdir -p "$ENTITLEMENTS_DIR"
    cp "$WIDGETS_ENTITLEMENTS" "$ENTITLEMENTS_DIR/widgets.entitlements"
    plutil -create xml1 "$ENTITLEMENTS_DIR/app.entitlements"
    for file in "$ENTITLEMENTS_DIR/widgets.entitlements" "$ENTITLEMENTS_DIR/app.entitlements"; do
        /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups array" \
            -c "Add :com.apple.security.application-groups:0 string $APP_GROUP" "$file"
        plutil -lint "$file"
    done
    WIDGETS_ENTITLEMENTS="$ENTITLEMENTS_DIR/widgets.entitlements"
    app_entitlements=(--entitlements "$ENTITLEMENTS_DIR/app.entitlements")
fi

# Nested code is signed first. macOS loads a widget extension only when it is
# sandboxed, and lists it in the widget gallery only when it is signed by a
# team: an ad hoc build bundles the widgets but the gallery leaves them out.
codesign "${sign_args[@]}" --entitlements "$WIDGETS_ENTITLEMENTS" "$APPEX"
codesign "${sign_args[@]}" ${app_entitlements[@]+"${app_entitlements[@]}"} "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# MARK: Package

log "Zipping"
# The zip holds the app and, beside it, the same notices as the bundle.
# ditto copies the signed bundle unchanged.
rm -rf "$ZIP_ROOT"
mkdir -p "$ZIP_ROOT"
ditto "$APP" "$ZIP_ROOT/$APP_NAME.app"
cp LICENSE "$ZIP_ROOT/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$ZIP_ROOT/THIRD_PARTY_NOTICES.md"
ditto -c -k "$ZIP_ROOT" "$ZIP"
rm -rf "$STAGE" "$ZIP_ROOT" "$BUILD_DIR/entitlements"

log "Done"
printf '  App:       %s\n' "$APP"
printf '  Zip:       %s (%s bytes)\n' "$ZIP" "$(wc -c < "$ZIP" | tr -d ' ')"
printf '  Version:   %s (build %s)\n' "$VERSION" "$BUILD"
printf '  App archs: %s\n' "$(lipo -archs "$APP/Contents/MacOS/BusStop")"
printf '  CLI archs: %s\n' "$(lipo -archs "$APP/Contents/Helpers/busstop")"
printf '  Widgets:   %s\n' "$(lipo -archs "$APPEX/Contents/MacOS/BusStopWidgets")"
printf '  Signed:    %s\n' "$([[ "$SIGN_IDENTITY" == "-" ]] && echo "ad hoc" || echo "$SIGN_IDENTITY")"
printf '  App Group: %s\n' "${APP_GROUP:-none (no team)}"
