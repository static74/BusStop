#!/usr/bin/env bash
#
# Prepares a release: sets BusStopVersion.string, turns CHANGELOG.md's
# [Unreleased] section into the new version, runs the tests, commits and tags
# vX.Y.Z on main. It never pushes. Pushing the tag starts release.yml, which
# builds the app, has Apple notarize it, and publishes the GitHub release with
# BusStop.dmg and its SHA-256.
#
# Usage: scripts/release.sh 1.1.0

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { printf 'release.sh: %s\n' "$*" >&2; exit 1; }

VERSION="${1:-}"
VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || fail "usage: scripts/release.sh X.Y.Z (semantic version)"
TAG="v$VERSION"
DATE="$(date +%Y-%m-%d)"
VERSION_FILE=Sources/BusStopCore/Version.swift

[[ "$(git branch --show-current)" == main ]] || fail "switch to main first"
[[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes; commit or stash them"
git fetch -q origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main differs from origin/main; pull first"
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "tag $TAG already exists"

# The [Unreleased] section must hold something to release.
awk '/^## \[Unreleased\]/ { on = 1; next } /^## / { on = 0 } on && /[^[:space:]]/ { found = 1 } END { exit !found }' CHANGELOG.md \
    || fail "CHANGELOG.md has nothing under [Unreleased]"

PREVIOUS="$(sed -nE 's|^\[Unreleased\]: .*/compare/(v[^ ]+)\.\.\.HEAD$|\1|p' CHANGELOG.md)"
[[ -n "$PREVIOUS" ]] || fail "could not read the previous version from the [Unreleased] link in CHANGELOG.md"
REPO_URL="https://github.com/static74/BusStop"

# Same pattern release.yml and build-app.sh read the version with.
sed -i '' -E "s/(static let string = \")[^\"]+(\")/\1$VERSION\2/" "$VERSION_FILE"
[[ "$(sed -nE 's/.*static let string = "([^"]+)".*/\1/p' "$VERSION_FILE" | head -n 1)" == "$VERSION" ]] \
    || fail "could not set the version in $VERSION_FILE"

awk -v v="$VERSION" -v d="$DATE" -v prev="$PREVIOUS" -v tag="$TAG" -v url="$REPO_URL" '
    /^## \[Unreleased\]/ { print; print ""; print "## [" v "] - " d; next }
    /^\[Unreleased\]: / { print "[Unreleased]: " url "/compare/" tag "...HEAD"; print "[" v "]: " url "/compare/" prev "..." tag; next }
    { print }
' CHANGELOG.md > CHANGELOG.md.tmp
mv CHANGELOG.md.tmp CHANGELOG.md

swift test

git commit -q -am "Release $VERSION"
git tag -a "$TAG" -m "Bus Stop $VERSION"

printf '\nCommitted "Release %s" and tagged %s. Check them with:\n  git show --stat HEAD\n' "$VERSION" "$TAG"
printf 'Publish (builds on the paid xcode-27 runner and creates the GitHub release;\nthen approve the run in Actions › Release):\n  git push origin main %s\n' "$TAG"
printf 'Undo instead:\n  git tag -d %s && git reset --hard HEAD~1\n' "$TAG"
