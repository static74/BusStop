# Bus Stop architecture

This document explains how Bus Stop is put together: the modules, how data flows from IOKit to the screen, which thread does what, and how to extend it. [SPEC.md](SPEC.md) is the full specification, including every IORegistry rule; this is the map.

## Principles

- **Read, never write.** Bus Stop only reads IORegistry properties, the power-source API and SMC read-only keys.
- **Capture, then interpret.** IOKit data is first copied into a plain, `Codable` snapshot of raw properties. Everything after that is pure Swift that runs the same on live data, demo data, saved captures and in tests on Linux.
- **Fail closed.** Keys can be missing or have the wrong type on another Mac or macOS version. Missing data means less detail, never a crash or a guess presented as fact.
- **Local only.** There is no network code anywhere.

## Modules

The project is a single Swift package (`Package.swift`, tools version 6.2, macOS 26 and later). Targets that need Apple frameworks are declared inside `#if os(macOS)`, so `swift build` and `swift test` on Linux build only the core and its tests.

| Target | Product | Platforms | Responsibility |
|---|---|---|---|
| `BusStopCore` | library | macOS, Linux | Foundation only. Raw capture model, output model, topology builder, port labels and catalogue, formatting, diagnostics, event diffing, power history, export, demo scenarios, version. |
| `BusStopKit` | library | macOS | IOKit capture (`RegistryCapture`), live monitoring (`LiveMonitor`), the SMC power channel reader, power-source and display readers. |
| `BusStopApp` | `BusStopApp` executable, renamed `BusStop` in the bundle | macOS | AppKit status item and popover, SwiftUI windows and settings, notifications, launch at login, export. |
| `BusStopCLI` | `busstop` executable | macOS | The command-line tool. |
| `BusStopCoreTests` | | macOS, Linux | Unit tests for the core, with fixtures. |
| `BusStopKitTests` | | macOS | Tests for the CF-to-`PlistValue` bridge, capture and monitor lifecycles. |

### Inside BusStopCore

| Folder | Contents |
|---|---|
| `Raw/` | `PlistValue` (a `Sendable`, `Codable` mirror of CoreFoundation property-list values), `PropertyBag` (forgiving typed accessors), `RawSnapshot` and its records (`RawNode`, `RawUSBDevice`, `RawThunderboltSwitch`, `SMCChannel`, `RawDisplay`). |
| `Model/` | The interpreted result: `HostSnapshot`, `PhysicalPort`, `DeviceNode`, `LinkInfo`, power types, `ConnectionEvent`, `Diagnostic`. |
| `Topology/` | `TopologyBuilder` and its parsers: ports, transports, USB device trees, Thunderbolt chains, link decoding, power, displays, device classification. |
| `Labels/` | `PortLabeler` (user name, catalogue, catalogue by rank, generic name) and the generated `PortLocationCatalog`. |
| `Diagnostics/` | `DiagnosticsEngine`, one function per rule in SPEC §5.4. |
| `Events/` | `SnapshotDiffer`, which turns two snapshots into `ConnectionEvent`s. |
| `History/` | `PowerHistory`, the in-memory samples behind the sparklines. |
| `Export/` | `Exporter`: JSON, Markdown, raw capture JSON, the CLI text tree, redaction. |
| `Demo/` | `DemoScenario`, which builds realistic `RawSnapshot`s. |
| `Formatting/` | `Format`: locale-independent units ("10 Gb/s", "4.5 W", "20 V × 4.7 A"). |
| `Version.swift` | `BusStopVersion`, the marketing version. |

## Data flow

```
  IOKit registry     IOPS power sources     SMC (read only)     CoreGraphics displays
        │                    │                     │                     │
        └────────────────────┴──────────┬──────────┴─────────────────────┘
                                        │  BusStopKit.RegistryCapture
                                        │  (LiveMonitor's serial queue)
                                        ▼
                                  RawSnapshot ◄──────── DemoScenario.raw(at:tick:)
                                        │      ◄──────── Exporter.decodeRaw (busstop --input,
                                        │                                  test fixtures)
                                        │  TopologyBuilder.build (pure)
                                        ▼
                                  HostSnapshot
                                        │  DiagnosticsEngine.evaluate (pure)
                                        ▼
                         HostSnapshot with diagnostics
                          │                    │
     SnapshotDiffer.events│                    │
     (previous, current)  ▼                    ▼
              [ConnectionEvent]        PortStore (@MainActor, @Observable)
               │          │                    │
     notifications   event log          SwiftUI views, status item text
                                               │
                                               ▼
                                  Exporter: JSON, Markdown, raw capture
```

The CLI runs the same pipeline: `busstop` captures once (or decodes a file, or asks a demo scenario), builds, evaluates and prints with `Exporter`. `busstop --watch` keeps the previous snapshot and prints the output of `SnapshotDiffer` for each new one.

### Why a raw snapshot

`RawSnapshot` keeps each IORegistry entry's properties as a `PropertyBag` (`[String: PlistValue]`) instead of a fixed schema:

- A new key never needs a capture format change; it is already in the bag.
- `busstop --raw` prints the snapshot as JSON, so a bug report from any Mac turns into a test fixture without the hardware.
- The topology rules are pure functions over plain data, testable on Linux.

`RawSnapshot.schemaVersion` exists for changes to the record structure itself. `Exporter.decodeRaw` fills in members that older captures lack.

## Threading

| Where | What runs there |
|---|---|
| `LiveMonitor`'s private serial queue | IOKit matching and interest notifications (`IONotificationPortSetDispatchQueue`), the power-source notification, the polling timer, the 250 ms debounce, and every capture. Captures never overlap. |
| Main thread / main actor | Display reconfiguration callbacks (they only post work to the monitor's queue), snapshot delivery, `PortStore`, all AppKit and SwiftUI code. The app target uses `.defaultIsolation(MainActor.self)`. |
| Anywhere | `BusStopCore` functions. Every core type is a `Sendable` value type and every core function is pure, so they need no isolation. |

`LiveMonitor.start(onSnapshot:)` takes a `@MainActor @Sendable` closure. The monitor captures on its queue and hops to the main actor to deliver. A delivery gate drops snapshots from a run that was stopped, so a late capture never reaches a store that has moved on (for example to demo mode).

Polling is adaptive: every 2 seconds while a popover or window is visible, every 10 seconds otherwise. Power figures change without IOKit notifications, so polling is what keeps the menu bar text current.

Safety rules for IOKit code (`BusStopKit`):

- Every `io_object_t` is released; wrappers own them.
- Volatile nodes (transport states, PD components, USB devices, Thunderbolt switches) are read one key at a time with `IORegistryEntryCreateCFProperty`, because bulk reads have been reported to crash while a device is being torn down. Long-lived port controllers are read in bulk.
- Iterators are checked with `IOIteratorIsValid` and walked again when invalidated.
- CoreFoundation values are bridged to `PlistValue` with type checks; unknown types are dropped.

## Adding a new IORegistry key

Say a port controller starts publishing a key you want to show.

1. **Check it is captured.** Run `busstop --raw` on a Mac that has the key and search the output.
   - Port controllers are read in bulk, so their keys arrive automatically unless they are on the noise list in `Sources/BusStopKit/RegistryKeys.swift`.
   - Volatile nodes are read key by key from the lists in `RegistryKeys.swift` (`usbTransport`, `displayPortTransport`, `cioTransport`, `feature`, `component`, `usbDevice`, `thunderboltSwitch`, `battery` and others). Add the key to the right list.
2. **Interpret it in the core.** Read it in the matching parser under `Sources/BusStopCore/Topology/` with the optional accessors (`bag.int("Key")`, `bag.string(["New Key", "Old Key"])`, `bag.bool("Key")`). Never force-unwrap: treat a missing key or a wrong type as "unknown".
3. **Carry it in the model** if the UI or exports need it. Add an optional or defaulted member to the model type in `Sources/BusStopCore/Model/`. Optional members keep older JSON exports decodable.
4. **Show it.** The inspector already lists every raw key. For a dedicated field, update the relevant view in `Sources/BusStopApp`, and `Exporter`'s Markdown and text output if it belongs there.
5. **Test it.** Add the key to a fixture in `Tests/BusStopCoreTests` and assert on the result, including a case where the key is missing or has the wrong type.

Keys whose names start with `Apple` are private to Apple and can change in any macOS update. Prefer the documented `IOPort` family keys where they exist, and keep a fallback.

## Adding a Mac model

Port locations come from PortScope's `MacPortLocations.json`, converted to `Sources/BusStopCore/Labels/PortLocationCatalog+Data.swift` by `scripts/generate-port-catalog.py`. Add the model to the JSON and regenerate; never edit the generated file. [CONTRIBUTING.md](../CONTRIBUTING.md#adding-a-mac-model-to-the-port-catalogue) has the steps.

Labels resolve in this order (SPEC §5.4):

1. the user's own name for the port,
2. a catalogue entry for this `hw.model` with the same connector and number,
3. a catalogue entry by rank among ports of the same connector (for non-contiguous numbering such as 1, 2, 4),
4. a generic name such as "USB-C 2".

A Mac missing from the catalogue still works; it just shows generic names until someone adds it.

## Testing

| Layer | How it is tested |
|---|---|
| `BusStopCore` | Unit tests with Swift Testing in `Tests/BusStopCoreTests`, on Linux and macOS. Fixtures are built from public IORegistry dumps (a macOS 26.3 MacBook `IOPort` plane, a macOS 27 `AppleSmartBattery`, Thunderbolt `system_profiler` captures) and from the demo scenarios. Covered: `PlistValue` coding, accessors, formatting, port parsing, label resolution, USB attribution order, hub roll-ups, Thunderbolt link decoding, charger and PDO parsing, per-port power joins, diagnostics, event diffing, export round trips, determinism and robustness against missing or wrongly typed keys. |
| `BusStopKit` | `Tests/BusStopKitTests` on macOS: the CF bridge, a live capture on the CI machine, rapid `LiveMonitor` start and stop cycles. |
| Bundle and CLI | `scripts/smoke-test.sh` after `scripts/build-app.sh`: bundle layout, the licence notices in the bundle and the zip, `Info.plist`, signature, icon, the CLI against every demo scenario (text, JSON, Markdown, raw capture and read-back), exit status 1 when standard output cannot be written, `--watch` and `--watch --json` printing events and stopping cleanly on Control-C, a live capture of the CI machine (a virtual Mac with few accessories), and the app still running 8 seconds after launch. It prints every output, so the CI log shows what the runner saw. |
| App UI | Built on both supported Xcode versions in CI; checked by hand with demo mode. |

CI runs on every push:

- **Core (Linux, Swift 6.4)**: `swift test` in `swift:6.4-noble`.
- **macOS 27 (Xcode 27)**: build, test, bundle, full smoke test, upload of `BusStop.zip`.
- **macOS 26 (Xcode 26.6)**: build, test, universal bundle, smoke test without the live checks.

Tags named `v*` run `.github/workflows/release.yml`, which builds a universal bundle stamped with the tag's version, runs the smoke test and publishes the zip with its SHA-256 checksum.

## Packaging

There is no Xcode project. `scripts/build-app.sh` builds the `BusStopApp` and `busstop` products in release mode and assembles the bundle by hand:

```
Bus Stop.app/
  Contents/
    Info.plist              Support/Info.plist with the version stamped in
    PkgInfo                 APPL????
    MacOS/BusStop           the app
    Helpers/busstop         the command-line tool
    Resources/AppIcon.icns  drawn by scripts/make-icon.py
    Resources/LICENSE.txt   Bus Stop's MIT License
    Resources/THIRD_PARTY_NOTICES.md
                            the MIT notices of PortScope, WhatPort and WhatCable
```

The CLI lives in `Contents/Helpers` because `Contents/MacOS/busstop` and `Contents/MacOS/BusStop` would be the same file on a case-insensitive volume. Both binaries are signed ad hoc with the hardened runtime (helper first, then the bundle). The app is not sandboxed: the App Sandbox blocks the SMC user client and some IOKit notifications Bus Stop relies on.

The MIT licences of the projects Bus Stop adapts code and data from require their notices in every copy, so the licence files are copied into the bundle before signing, and `build/BusStop.zip` holds them a second time next to `Bus Stop.app`. The smoke test checks both.

When `busstop` runs from inside the bundle (directly or through the symbolic link `scripts/install.sh --link-cli` makes), `--version` reads the bundle's `Info.plist`, so it reports the same version and build as the app.
