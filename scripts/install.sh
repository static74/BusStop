#!/usr/bin/env bash
#
# Builds Bus Stop from source, installs it and opens it.
#
# Usage: scripts/install.sh [--link-cli] [--no-open]
#
#   --link-cli   Also link the busstop command into /usr/local/bin, or into
#                ~/.local/bin when /usr/local/bin is missing or not writable.
#   --no-open    Do not open the app after installing.
#
# The app goes to /Applications, or to ~/Applications when /Applications is
# not writable. A build made on this Mac carries no quarantine attribute;
# the script removes it anyway in case the source came from a download.
#
# Environment: VERSION, BUILD and CONFIGURATION are passed to build-app.sh.
# ARCHS defaults to this Mac's architecture.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Bus Stop"
LINK_CLI=0
OPEN_APP=1

fail() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
log() { printf '\n==> %s\n' "$*"; }

for argument in "$@"; do
    case "$argument" in
        --link-cli) LINK_CLI=1 ;;
        --no-open) OPEN_APP=0 ;;
        -h | --help)
            sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) printf 'install.sh: unknown option %s\n' "$argument" >&2; exit 2 ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || fail "Bus Stop runs on macOS only"

if [[ -z "${ARCHS:-}" ]]; then
    ARCHS="$(uname -m)"
fi
export ARCHS

"$ROOT/scripts/build-app.sh"

SOURCE_APP="$ROOT/build/$APP_NAME.app"
[[ -d "$SOURCE_APP" ]] || fail "the build did not produce $SOURCE_APP"

DESTINATION_DIR="/Applications"
if [[ ! -w "$DESTINATION_DIR" ]]; then
    DESTINATION_DIR="$HOME/Applications"
    mkdir -p "$DESTINATION_DIR"
fi
DESTINATION="$DESTINATION_DIR/$APP_NAME.app"

# Quit a running copy so the new one replaces it cleanly.
if pgrep -x BusStop > /dev/null 2>&1; then
    log "Quitting the running copy of $APP_NAME"
    pkill -x BusStop || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x BusStop > /dev/null 2>&1 || break
        sleep 0.5
    done
fi

log "Installing to $DESTINATION"
if [[ -e "$DESTINATION" ]]; then
    rm -rf "$DESTINATION" || fail "cannot replace $DESTINATION; remove it and run this script again"
fi
ditto "$SOURCE_APP" "$DESTINATION"
xattr -dr com.apple.quarantine "$DESTINATION" 2> /dev/null || true

if (( LINK_CLI )); then
    TARGET="$DESTINATION/Contents/Helpers/busstop"
    if [[ -d /usr/local/bin && -w /usr/local/bin ]]; then
        LINK_DIR="/usr/local/bin"
    else
        LINK_DIR="$HOME/.local/bin"
        mkdir -p "$LINK_DIR"
    fi
    ln -sf "$TARGET" "$LINK_DIR/busstop"
    log "Linked $LINK_DIR/busstop to $TARGET"
    case ":$PATH:" in
        *":$LINK_DIR:"*) ;;
        *) printf 'Add %s to your PATH to run busstop from any directory.\n' "$LINK_DIR" ;;
    esac
fi

if (( OPEN_APP )); then
    log "Opening $APP_NAME"
    open "$DESTINATION"
fi

printf '\n%s is installed at %s.\n' "$APP_NAME" "$DESTINATION"
