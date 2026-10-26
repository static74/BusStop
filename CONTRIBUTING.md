# Contributing to Bus Stop

Thank you for helping. Bus Stop is a small project with a few firm rules: it only reads hardware state, it stays local, and it never crashes on an IORegistry key it did not expect. This guide covers building, testing, bug reports and the two most common contributions: adding a Mac model and turning a capture into a test fixture.

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the code fits together. [docs/SPEC.md](docs/SPEC.md) is the full specification.

## Build and test

Bus Stop builds and runs on macOS only. You need Xcode 27 (Swift 6.4, macOS 27 SDK) or Xcode 26.6 (Swift 6.3). CI tests Xcode 26.6 on every pull request, and Xcode 27 when started by hand and on every release.

```sh
swift build                     # everything, debug
swift test                      # unit tests
swift run busstop --demo studioDesk
scripts/build-app.sh            # build/Bus Stop.app and build/BusStop.zip
scripts/make-dmg.sh             # build/BusStop.dmg from the app
scripts/smoke-test.sh           # checks the bundle, the CLI and that the app launches
open "build/Bus Stop.app"
```

Run the app from the bundle rather than with `swift run BusStopApp`: notifications, launch at login and the app icon need a real bundle with an `Info.plist`.

`scripts/install.sh` builds and installs into `/Applications` in one step. `scripts/build-app.sh` accepts `ARCHS=universal`, `VERSION`, `BUILD` and `CONFIGURATION=debug`; the comment at the top of the script describes them.

### Testing widgets

The desktop widgets are a separate target, `BusStopWidgets`, which `scripts/build-app.sh` wraps into `Contents/PlugIns/BusStopWidgets.appex`. The views they share with the app are in the `BusStopUI` library. The extension never reads hardware: it shows the payload the app writes into their shared App Group container, so the app must be running for live data.

macOS shows widgets only from a build signed by a team and installed in `/Applications`. An ad hoc build bundles the extension and passes every test, but no widget appears in the gallery; `swift test` renders the widget views off screen either way. To see them, sign with an Apple Development or Developer ID certificate:

```sh
SIGN_IDENTITY=<Apple Development or Developer ID identity or SHA-1 hash> scripts/build-app.sh
osascript -e 'quit app "Bus Stop"'
ditto "build/Bus Stop.app" "/Applications/Bus Stop.app"
open "/Applications/Bus Stop.app"
```

Then right-click the desktop › Edit Widgets › search "Bus Stop". If two identities share a name, pass the SHA-1 hash from `security find-identity -v -p codesigning`. An Apple Development certificate needs Apple's WWDR G3 intermediate in the keychain. To debug: `pluginkit -m -p com.apple.widgetkit-extension -v`, and chronod's messages through `/usr/bin/log` (in zsh, a bare `log` is a shell builtin).

### Continuous integration

CI runs on every pull request, and again on each push to it. Plain branch pushes and merges to `main` run nothing.

| Job | When | What it does |
|---|---|---|
| macOS 26 (Xcode 26.6) | every pull request | build, test, a universal `scripts/build-app.sh`, `scripts/smoke-test.sh --skip-live` |
| macOS 27 (Xcode 27) | only when started by hand (Actions › CI › Run workflow), because its runner is paid | build, test, `scripts/build-app.sh`, `scripts/smoke-test.sh` against demo data and the runner's own hardware, upload of `BusStop.zip` |

A separate Screenshots workflow (Actions › Screenshots › Run workflow) launches the real app in demo mode on the paid macOS 27 runner, captures the popover, the topology window and every settings pane, and publishes the images to the `screenshots` branch, where the README links them. It is started by hand, so run it before a release when the UI has changed, or the README's images will trail the app.

The smoke test prints every command's output, so the job log shows what the CLI saw on the runner. Pull requests need the macOS 26 job to pass. Releases run the full test and smoke test on Xcode 27 before they publish.

## Reporting a bug

The most useful bug report includes a raw capture from the Mac that shows the problem:

```sh
"/Applications/Bus Stop.app/Contents/Helpers/busstop" --raw > capture.json
```

(or `busstop --raw > capture.json` if you linked the command with `scripts/install.sh --link-cli`). You can also use **Export › Raw Capture for Bug Reports** in the app.

The capture is a JSON copy of the IORegistry properties Bus Stop reads. Serial numbers and the computer name are redacted by default; look through the file before attaching it anyway. Please also say:

- which Mac it is (Apple menu › About This Mac) and the macOS version,
- what is plugged into which physical port,
- what Bus Stop shows and what you expected.

To see how a capture is interpreted without the hardware, run `busstop --input capture.json` (add `--json` or `--markdown` for other formats).

## Turning a capture into a test fixture

Every topology bug should end up as a test, so it stays fixed.

1. Make the capture as small as the bug allows. It is plain JSON: `portNodes`, `usbDevices`, `thunderboltSwitches`, `battery`, `adapter`, `smcChannels` and `displays`. Remove records that have nothing to do with the bug, and keep the registry IDs and `parentID` links of the records you keep consistent.
2. Check that it still reproduces the problem: `swift run busstop --input capture.json`.
3. Add it to `Tests/BusStopCoreTests`. Small captures can go straight into a Swift raw string literal (`#"""…"""#`) next to the test. Larger ones go in a `.json` file under `Tests/BusStopCoreTests/Fixtures/`, declared in `Package.swift` with `resources: [.copy("Fixtures/<folder>")]` on the test target and loaded with `Bundle.module`.
4. Write the test: decode with `Exporter.decodeRaw`, build with `TopologyBuilder.build`, and assert on what the bug was about (a device's port, a link speed, a power figure). Tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
5. Run `swift test`.

Fixtures must not contain real serial numbers. Captures made with the default settings are already redacted.

## Adding a Mac model to the port catalogue

Port names such as "Left Front" come from a catalogue of physical port locations per `hw.model`, generated from [PortScope](https://github.com/azenla/portscope)'s `MacPortLocations.json` (MIT License, © 2026 Alex Zenla). The generated file is `Sources/BusStopCore/Labels/PortLocationCatalog+Data.swift`; do not edit it by hand.

1. Find the model identifier: `sysctl hw.model` (for example `Mac16,6`).
2. Find each port's number. `busstop --json` lists every port with its `number` and `registryName` (for example `Port-USB-C@2`). Plug a device into each physical port in turn and note which number shows it.
3. Add the model to `MacPortLocations.json`, in PortScope's format. This is the existing entry for the 14-inch MacBook Pro with M4 Max:
   ```json
   "Mac16,6": {
     "marketing_name": "MacBook Pro (14-inch, 2024, M4 Max)",
     "chassis": "MacBook Pro 14″ Pro chassis",
     "ports": [
       { "connector": "magsafe", "port_number": 1, "location": "Left Rear", "capability": "MagSafe 3" },
       { "connector": "usb-c", "port_number": 1, "location": "Left Center", "capability": "Thunderbolt 5" },
       { "connector": "usb-c", "port_number": 2, "location": "Left Front", "capability": "Thunderbolt 5" },
       { "connector": "sd-card", "port_number": 1, "location": "Right Front", "capability": "SDXC UHS-II" },
       { "connector": "hdmi", "port_number": 1, "location": "Right Rear", "capability": "HDMI 2.1" },
       { "connector": "usb-c", "port_number": 3, "location": "Right Center", "capability": "Thunderbolt 5" }
     ]
   }
   ```
   Connector names in the file are `usb-c`, `magsafe`, `usb-a`, `hdmi`, `sd-card`, `ethernet` and `ac-power`. List the ports in physical order; Bus Stop shows them in that order. Write locations in the existing forms ("Left Rear", "Right Center", "Rear (left-center)", "Top/Front (left)"), because Bus Stop reads them to place the ports on the Mac's outline; `ChassisLayoutTests.everyCatalogueLocationParses` checks every row.
4. Regenerate the Swift file:
   ```sh
   scripts/generate-port-catalog.py path/to/MacPortLocations.json
   ```
5. Run `swift test`, then check the labels with `busstop` on the Mac itself.

Please also send the new entry upstream to PortScope, so both projects benefit.

## Code style

- **Swift 6 language mode with complete concurrency checking.** Core types are `Sendable` values; UI code is `@MainActor`. No `@unchecked Sendable` without a comment explaining why it is safe.
- **`BusStopCore` has no hardware access and no UI** (no IOKit, AppKit or SwiftUI), so its tests run on saved captures and demo data. Hardware access belongs in `BusStopKit`, and UI in the app, or in `BusStopUI` when the widget extension (`BusStopWidgets`) draws it too. `BusStopUI` views take plain values, not the app's store, and the extension never reads hardware.
- **Read every IORegistry key defensively.** Keys can be missing or have an unexpected type on another Mac or macOS version, and keys starting with `Apple` are not API. Use the optional accessors on `PropertyBag` and `PlistValue`; never force-unwrap or force-cast registry data.
- **Avoid Foundation's type names** for new types: `Port`, `Process`, `Host`, `Thread`, `Timer` and the like collide on macOS (Foundation's `NSPort` is imported as `Port`).
- **Document types and non-obvious members** with `///` comments, including the reason behind anything surprising.
- **Plain, direct English** in comments and user-facing text. No emoji.
- **Colours come from the `Lagoon` tokens in `Theme.swift`.** Do not write `Color(hex:)`, `.white` or `.black` in a view; add a token instead (the Appearance preview wallpaper and the status icon's template ink are the only exceptions). New tokens use `Lagoon.themed(dark, light)`, and both values must meet the contrast targets in `ThemeContrastTests`. A glow or blur goes through `lagoonGlow`, which draws nothing in Light, and softened text goes through `Lagoon.textFade`.
- Four-space indentation, lines up to about 120 characters, one type per file where practical.
- Guard APIs newer than macOS 26 with `#available(macOS 27, *)`, and code that needs the macOS 27 SDK with `#if compiler(>=6.4)`, so the project still builds with Xcode 26.6.

## Commits and pull requests

- Keep commits focused, with a short imperative subject line ("Decode USB4 v2 link widths") and a body that says why.
- Add or update tests for every behaviour change in `BusStopCore`.
- Update `CHANGELOG.md` under an "Unreleased" heading for user-visible changes.
- By contributing you agree that your work is released under the project's MIT License.

## Releases

Maintainers release from an up-to-date `main` with `scripts/release.sh 1.1.0`. The script sets `BusStopVersion.string`, turns the `[Unreleased]` section of `CHANGELOG.md` into `[1.1.0]`, runs `swift test`, commits and tags `v1.1.0`, and prints the push command. Pushing the tag starts the release workflow, which fails if the tag and `BusStopVersion.string` differ, then builds a universal app, signs it with the Developer ID, has Apple notarize it, packs it into a disk image that is signed and notarized too, runs the smoke test and publishes `BusStop.dmg` with its SHA-256 checksum. The certificate and notary credentials are secrets of the `release` environment, listed at the top of `.github/workflows/release.yml`, and each run waits for a maintainer to approve it there; without them the release is signed ad hoc and the workflow warns. To check the secrets without releasing, start the Release workflow by hand from the Actions tab: it does everything but publish and uploads the disk image as a workflow artifact. Choose the number by [Semantic Versioning](https://semver.org/): a fix raises the patch number, a new feature the minor number, and a change that breaks the command-line output or the saved history the major number. The build number (`CFBundleVersion`) is the commit count and needs no bump.

The first release with the desktop widgets needs one check by hand before its tag: start the Release workflow from the Actions tab on `main`, install the notarized app from its artifact on a Mac with no development certificates, on macOS 26 and on 27, and confirm that notarization accepted the app and extension with the App Group entitlement, that the widgets appear in Edit Widgets and show live data, that no "access data from other apps" prompt appears, and that they read well in full colour, monochrome, tinted and clear styles. Remove this paragraph once that release is out.
