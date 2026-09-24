#!/bin/sh
# Builds an unsigned Yuki.ipa for AltStore or SideStore, which sign it with the user's Apple ID.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/build}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$ROOT"
xcodebuild archive \
    -project Yuki.xcodeproj \
    -scheme Yuki \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$WORK/Yuki.xcarchive" \
    -derivedDataPath "$WORK/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    -quiet

mkdir -p "$WORK/Payload" "$OUT"
cp -R "$WORK/Yuki.xcarchive/Products/Applications/Yuki.app" "$WORK/Payload/"
rm -f "$OUT/Yuki.ipa"
(cd "$WORK" && zip -qry "$OUT/Yuki.ipa" Payload)
echo "$OUT/Yuki.ipa ($(du -h "$OUT/Yuki.ipa" | cut -f1))"
