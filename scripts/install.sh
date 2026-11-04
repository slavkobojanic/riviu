#!/bin/bash
# Installs the latest Riviu release, or updates it:
#
#   curl -fsSL https://raw.githubusercontent.com/slavkobojanic/riviu/main/scripts/install.sh | bash
#
# It downloads Riviu.dmg from GitHub, checks Apple notarized it, and copies Riviu to /Applications (or
# ~/Applications if /Applications isn't writable). Then it opens Riviu, unless you pass --no-open.
# INSTALL_DIR=/some/folder installs somewhere else.
set -euo pipefail

REPOSITORY=slavkobojanic/riviu
DMG_URL="https://github.com/$REPOSITORY/releases/latest/download/Riviu.dmg"
BUNDLE_ID=email.slavko.riviu
OPENS=1
[[ "${1:-}" == "--no-open" ]] && OPENS=0

fail() { echo "error: $1" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "Riviu is a Mac app."
MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
(( MACOS_MAJOR >= 27 )) || fail "Riviu needs macOS 27 or later; this Mac has $(sw_vers -productVersion)."
[[ "$(uname -m)" == "arm64" ]] || fail "Riviu needs a Mac with Apple silicon."

if [[ -n "${INSTALL_DIR:-}" ]]; then
    DESTINATION=$INSTALL_DIR
elif [[ -w /Applications ]]; then
    DESTINATION=/Applications
else
    DESTINATION="$HOME/Applications"
fi
mkdir -p "$DESTINATION"

WORK=$(mktemp -d)
MOUNT="$WORK/mount"
cleanup() {
    hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "Downloading the latest Riviu..."
curl -fL --progress-bar -o "$WORK/Riviu.dmg" "$DMG_URL"

echo "Checking it's notarized by Apple..."
spctl --assess --type open --context context:primary-signature "$WORK/Riviu.dmg" 2>/dev/null \
    || fail "the download isn't signed and notarized; not installing it."

mkdir -p "$MOUNT"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$WORK/Riviu.dmg"
[[ -d "$MOUNT/Riviu.app" ]] || fail "Riviu.app isn't in the disk image."
VERSION=$(defaults read "$MOUNT/Riviu.app/Contents/Info.plist" CFBundleShortVersionString)

# Quit Riviu first if it's running, so the copy isn't replaced underneath it.
if pgrep -xq Riviu; then
    echo "Quitting Riviu..."
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" || true
    for _ in {1..20}; do pgrep -xq Riviu || break; sleep 0.5; done
    pgrep -xq Riviu && fail "Riviu is still running; quit it and run this again."
fi

echo "Installing Riviu $VERSION in $DESTINATION..."
rm -rf "$DESTINATION/Riviu.app"
ditto "$MOUNT/Riviu.app" "$DESTINATION/Riviu.app"
codesign --verify --deep --strict "$DESTINATION/Riviu.app" || fail "the installed copy failed its signature check."

echo "Riviu $VERSION is installed. It updates itself from now on."
if (( OPENS )); then
    open "$DESTINATION/Riviu.app"
fi
