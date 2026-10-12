# Contributing to Bus Stop

Thank you for helping. Bus Stop is a small project with a few firm rules: it only reads hardware state, it stays local, and it never crashes on an IORegistry key it did not expect. This guide covers building, testing, bug reports and the two most common contributions: adding a Mac model and turning a capture into a test fixture.

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the code fits together. [docs/SPEC.md](docs/SPEC.md) is the full specification.

## Build and test

### On a Mac

You need Xcode 27 (Swift 6.4, macOS 27 SDK) or Xcode 26.6 (Swift 6.3). Both are tested in CI.

```sh
swift build                     # everything, debug
swift test                      # unit tests
swift run busstop --demo studioDesk
scripts/build-app.sh            # build/Bus Stop.app and build/BusStop.zip
scripts/smoke-test.sh           # checks the bundle, the CLI and that the app launches
open "build/Bus Stop.app"
```

Run the app from the bundle rather than with `swift run BusStopApp`: notifications, launch at login and the app icon need a real bundle with an `Info.plist`.

`scripts/install.sh` builds and installs into `/Applications` in one step. `scripts/build-app.sh` accepts `ARCHS=universal`, `VERSION`, `BUILD` and `CONFIGURATION=debug`; the comment at the top of the script describes them.

### On Linux, with Docker

`BusStopCore` (parsing, topology, labels, diagnostics, events, export and demo data) is pure Swift and builds on Linux, so you can work on it without a Mac. The macOS-only targets are left out of the package automatically.

```sh
docker run --rm -v "$PWD":/src -w /src swift:6.4-noble swift test
```

Add `--scratch-path /tmp/busstop-build` (with a matching volume) if you want the build products outside the repository.

### Continuous integration

Every push runs three jobs:

| Job | What it does |
|---|---|
| Core (Linux, Swift 6.4) | `swift test` in the `swift:6.4-noble` container |
| macOS 27 (Xcode 27) | build, test, `scripts/build-app.sh`, `scripts/smoke-test.sh` against demo data and the runner's own hardware, upload of `BusStop.zip` |
| macOS 26 (Xcode 26.6) | build, test, a universal `scripts/build-app.sh`, `scripts/smoke-test.sh --skip-live` |

The smoke test prints every command's output, so the job log shows what the CLI saw on the runner. Pull requests need all three jobs to pass.

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
5. Run `swift test` on Linux or macOS.

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
   Connector names in the file are `usb-c`, `magsafe`, `usb-a`, `hdmi`, `sd-card`, `ethernet` and `ac-power`. List the ports in physical order; Bus Stop shows them in that order.
4. Regenerate the Swift file:
   ```sh
   scripts/generate-port-catalog.py path/to/MacPortLocations.json
   ```
5. Run `swift test`, then check the labels with `busstop` on the Mac itself.

Please also send the new entry upstream to PortScope, so both projects benefit.

## Code style

- **Swift 6 language mode with complete concurrency checking.** Core types are `Sendable` values; UI code is `@MainActor`. No `@unchecked Sendable` without a comment explaining why it is safe.
- **`BusStopCore` stays Foundation-only** (no IOKit, AppKit, SwiftUI or CoreGraphics), so it builds and tests on Linux. Hardware access belongs in `BusStopKit`.
- **Read every IORegistry key defensively.** Keys can be missing or have an unexpected type on another Mac or macOS version, and keys starting with `Apple` are not API. Use the optional accessors on `PropertyBag` and `PlistValue`; never force-unwrap or force-cast registry data.
- **Avoid Foundation's type names** for new types: `Port`, `Process`, `Host`, `Thread`, `Timer` and the like collide on macOS (Foundation's `NSPort` is imported as `Port`).
- **Document types and non-obvious members** with `///` comments, including the reason behind anything surprising.
- **Plain, direct English** in comments and user-facing text. No emoji.
- Four-space indentation, lines up to about 120 characters, one type per file where practical.
- Guard APIs newer than macOS 26 with `#available(macOS 27, *)`, and code that needs the macOS 27 SDK with `#if compiler(>=6.4)`, so the project still builds with Xcode 26.6.

## Commits and pull requests

- Keep commits focused, with a short imperative subject line ("Decode USB4 v2 link widths") and a body that says why.
- Add or update tests for every behaviour change in `BusStopCore`.
- Update `CHANGELOG.md` under an "Unreleased" heading for user-visible changes.
- By contributing you agree that your work is released under the project's MIT License.

## Releases

Maintainers bump `BusStopVersion.string` in `Sources/BusStopCore/Version.swift`, add the version to `CHANGELOG.md`, and push a tag such as `v1.1.0`. The release workflow builds a universal app, runs the smoke test and publishes `BusStop.zip` with its SHA-256 checksum.
