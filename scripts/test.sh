#!/bin/sh
# Runs the Swift package tests on an iOS simulator.
#
# xcodebuild picks Yuki.xcodeproj over Package.swift when both are present, so the
# package is linked into a temporary directory on its own first.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ln -s "$ROOT/Package.swift" "$WORK/Package.swift"
ln -s "$ROOT/Sources" "$WORK/Sources"
ln -s "$ROOT/Tests" "$WORK/Tests"

cd "$WORK"
xcodebuild test -scheme Stoat-Package -destination "$DESTINATION" -derivedDataPath "$WORK/DerivedData" "$@"
