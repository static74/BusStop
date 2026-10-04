#!/usr/bin/env bash
#
# Checks a bundle made by scripts/build-app.sh: layout, Info.plist, signature
# and icon; the bundled CLI against every demo scenario and against this Mac;
# and that the app is still running a few seconds after launch.
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
            sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) printf 'smoke-test.sh: unknown option %s\n' "$argument" >&2; exit 2 ;;
        *) APP="$argument" ;;
    esac
done

CLI="$APP/Contents/Helpers/busstop"
APP_BINARY="$APP/Contents/MacOS/BusStop"
PLIST="$APP/Contents/Info.plist"
OUT="$ROOT/build/smoke"
DEMOS=(studioDesk travel dockStation unplugged)
CLI_TIME_LIMIT=120
FAILURES=()
CHECKS=0

for tool in plutil codesign lipo iconutil python3; do
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

# Prints the newest crash report for a process name written in the last
# ten minutes, if there is one.
show_crash_report() {
    local name="$1" report
    # ReportCrash writes the report a moment after the process dies.
    sleep 3
    report="$(find "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports \
        -maxdepth 1 -name "${name}*" -mmin -10 2> /dev/null | head -n 1)"
    if [[ -n "$report" ]]; then
        printf -- '--- crash report %s (first 120 lines) ---\n' "$report"
        head -n 120 "$report"
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

section "watch: busstop --watch --demo studioDesk (7 s, then Control-C)"
"$CLI" --watch --demo studioDesk > "$OUT/watch.txt" 2> "$OUT/watch.txt.stderr" &
WATCH_PID=$!
sleep 7
kill -INT "$WATCH_PID" 2> /dev/null
WATCH_STATUS=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$WATCH_PID" 2> /dev/null || break
    sleep 0.5
done
if kill -0 "$WATCH_PID" 2> /dev/null; then
    kill -KILL "$WATCH_PID" 2> /dev/null
    WATCH_STATUS=124
fi
wait "$WATCH_PID" 2> /dev/null || WATCH_STATUS=$?
show stdout "$OUT/watch.txt"
show stderr "$OUT/watch.txt.stderr"
if [[ "$WATCH_STATUS" == 0 ]]; then
    pass "--watch --demo stops cleanly on SIGINT"
else
    failed "--watch --demo ended with status $WATCH_STATUS after SIGINT"
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
