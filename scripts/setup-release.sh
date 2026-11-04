#!/bin/bash
# Sets up signed releases, once. Run it yourself in Terminal: it asks for your passwords and stores them as
# GitHub Actions secrets with `gh secret set`, so they never land in a file or in the repository.
#
#   scripts/setup-release.sh
#
# It sets up:
#   1. Sparkle's signing key. The private half goes to GitHub; the public half goes into Config/Info.plist.
#   2. Your Developer ID Application certificate, exported as a .p12.
#   3. Your Apple ID, team ID and an app-specific password, for notarizing.
set -euo pipefail
cd "$(dirname "$0")/.."

REPOSITORY=slavkobojanic/riviu
pause() { read -r -p "$1 Press Return when done. " _; }

gh auth status > /dev/null || { echo "Sign in to GitHub first: gh auth login"; exit 1; }

echo
echo "== 1. Sparkle's signing key"
GENERATE_KEYS=$(find ~/Library/Developer/Xcode/DerivedData -path "*artifacts/sparkle/Sparkle/bin/generate_keys" 2>/dev/null | head -1)
if [[ -z "$GENERATE_KEYS" ]]; then
    echo "Fetching Sparkle..."
    xcodebuild -resolvePackageDependencies -project Riviu.xcodeproj -scheme Riviu > /dev/null
    GENERATE_KEYS=$(find ~/Library/Developer/Xcode/DerivedData -path "*artifacts/sparkle/Sparkle/bin/generate_keys" | head -1)
fi
# Makes a key in your login keychain, or prints the one already there.
PUBLIC_KEY=$("$GENERATE_KEYS" | sed -n 's:.*<string>\(.*\)</string>.*:\1:p' | head -1)
if [[ -z "$PUBLIC_KEY" ]]; then
    PUBLIC_KEY=$("$GENERATE_KEYS" -p)
fi
plutil -replace SUPublicEDKey -string "$PUBLIC_KEY" Config/Info.plist
echo "Public key written to Config/Info.plist: $PUBLIC_KEY"
KEY_FILE=$(mktemp)
rm "$KEY_FILE"
"$GENERATE_KEYS" -x "$KEY_FILE"
gh secret set SPARKLE_PRIVATE_KEY --repo "$REPOSITORY" < "$KEY_FILE"
rm "$KEY_FILE"
echo "Keep the key in your login keychain: every future update must be signed with it."

echo
echo "== 2. Developer ID certificate"
echo "In Xcode: Settings > Accounts > your Apple ID > Manage Certificates… > + > Developer ID Application."
echo "Then in Keychain Access, find \"Developer ID Application: …\" under My Certificates,"
echo "right-click > Export…, save it as a .p12 and choose a password."
pause "Export the .p12."
read -r -p "Path to the .p12: " P12_PATH
P12_PATH="${P12_PATH/#\~/$HOME}"
base64 -i "$P12_PATH" | gh secret set DEVELOPER_ID_P12_BASE64 --repo "$REPOSITORY"
echo "Now the .p12's password:"
gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$REPOSITORY"
echo "You can delete $P12_PATH now; the certificate stays in your keychain."

echo
echo "== 3. Notarizing"
read -r -p "Apple ID of the developer account [slavkobojanic@icloud.com]: " APPLE_ID
APPLE_ID=${APPLE_ID:-slavkobojanic@icloud.com}
gh secret set APPLE_ID --repo "$REPOSITORY" --body "$APPLE_ID"
echo "Team ID: developer.apple.com/account > Membership details."
read -r -p "Team ID [6ZG9U52KS9]: " TEAM_ID
TEAM_ID=${TEAM_ID:-6ZG9U52KS9}
gh secret set APPLE_TEAM_ID --repo "$REPOSITORY" --body "$TEAM_ID"
echo "Make an app-specific password at account.apple.com > Sign-In and Security > App-Specific Passwords."
pause "Make the password."
echo "Now paste it:"
gh secret set APPLE_APP_PASSWORD --repo "$REPOSITORY"

echo
echo "All set. Commit Config/Info.plist (it now holds the public key) and push; the next push to main"
echo "publishes a signed, notarized release."
