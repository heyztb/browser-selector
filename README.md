# Browser Selector

Browser Selector is a small, native macOS utility that asks which browser or Firefox profile should open a link. It is deliberately limited to that job: no rules, history, analytics, page lookups, native-app routing, or update checks.

It supports macOS 14 Sonoma and newer and is licensed under the MIT License.

## Features

- Registers as an `http` and `https` handler.
- Finds installed browsers through macOS Launch Services.
- Presents each Firefox profile as a separate choice, including valid profile directories missing from `profiles.ini`.
- Opens a burst of pending links together in the selected target.
- Supports the mouse, arrow keys, Tab and Shift-Tab, Return, number keys 1–9, Escape, and click-away dismissal.
- Stores only display names, visibility, and ordering in local preferences.
- Performs no network requests of its own.

## Build

Xcode 16 or newer is required. Build and test the Swift package:

```sh
swift test
./scripts/build-app.sh debug native
./scripts/verify-app.sh
```

The app is written to `.build/Browser Selector.app`. For Launch Services testing, install it in `/Applications`:

```sh
./scripts/install-local.sh
```

Opening Browser Selector directly shows Settings. Select **Set as Default Browser** and approve the macOS confirmation. You can also choose it under **System Settings → Desktop & Dock → Default web browser**.

## Firefox profiles

Browser Selector reads `~/Library/Application Support/Firefox/profiles.ini` and scans the adjacent `Profiles` directory. Registered profiles use their Firefox name; otherwise the directory name is shown. Rename entries in Settings without changing the underlying Firefox profile.

Firefox is invoked directly with `-profile` and the absolute profile path. Browser Selector never uses a shell to construct browser commands.

## Keyboard controls

| Key | Action |
| --- | --- |
| Up / Down | Move through choices |
| Tab / Shift-Tab | Move forward / backward |
| Return | Open in the focused choice |
| 1–9 | Open the numbered choice |
| Escape | Cancel |

## Release signing

Tags matching `vMAJOR.MINOR.PATCH` trigger the release workflow. It tests the package, builds a universal app, signs it with hardened runtime, notarizes and staples it, and publishes a ZIP plus SHA-256 checksum.

Configure these GitHub Actions secrets:

- `APPLE_DEVELOPER_ID_P12`: base64-encoded Developer ID Application certificate and private key.
- `APPLE_DEVELOPER_ID_PASSWORD`: password for the P12.
- `APPLE_KEYCHAIN_PASSWORD`: temporary CI keychain password.
- `APPLE_SIGNING_IDENTITY`: full Developer ID Application identity.
- `APPLE_NOTARY_KEY_P8`: base64-encoded App Store Connect API private key.
- `APPLE_NOTARY_KEY_ID` and `APPLE_NOTARY_ISSUER_ID`: corresponding API key identifiers.

Browser Selector has no automatic updater. Users install new versions from GitHub Releases.

## Privacy and scope

Browser Selector examines installed application bundles and Firefox's local profile index. It does not inspect pages, follow redirects, fetch favicons, retain opened URLs, or send telemetry. Tor Browser is treated as an ordinary browser application; its configuration is neither read nor changed.
