# Riviu

A native macOS app for reviewing GitHub pull requests, with AI review, guided tours and code navigation.

Requires macOS 27.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/slavkobojanic/riviu/main/scripts/install.sh | bash
```

This downloads the latest release, checks it's notarized, installs it in Applications and opens it. Run it again to
update, or let Riviu update itself. You can also download `Riviu.dmg` from the
[latest release](https://github.com/slavkobojanic/riviu/releases/latest) and drag Riviu to Applications.

## Build

Open `Riviu.xcodeproj` in Xcode 27 and run the Riviu scheme. Package tests: `swift test --package-path Packages/RiviuKit`.

## Releases

Every push to `main` runs `.github/workflows/release.yml`, which builds a DMG with `scripts/release.sh`. Once the
signing secrets are set with `scripts/setup-release.sh`, each build is signed with Developer ID, notarized and
published as a release, with the `appcast.xml` that Sparkle checks for updates.
