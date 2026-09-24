# Browser Selector

Browser Selector is a small, native macOS utility that asks which browser or
Firefox profile should open a link. It is deliberately limited to that job: no
rules, history, analytics, page lookups, native-app routing, or update checks.

It supports macOS 14 Sonoma and newer and is licensed under the
GNU General Public License, version 3 or (at your option) any later version
(`GPL-3.0-or-later`). See [LICENSE](LICENSE).

## Features

- Registers as a `http` and `https` handler.
- Finds installed browsers through macOS Launch Services.
- Presents each Firefox profile as a separate choice, including valid profile
  directories missing from `profiles.ini`.
- Opens a burst of pending links together in the selected target.
- Supports the mouse, arrow keys, Tab and Shift-Tab, Return, number keys 1–9,
  Escape, and click-away dismissal.
- Stores only display names, visibility, and ordering in local preferences.
- Performs no network requests of its own.

## Build

Xcode 16 or newer is required. Build and test the Swift package:

```sh
swift test
./scripts/build-app.sh debug native
./scripts/verify-app.sh
```

The app is written to `.build/Browser Selector.app`. For Launch Services
testing, install it in `/Applications`:

```sh
./scripts/install-local.sh
```

Opening Browser Selector directly shows Settings. Select **Set as Default
Browser** and approve the macOS confirmation. You can also choose it under
**System Settings → Desktop & Dock → Default web browser**.

## Firefox profiles

Browser Selector reads `~/Library/Application Support/Firefox/profiles.ini` and
scans the adjacent `Profiles` directory. Registered profiles use their Firefox
name; otherwise the directory name is shown. Rename entries in Settings without
changing the underlying Firefox profile.

Regular Firefox and Firefox Developer Edition profiles are matched to the installed
app recorded in each profile's `compatibility.ini`. This records the last app used,
not permanent ownership. Each matched profile uses that edition's icon and executable;
an edition's generic app entry appears only when it has no matched profiles.

Profiles with missing, conflicting, or stale app metadata are skipped with a notice
in Settings. Open the profile in its intended Firefox edition, then refresh the
browser list. Profile names are not used to guess the edition. Existing names,
visibility, and ordering are preserved when a Developer Edition profile is corrected.

Firefox is invoked directly with `-profile` and the absolute profile path.
Browser Selector never uses a shell to construct browser commands.

## Keyboard controls

| Key | Action |
| --- | --- |
| Up / Down | Move through choices |
| Tab / Shift-Tab | Move forward / backward |
| Return | Open in the focused choice |
| 1–9 | Open the numbered choice |
| Escape | Cancel |

## Install

Download the DMG from [GitHub Releases](https://github.com/heyztb/browser-selector/releases),
open it, and drag **Browser Selector** into **Applications**.

Releases are **ad hoc signed and not notarized by Apple**. On first launch, macOS
may block the app because it cannot verify the developer. Open **System Settings
→ Privacy & Security**, select **Open Anyway** for Browser Selector, and confirm.
This grants an exception for this app; disabling Gatekeeper is unnecessary.
See [Apple's instructions](https://support.apple.com/102445).

Once the app opens, select **Set as Default Browser** and approve the macOS
confirmation. Updates are manual: quit the app, then replace it in Applications
with the new version.

## Releases

Release builds include a [reproducibility check and independent comparison
procedure](REPRODUCIBILITY.md). Run `./scripts/check-reproducibility.sh` to compare
two clean universal builds. Each build records its environment in
`.build/build-info.txt`; signed containers themselves are not byte-reproducible.

Releases are packaged locally and uploaded manually.

## Privacy and scope

Browser Selector knows what browsers you have installed and can detect Firefox
profiles. It does not inspect pages, follow redirects, fetch favicons, retain
opened URLs, or send telemetry. 
