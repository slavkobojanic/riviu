# Riviu

A native macOS app for reviewing GitHub pull requests, with AI review, guided tours and code navigation.

Requires macOS 27.

## Install

Download `Riviu.dmg` from the [latest release](https://github.com/slavkobojanic/riviu/releases/latest), open it and
drag Riviu to Applications. Riviu updates itself.

## Build

Open `Riviu.xcodeproj` in Xcode 27 and run the Riviu scheme. Package tests: `swift test --package-path Packages/RiviuKit`.

## Releases

Every push to `main` runs `.github/workflows/release.yml`, which builds a DMG with `scripts/release.sh`. Once the
signing secrets are set with `scripts/setup-release.sh`, each build is signed with Developer ID, notarized and
published as a release, with the `appcast.xml` that Sparkle checks for updates.
