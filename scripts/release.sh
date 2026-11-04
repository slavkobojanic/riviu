#!/bin/bash
# Builds build/Riviu.dmg from the current checkout.
#
# With the signing secrets set (see scripts/setup-release.sh) it signs Riviu with Developer ID, has Apple notarize
# it, signs the DMG for Sparkle and writes build/appcast.xml, the announcement Sparkle reads. Without them it makes
# an unsigned DMG, which is only good for trying a build on your own Mac.
#
# Environment:
#   BUILD_NUMBER                  Increases with every release; Sparkle compares it. The version is 1.0.BUILD_NUMBER.
#   REPOSITORY                    owner/name on GitHub, for download links. Defaults to slavkobojanic/riviu.
#   RELEASE_NOTES                 Shown in Sparkle's update window.
#   DEVELOPER_ID_P12_BASE64       The Developer ID Application certificate and key, exported as .p12, base64.
#   DEVELOPER_ID_P12_PASSWORD     The .p12's password.
#   APPLE_ID, APPLE_TEAM_ID       The Apple Developer account, for notarizing.
#   APPLE_APP_PASSWORD            An app-specific password for that Apple ID.
#   SPARKLE_PRIVATE_KEY           From `generate_keys -x`; signs updates.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_NUMBER=${BUILD_NUMBER:-1}
VERSION="1.0.$BUILD_NUMBER"
REPOSITORY=${REPOSITORY:-slavkobojanic/riviu}
OUT=build
DERIVED="$OUT/DerivedData"
rm -rf "$OUT/Riviu.xcarchive" "$OUT/export" "$OUT/dmg" "$OUT/Riviu.dmg" "$OUT/appcast.xml"
mkdir -p "$OUT"

if [[ -n "${DEVELOPER_ID_P12_BASE64:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    SIGNED=1
else
    SIGNED=0
    echo "Signing secrets aren't set, so this DMG is unsigned and won't be published."
fi
# Lets the workflow know whether to publish.
[[ -n "${GITHUB_ENV:-}" ]] && echo "SIGNED=$SIGNED" >> "$GITHUB_ENV"

# On CI, put the certificate in a keychain of its own for this run.
if [[ $SIGNED == 1 && -n "${CI:-}" ]]; then
    KEYCHAIN="$RUNNER_TEMP/riviu-signing.keychain-db"
    KEYCHAIN_PASSWORD=$(uuidgen)
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    echo "$DEVELOPER_ID_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
    security import "$RUNNER_TEMP/certificate.p12" -k "$KEYCHAIN" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
    rm "$RUNNER_TEMP/certificate.p12"
    security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
    security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
fi

echo "Building Riviu $VERSION"
if [[ $SIGNED == 1 ]]; then
    SIGNING=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Developer ID Application" "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
             "OTHER_CODE_SIGN_FLAGS=--timestamp")
else
    SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi
xcodebuild archive -quiet \
    -project Riviu.xcodeproj -scheme Riviu -configuration Release -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED" -archivePath "$OUT/Riviu.xcarchive" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${SIGNING[@]}"

if [[ $SIGNED == 1 ]]; then
    # Exporting re-signs Sparkle's helpers with our certificate too.
    cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
    <key>teamID</key><string>$APPLE_TEAM_ID</string>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive -quiet -archivePath "$OUT/Riviu.xcarchive" \
        -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export"
else
    mkdir -p "$OUT/export"
    cp -R "$OUT/Riviu.xcarchive/Products/Applications/Riviu.app" "$OUT/export/"
fi

echo "Making the DMG"
mkdir -p "$OUT/dmg"
cp -R "$OUT/export/Riviu.app" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -quiet -volname Riviu -srcfolder "$OUT/dmg" -ov -format UDZO "$OUT/Riviu.dmg"

if [[ $SIGNED == 0 ]]; then
    echo "Done: $OUT/Riviu.dmg (unsigned)"
    exit 0
fi

codesign --sign "Developer ID Application" --timestamp "$OUT/Riviu.dmg"

echo "Notarizing (this takes a few minutes)"
xcrun notarytool submit "$OUT/Riviu.dmg" --wait \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
xcrun stapler staple "$OUT/Riviu.dmg"
spctl --assess --type open --context context:primary-signature --verbose "$OUT/Riviu.dmg"

echo "Signing the update for Sparkle"
SIGN_UPDATE="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
KEY_FILE=$(mktemp)
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
# Prints: sparkle:edSignature="…" length="…"
SPARKLE_ATTRIBUTES=$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$OUT/Riviu.dmg")
rm "$KEY_FILE"

cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Riviu</title>
        <item>
            <title>Riviu $VERSION</title>
            <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
            <description><![CDATA[<p>${RELEASE_NOTES:-}</p>]]></description>
            <link>https://github.com/$REPOSITORY/releases/tag/v$VERSION</link>
            <enclosure url="https://github.com/$REPOSITORY/releases/download/v$VERSION/Riviu.dmg"
                       $SPARKLE_ATTRIBUTES type="application/octet-stream"/>
        </item>
    </channel>
</rss>
XML

echo "Done: $OUT/Riviu.dmg and $OUT/appcast.xml"
