#!/bin/sh
# Builds Yuki and installs it on a connected iPhone.
#
# Uses the first team Xcode is signed in to (a free Personal Team works; its installs stop
# opening after 7 days, so rerun this weekly). Override with TEAM=<team id> or DEVICE=<udid>.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Yuki-Device}"

TEAM="${TEAM:-$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | sed -n 's/.*teamID = \([A-Z0-9]*\);.*/\1/p' | head -n 1)}"
if [ -z "$TEAM" ]; then
    echo "No development team found. Sign in to Xcode (Settings > Accounts) or set TEAM." >&2
    exit 1
fi

if [ -z "${DEVICE:-}" ]; then
    JSON="$(mktemp)"
    trap 'rm -f "$JSON"' EXIT
    xcrun devicectl list devices --json-output "$JSON" >/dev/null
    DEVICE="$(python3 -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
paired = [d for d in devices if d["hardwareProperties"].get("deviceType") == "iPhone"
          and d["connectionProperties"].get("pairingState") == "paired"]
print(paired[0]["identifier"] if paired else "")
' "$JSON")"
fi
if [ -z "$DEVICE" ]; then
    echo "No paired iPhone found. Connect and unlock it, then try again." >&2
    exit 1
fi

cd "$ROOT"
xcodebuild build \
    -project Yuki.xcodeproj \
    -scheme Yuki \
    -configuration Release \
    -destination "id=$DEVICE" \
    -derivedDataPath "$WORK" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    -quiet

xcrun devicectl device install app --device "$DEVICE" "$WORK/Build/Products/Release-iphoneos/Yuki.app"

if ! xcrun devicectl device process launch --device "$DEVICE" chat.yuki.ios >/dev/null 2>&1; then
    echo "Installed. If Yuki won't open, trust the developer on the iPhone:" >&2
    echo "Settings > General > VPN & Device Management > Apple Development." >&2
fi
