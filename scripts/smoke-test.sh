#!/usr/bin/env bash
#
# Checks a bundle made by scripts/build-app.sh: layout, licence notices,
# Info.plist, signature and icon; the zip next to it; the bundled CLI against
# every demo scenario and against this Mac; and that the app is still running
# a few seconds after launch.
#
# Usage: scripts/smoke-test.sh [--skip-live] [path/to/Bus Stop.app]
#
#   --skip-live   Leave out the checks that read this Mac's hardware.
#
# Every command's output is printed, because in CI this log is the only view
# of the machine. Checks keep going after a failure; the script exits with
# status 1 and lists every failed check at the end.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

SKIP_LIVE=0
APP="$ROOT/build/Bus Stop.app"
for argument in "$@"; do
    case "$argument" in
        --skip-live) SKIP_LIVE=1 ;;
        -h | --help)
            sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) printf 'smoke-test.sh: unknown option %s\n' "$argument" >&2; exit 2 ;;
        *) APP="$argument" ;;
    esac
done

CLI="$APP/Contents/Helpers/busstop"
APP_BINARY="$APP/Contents/MacOS/BusStop"
PLIST="$APP/Contents/Info.plist"
ZIP="$(dirname "$APP")/BusStop.zip"
OUT="$ROOT/build/smoke"
DEMOS=(studioDesk travel dockStation unplugged)
CLI_TIME_LIMIT=120
FAILURES=()
CHECKS=0

for tool in plutil codesign lipo iconutil python3 zipinfo; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        printf 'smoke-test.sh: %s was not found; run this on macOS with Xcode installed.\n' "$tool" >&2
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT"

# MARK: Helpers

section() { printf '\n==== %s\n' "$*"; }
pass() { CHECKS=$((CHECKS + 1)); printf 'ok:   %s\n' "$*"; }
failed() { CHECKS=$((CHECKS + 1)); FAILURES+=("$*"); printf 'FAIL: %s\n' "$*"; }

# Runs a command with its output in files, killing it after a time limit.
# Usage: run_limited SECONDS STDOUT_FILE STDERR_FILE COMMAND...
# Returns the command's exit status, or 124 when it ran out of time.
run_limited() {
    local limit="$1" stdout_file="$2" stderr_file="$3"
    shift 3
    "$@" > "$stdout_file" 2> "$stderr_file" &
    local pid=$! tenths=0
    while kill -0 "$pid" 2> /dev/null; do
        if (( tenths >= limit * 10 )); then
            kill -KILL "$pid" 2> /dev/null
            wait "$pid" 2> /dev/null
            return 124
        fi
        sleep 0.1
        tenths=$((tenths + 1))
    done
    wait "$pid"
}

# Prints a file's contents, or a note when it is empty.
show() {
    local label="$1" file="$2"
    if [[ -s "$file" ]]; then
        printf -- '--- %s ---\n' "$label"
        cat "$file"
        # Keep the log readable when the output lacks a final newline.
        [[ -z "$(tail -c 1 "$file")" ]] || printf '\n'
    else
        printf -- '--- %s: (empty) ---\n' "$label"
    fi
}

# Runs the CLI, prints what it wrote and checks its exit status.
# Usage: cli EXPECTED_STATUS NAME OUTPUT_FILE ARGUMENTS...
cli() {
    local expected="$1" name="$2" output="$3"
    shift 3
    section "$name: busstop $*"
    local status=0
    run_limited "$CLI_TIME_LIMIT" "$output" "$output.stderr" "$CLI" "$@" || status=$?
    show stdout "$output"
    show stderr "$output.stderr"
    if [[ "$status" == "$expected" ]]; then
        pass "$name (exit status $status)"
        return 0
    fi
    if [[ "$status" == 124 ]]; then
        failed "$name: no result after ${CLI_TIME_LIMIT} s"
    else
        failed "$name: exit status $status, expected $expected"
    fi
    return 1
}

# Checks that a file holds valid JSON.
valid_json() {
    local name="$1" file="$2"
    if python3 -m json.tool "$file" > /dev/null 2> "$file.json-error"; then
        pass "$name is valid JSON"
    else
        failed "$name is not valid JSON: $(head -n 3 "$file.json-error" | tr '\n' ' ')"
    fi
}

# Checks one Info.plist key.
plist_key() {
    local key="$1" expected="$2" actual
    actual="$(plutil -extract "$key" raw -o - "$PLIST" 2> /dev/null)" || actual="(missing)"
    if [[ "$actual" == "$expected" ]]; then
        pass "Info.plist $key = $actual"
    else
        failed "Info.plist $key is '$actual', expected '$expected'"
    fi
}

# Checks that a licence file exists, is not empty and names everyone it must.
# Usage: notice_file LABEL FILE TEXT...
notice_file() {
    local label="$1" file="$2" text missing=()
    shift 2
    if [[ ! -s "$file" ]]; then
        failed "$label is missing or empty"
        return
    fi
    for text in "$@"; do
        grep -qF "$text" "$file" || missing+=("$text")
    done
    if (( ${#missing[@]} == 0 )); then
        pass "$label carries $(printf "'%s' " "$@")"
    else
        failed "$label lacks $(printf "'%s' " "${missing[@]}")"
    fi
}

# Prints the newest crash report for a process name, if there is one.
show_crash_report() {
    local name="$1" report
    # ReportCrash writes the report a moment after the process dies.
    sleep 3
    # Report names are "<process>-<date>-<time>.ips", without spaces.
    # shellcheck disable=SC2012
    report="$(ls -t "$HOME/Library/Logs/DiagnosticReports/$name"-*.ips \
        "/Library/Logs/DiagnosticReports/$name"-*.ips 2> /dev/null | head -n 1)"
    if [[ -n "$report" ]]; then
        printf -- '--- crash report %s (first 120 lines) ---\n' "$report"
        head -n 120 "$report"
    fi
}

# Runs `busstop --watch ...` for a few seconds, sends SIGINT like Control-C
# and checks that it stops with status 0.
# Usage: watch_check NAME SECONDS ARGUMENTS...
watch_check() {
    local name="$1" seconds="$2"
    shift 2
    local output="$OUT/${name// /-}.txt" status=0 pid
    section "$name: busstop $* ($seconds s, then Control-C)"
    "$CLI" "$@" > "$output" 2> "$output.stderr" &
    pid=$!
    sleep "$seconds"
    if ! kill -0 "$pid" 2> /dev/null; then
        wait "$pid" 2> /dev/null || status=$?
        show stdout "$output"
        show stderr "$output.stderr"
        failed "$name exited on its own with status $status before Control-C"
        [[ "$status" == 0 ]] || show_crash_report busstop
        return
    fi
    kill -INT "$pid" 2> /dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2> /dev/null || break
        sleep 0.5
    done
    if kill -0 "$pid" 2> /dev/null; then
        kill -KILL "$pid" 2> /dev/null
        wait "$pid" 2> /dev/null
        status=124
    else
        wait "$pid" 2> /dev/null || status=$?
    fi
    show stdout "$output"
    show stderr "$output.stderr"
    if [[ "$status" == 0 ]]; then
        pass "$name stops cleanly on SIGINT"
    elif [[ "$status" == 124 ]]; then
        failed "$name was still running 5 s after SIGINT"
    else
        failed "$name ended with status $status after SIGINT"
    fi
}

# MARK: Bundle

section "Bundle layout: $APP"
if [[ ! -d "$APP" ]]; then
    printf 'FAIL: %s does not exist. Run scripts/build-app.sh first.\n' "$APP"
    exit 1
fi
find "$APP" -print | sed "s|^$ROOT/||"

for path in "Contents/Info.plist" "Contents/PkgInfo" "Contents/Resources/AppIcon.icns"; do
    if [[ -f "$APP/$path" ]]; then pass "$path exists"; else failed "$path is missing"; fi
done
for path in "Contents/MacOS/BusStop" "Contents/Helpers/busstop"; do
    if [[ -x "$APP/$path" ]]; then pass "$path is executable"; else failed "$path is missing or not executable"; fi
done
if [[ "$(cat "$APP/Contents/PkgInfo" 2> /dev/null)" == "APPL????" ]]; then
    pass "PkgInfo reads APPL????"
else
    failed "PkgInfo does not read APPL????"
fi
if cmp -s "$APP_BINARY" "$CLI"; then
    failed "Contents/MacOS/BusStop and Contents/Helpers/busstop are the same binary"
else
    pass "the app and the CLI are different binaries"
fi

# The MIT licences of PortScope, WhatPort and WhatCable require their notices
# in every copy of the software.
LICENCE_TEXT="Permission is hereby granted"
notice_file "Contents/Resources/LICENSE.txt" "$APP/Contents/Resources/LICENSE.txt" "$LICENCE_TEXT"
notice_file "Contents/Resources/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md" \
    "PortScope" "Alex Zenla" "WhatPort" "WhatCable" "Darryl Morley" "$LICENCE_TEXT"

section "Zip: $ZIP"
if [[ -f "$ZIP" ]]; then
    ZIP_LIST="$OUT/zip-contents.txt"
    if zipinfo -1 "$ZIP" > "$ZIP_LIST" 2> "$ZIP_LIST.stderr"; then
        cat "$ZIP_LIST"
        for entry in "Bus Stop.app/Contents/MacOS/BusStop" "Bus Stop.app/Contents/Helpers/busstop" \
            "Bus Stop.app/Contents/Resources/LICENSE.txt" "Bus Stop.app/Contents/Resources/THIRD_PARTY_NOTICES.md" \
            "LICENSE.txt" "THIRD_PARTY_NOTICES.md"; do
            if grep -qxF "$entry" "$ZIP_LIST"; then pass "the zip holds $entry"; else failed "the zip lacks $entry"; fi
        done
    else
        show stderr "$ZIP_LIST.stderr"
        failed "zipinfo cannot read $ZIP"
    fi
else
    printf 'No zip next to the app; skipping the zip checks.\n'
fi
if [[ ! -x "$CLI" ]]; then
    printf 'FAIL: the bundled CLI is missing, so nothing else can be checked.\n'
    exit 1
fi

section "Info.plist"
cat "$PLIST"
if plutil -lint "$PLIST"; then pass "Info.plist is well formed"; else failed "Info.plist does not pass plutil -lint"; fi
plist_key CFBundleExecutable "BusStop"
plist_key CFBundleIdentifier "io.github.static74.busstop"
plist_key CFBundleName "Bus Stop"
plist_key CFBundleDisplayName "Bus Stop"
plist_key CFBundlePackageType "APPL"
plist_key CFBundleIconFile "AppIcon"
plist_key CFBundleInfoDictionaryVersion "6.0"
plist_key CFBundleDevelopmentRegion "en"
plist_key LSMinimumSystemVersion "26.0"
plist_key LSUIElement "true"
plist_key LSApplicationCategoryType "public.app-category.utilities"
plist_key NSHighResolutionCapable "true"
BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST" 2> /dev/null || true)"
BUNDLE_BUILD="$(plutil -extract CFBundleVersion raw -o - "$PLIST" 2> /dev/null || true)"
if [[ -n "$BUNDLE_VERSION" && -n "$BUNDLE_BUILD" ]]; then
    pass "version $BUNDLE_VERSION (build $BUNDLE_BUILD)"
else
    failed "CFBundleShortVersionString or CFBundleVersion is empty"
fi

section "Signature"
if codesign --verify --deep --strict --verbose=2 "$APP"; then
    pass "codesign --verify --deep --strict"
else
    failed "the signature does not verify"
fi
for binary in "$APP" "$CLI"; do
    details="$(codesign --display --verbose=2 "$binary" 2>&1)"
    printf '%s\n' "$details"
    if grep -q "runtime" <<< "$details"; then
        pass "$(basename "$binary") is signed with the hardened runtime"
    else
        failed "$(basename "$binary") is not signed with the hardened runtime"
    fi
done

section "Architectures"
APP_ARCHS="$(lipo -archs "$APP_BINARY" 2> /dev/null || true)"
CLI_ARCHS="$(lipo -archs "$CLI" 2> /dev/null || true)"
printf 'BusStop: %s\nbusstop: %s\n' "$APP_ARCHS" "$CLI_ARCHS"
if [[ -n "$APP_ARCHS" && "$APP_ARCHS" == "$CLI_ARCHS" ]]; then
    pass "app and CLI are built for the same architectures"
else
    failed "app ($APP_ARCHS) and CLI ($CLI_ARCHS) architectures differ"
fi

section "Icon"
ICONSET="$OUT/AppIcon.iconset"
if iconutil -c iconset -o "$ICONSET" "$APP/Contents/Resources/AppIcon.icns"; then
    ls -l "$ICONSET"
    if [[ -f "$ICONSET/icon_512x512@2x.png" && -f "$ICONSET/icon_16x16.png" ]]; then
        pass "AppIcon.icns opens with iconutil and has 16 to 1024 px images"
    else
        failed "AppIcon.icns lacks the 16 px or 1024 px image"
    fi
else
    failed "iconutil cannot read AppIcon.icns"
fi

# MARK: CLI basics

cli 0 "version" "$OUT/version.txt" --version
if [[ -n "$BUNDLE_VERSION" ]] && grep -qF "busstop $BUNDLE_VERSION" "$OUT/version.txt"; then
    pass "--version reports the bundle version $BUNDLE_VERSION"
else
    failed "--version does not report the bundle version $BUNDLE_VERSION"
fi
cli 0 "help" "$OUT/help.txt" --help
cli 2 "unknown option" "$OUT/unknown.txt" --no-such-option
cli 2 "unknown demo" "$OUT/unknown-demo.txt" --demo no-such-scenario
if grep -q "studioDesk" "$OUT/unknown-demo.txt.stderr"; then
    pass "an unknown demo name lists the valid names"
else
    failed "an unknown demo name does not list the valid names"
fi
cli 1 "missing input file" "$OUT/missing-input.txt" --input "$OUT/does-not-exist.json"

# Standard output open for reading only, so every write fails with EBADF: the
# command must report it and exit with status 1, as on a full disk.
section "write error: busstop --demo studioDesk with standard output not writable"
WRITE_STATUS=0
# shellcheck disable=SC2016 # $0 expands in the inner shell.
run_limited "$CLI_TIME_LIMIT" "$OUT/write-error.txt" "$OUT/write-error.txt.stderr" \
    /bin/bash -c 'exec "$0" --demo studioDesk 1< /dev/null' "$CLI" || WRITE_STATUS=$?
show stderr "$OUT/write-error.txt.stderr"
if [[ "$WRITE_STATUS" == 1 ]] && grep -q "cannot write" "$OUT/write-error.txt.stderr"; then
    pass "a failed write to standard output ends with status 1 and a message"
else
    failed "a failed write to standard output ended with status $WRITE_STATUS, expected 1 and a message"
fi

# MARK: Demo scenarios

for demo in "${DEMOS[@]}"; do
    cli 0 "demo $demo text" "$OUT/demo-$demo.txt" --demo "$demo"
    if cli 0 "demo $demo JSON" "$OUT/demo-$demo.json" --demo "$demo" --json; then
        valid_json "demo $demo JSON" "$OUT/demo-$demo.json"
    fi
    cli 0 "demo $demo Markdown" "$OUT/demo-$demo.md" --demo "$demo" --markdown
    if cli 0 "demo $demo raw" "$OUT/demo-$demo-raw.json" --demo "$demo" --raw; then
        valid_json "demo $demo raw capture" "$OUT/demo-$demo-raw.json"
        if cli 0 "demo $demo raw read back" "$OUT/demo-$demo-roundtrip.json" \
            --input "$OUT/demo-$demo-raw.json" --json; then
            valid_json "demo $demo raw read back" "$OUT/demo-$demo-roundtrip.json"
        fi
    fi
done

watch_check "demo watch" 7 --watch --demo studioDesk
# The sample device is unplugged on the third tick, about 4 s in.
if grep -Eq '^[0-9]{2}:[0-9]{2}:[0-9]{2} - .+ disconnected' "$OUT/demo-watch.txt"; then
    pass "demo watch prints a disconnection line"
else
    failed "demo watch printed no disconnection line"
fi
if LC_ALL=C grep -q '[[:cntrl:]]' "$OUT/demo-watch.txt"; then
    failed "demo watch output contains control characters"
else
    pass "demo watch output has no control characters"
fi

watch_check "demo watch JSON" 7 --watch --json --demo dockStation
if python3 - "$OUT/demo-watch-JSON.txt" << 'PYTHON'
import json, sys
lines = [line for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
events = [json.loads(line) for line in lines]
assert events, "no events"
for event in events:
    assert {"id", "kind", "title", "date"} <= event.keys(), f"missing keys in {event}"
PYTHON
then
    pass "demo watch JSON prints one valid event object per line"
else
    failed "demo watch JSON did not print valid event objects, one per line"
fi

watch_check "demo watch unplugged" 3 --watch --demo unplugged
if grep -q "nothing plugged in" "$OUT/demo-watch-unplugged.txt.stderr"; then
    pass "demo watch on the unplugged setup says that no events will appear"
else
    failed "demo watch on the unplugged setup does not say that no events will appear"
fi

# MARK: Live

if (( SKIP_LIVE )); then
    section "Live checks skipped (--skip-live)"
else
    LIVE_RAW="$ROOT/build/live-raw.json"
    rm -f "$LIVE_RAW"
    if cli 0 "live raw capture" "$LIVE_RAW" --raw; then
        valid_json "live raw capture" "$LIVE_RAW"
        if cli 0 "live capture read back" "$OUT/live-from-raw.json" --input "$LIVE_RAW" --json; then
            valid_json "live capture read back" "$OUT/live-from-raw.json"
        fi
    else
        show_crash_report busstop
        printf 'Skipping the read-back check because the raw capture failed.\n'
    fi
    if ! cli 0 "live text" "$OUT/live.txt"; then
        show_crash_report busstop
    fi
    watch_check "live watch" 5 --watch
fi

# MARK: App launch

section "App launch: $APP_BINARY"
"$APP_BINARY" > "$OUT/app.stdout" 2> "$OUT/app.stderr" &
APP_PID=$!
sleep 8
if kill -0 "$APP_PID" 2> /dev/null; then
    pass "the app is still running 8 s after launch (pid $APP_PID)"
    kill -TERM "$APP_PID" 2> /dev/null
    wait "$APP_PID" 2> /dev/null
else
    APP_STATUS=0
    wait "$APP_PID" 2> /dev/null || APP_STATUS=$?
    failed "the app exited within 8 s of launch (exit status $APP_STATUS)"
    show_crash_report BusStop
fi
show "app stdout" "$OUT/app.stdout"
printf -- '--- app stderr (last 60 lines) ---\n'
tail -n 60 "$OUT/app.stderr"

# MARK: Summary

section "Summary"
if (( ${#FAILURES[@]} == 0 )); then
    printf 'All %d checks passed.\n' "$CHECKS"
    exit 0
fi
printf '%d of %d checks failed:\n' "${#FAILURES[@]}" "$CHECKS"
for failure in "${FAILURES[@]}"; do
    printf '  - %s\n' "$failure"
done
exit 1
