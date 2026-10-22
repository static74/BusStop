#!/usr/bin/env bash
#
# Sends build/BusStop.zip to Apple's notary service, staples the ticket to
# "build/Bus Stop.app" and zips the stapled app again, so the app opens on
# other Macs without a Gatekeeper warning, even offline.
#
# Usage: scripts/notarize.sh
#
# Run it after scripts/build-app.sh with SIGN_IDENTITY set to a Developer ID
# Application identity. The notary credentials come from the environment, in
# one of three forms (the first one set wins):
#
#   NOTARY_PROFILE      a profile saved with `xcrun notarytool store-credentials`
#   NOTARY_KEY_PATH     an App Store Connect API key (.p8), with
#                       NOTARY_KEY_ID and NOTARY_ISSUER_ID
#   NOTARY_APPLE_ID     an Apple ID, with NOTARY_PASSWORD (an app-specific
#                       password) and NOTARY_TEAM_ID

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Bus Stop"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
ZIP="$BUILD_DIR/BusStop.zip"
ZIP_ROOT="$BUILD_DIR/notarize-root"
RESULT="$BUILD_DIR/notarize-result.plist"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'notarize.sh: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "this script needs macOS (it uses notarytool, stapler and spctl)"
for tool in xcrun codesign spctl ditto plutil; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool was not found; install Xcode 27 or Xcode 26.6"
done
[[ -d "$APP" && -f "$ZIP" ]] || fail "$APP or $ZIP is missing; run scripts/build-app.sh first"

# MARK: Credentials

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    credentials=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]] || fail "NOTARY_KEY_PATH needs NOTARY_KEY_ID and NOTARY_ISSUER_ID"
    [[ -s "$NOTARY_KEY_PATH" ]] || fail "the API key $NOTARY_KEY_PATH is missing or empty"
    credentials=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
elif [[ -n "${NOTARY_APPLE_ID:-}" ]]; then
    [[ -n "${NOTARY_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]] || fail "NOTARY_APPLE_ID needs NOTARY_PASSWORD and NOTARY_TEAM_ID"
    credentials=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID")
else
    fail "no notary credentials; set NOTARY_PROFILE, NOTARY_KEY_PATH or NOTARY_APPLE_ID (see the top of this script)"
fi

# The notary service accepts only code signed with a Developer ID; checking
# first saves a round trip that would end in "Invalid".
signature="$(codesign --display --verbose=2 "$APP" 2>&1)"
if ! grep -q '^Authority=Developer ID Application:' <<< "$signature"; then
    printf '%s\n' "$signature"
    fail "$APP is not signed with a Developer ID Application identity; build it with SIGN_IDENTITY set"
fi

# MARK: Submit

log "Submitting $ZIP to Apple's notary service (this usually takes a few minutes)"
# notarytool's exit status does not say whether Apple accepted the build, so
# the status in its output decides.
xcrun notarytool submit "$ZIP" "${credentials[@]}" --wait --timeout 1h --output-format plist > "$RESULT" || true
cat "$RESULT"
submission_id="$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || true)"
status="$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || true)"
if [[ "$status" != "Accepted" ]]; then
    if [[ -n "$submission_id" ]]; then
        log "Notary log for submission $submission_id"
        xcrun notarytool log "$submission_id" "${credentials[@]}" || true
    fi
    fail "notarization did not succeed (status: ${status:-unknown})"
fi

# MARK: Staple

log "Stapling the ticket to $APP"
# The ticket can take a short while to reach Apple's servers after the
# submission is accepted.
for attempt in 1 2 3 4 5; do
    if xcrun stapler staple "$APP"; then
        break
    fi
    (( attempt < 5 )) || fail "stapling failed after $attempt attempts"
    sleep 20
done
xcrun stapler validate "$APP"

log "Checking the app with Gatekeeper"
spctl --assess --type execute --verbose=4 "$APP"

# MARK: Package

log "Zipping the stapled app"
# The zip keeps build-app.sh's layout, with the licence notices beside the
# app; only the app inside it is replaced by the stapled copy.
rm -rf "$ZIP_ROOT"
mkdir -p "$ZIP_ROOT"
ditto -x -k "$ZIP" "$ZIP_ROOT"
[[ -d "$ZIP_ROOT/$APP_NAME.app" ]] || fail "$ZIP does not hold $APP_NAME.app"
rm -rf "$ZIP_ROOT/$APP_NAME.app"
ditto "$APP" "$ZIP_ROOT/$APP_NAME.app"
rm -f "$ZIP"
ditto -c -k "$ZIP_ROOT" "$ZIP"
rm -rf "$ZIP_ROOT" "$RESULT"

log "Done"
printf '  Submission: %s\n' "$submission_id"
printf '  Zip:        %s (%s bytes)\n' "$ZIP" "$(wc -c < "$ZIP" | tr -d ' ')"
