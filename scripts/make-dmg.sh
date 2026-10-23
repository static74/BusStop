#!/usr/bin/env bash
#
# Packs "build/Bus Stop.app" into build/BusStop.dmg, the disk image releases
# ship. The image opens to the app, a link to /Applications to drag it onto,
# and the licence and third-party notices:
#   Bus Stop.app
#   Applications -> /Applications
#   LICENSE.txt
#   THIRD_PARTY_NOTICES.md
#
# Usage: scripts/make-dmg.sh
#
# Run it after scripts/build-app.sh, and after scripts/notarize.sh when the app
# is notarized, so the image holds the stapled app. When SIGN_IDENTITY names a
# Developer ID Application identity, the image is signed with it too, ready for
# `scripts/notarize.sh build/BusStop.dmg`. Otherwise the image is left unsigned.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Bus Stop"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
DMG="$BUILD_DIR/BusStop.dmg"
STAGE="$BUILD_DIR/dmg-root"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'make-dmg.sh: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "this script needs macOS (it uses hdiutil and codesign)"
for tool in hdiutil ditto codesign; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool was not found; install Xcode 27 or Xcode 26.6"
done
[[ -d "$APP" ]] || fail "$APP is missing; run scripts/build-app.sh first"
# The MIT and BSD licences of the projects Bus Stop builds on require their
# notices in every copy, so the image carries them next to the app, as the
# zip does.
for notice in LICENSE THIRD_PARTY_NOTICES.md; do
    [[ -s "$notice" ]] || fail "$notice is missing or empty; every copy of the app must carry it"
done

log "Staging the disk image"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
cp LICENSE "$STAGE/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$STAGE/THIRD_PARTY_NOTICES.md"
ln -s /Applications "$STAGE/Applications"

log "Creating $DMG"
# hdiutil sometimes fails with "Resource busy" on CI runners; a retry a few
# seconds later succeeds.
for attempt in 1 2 3; do
    if hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"; then
        break
    fi
    (( attempt < 3 )) || fail "hdiutil create failed after $attempt attempts"
    sleep 5
done
rm -rf "$STAGE"
hdiutil verify "$DMG"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    log "Signing the disk image as $SIGN_IDENTITY"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    codesign --verify --verbose=2 "$DMG"
fi

log "Done"
printf '  Image:  %s (%s bytes)\n' "$DMG" "$(wc -c < "$DMG" | tr -d ' ')"
printf '  Signed: %s\n' "$([[ "$SIGN_IDENTITY" == "-" ]] && echo "no" || echo "$SIGN_IDENTITY")"
