# Bus Stop: implementation plan

This plan was executed in October 2026. It records how the work was split so contributors can see which part of the code owns what.

## Phase 0: research (done)

- Product research on ViewPorts (public search snippets) and its open-source peers (WhatPort, WhatCable, PortScope, Manifold).
- IOKit research: port controllers (`AppleHPMInterface*`, `AppleTCController*`, bare `IOPort`), the `IOPort` registry plane, transport states, USB device keys, Thunderbolt switch/port keys, power telemetry, SMC power channels, notifications.
- Platform research: macOS 27 "Golden Gate", Xcode 27 / Swift 6.4, Liquid Glass APIs, GitHub `xcode-27` runner.

## Phase 1: contracts (done)

Written first so parallel work could not drift:

| File | Purpose |
|---|---|
| `Package.swift` | Targets; macOS-only targets behind `#if os(macOS)` so Linux can build and test the core |
| `Sources/BusStopCore/Raw/*` | `PlistValue`, `PropertyBag`, `RawSnapshot` and friends |
| `Sources/BusStopCore/Model/*` | `HostSnapshot`, `Port`, `DeviceNode`, `LinkInfo`, power types, events, diagnostics |
| `Sources/BusStopCore/Formatting/Format.swift` | Units |
| `Sources/BusStopKit/{RegistryCapture,LiveMonitor}.swift` | Capture API |
| `Sources/BusStopApp/Theme/*` | Lagoon tokens and shared SwiftUI components |
| `Sources/BusStopApp/Model/*` | `AppSettings`, `PortStore` |

## Phase 2: parallel implementation

Each work package was built on its own branch against the contracts, then merged.

| Package | Owns | Verified by |
|---|---|---|
| Core topology | `Sources/BusStopCore/Topology/*`, topology tests and fixtures | `swift test` on Linux |
| Core support | `Labels/*` (catalogue generated from PortScope data), `Diagnostics/*`, `Events/*`, `Export/*`, tests | `swift test` on Linux |
| Capture | `Sources/BusStopKit/*` | macOS CI build, CLI smoke test on the runner |
| App shell | `main.swift`, `App/*`, `Popover/*` | macOS CI build |
| Windows | `Window/*`, `Settings/*`, `About/*` | macOS CI build |
| Tooling | `Sources/BusStopCLI/*`, `scripts/*`, `Support/*`, CI, README, notices | CI |
| Demo data | `Sources/BusStopCore/Demo/*`, scenario tests | `swift test` on Linux |

## Phase 3: integration

1. Merge all packages.
2. Linux: `swift test` for the core.
3. macOS 27 CI: build, test, assemble the `.app`, run the CLI against demo data and the live runner.
4. macOS 26 CI: build and test with Xcode 26.6.

## Phase 4: review (done)

Eight independent reviewers covered IOKit capture, topology, support modules, the app shell, the windows, tooling, privacy/security and spec/UX (using screenshots of the running app from CI). Every finding was checked by one or two adversarial verifiers before it counted: 69 findings were reported, 66 confirmed, 3 refuted. The confirmed ones (3 high, 27 medium, 36 low, with overlaps between reviewers) were fixed in five packages (core, capture, app shell, windows, tooling), each on its own branch and green in CI before merging. Core tests grew from 219 to 263 and the macOS smoke test from 73 to 88 checks.

## Visual verification

The `Screenshots` workflow launches the real app on the macOS 27 runner at 1920 × 1080 with a dark system appearance, in every demo scenario plus live data, and publishes the images to the `screenshots` branch. The popover, topology window, settings panes and About window were reviewed from these images and polished (name wrapping, contrast, fit-to-window graph, window placement).

## Future work

- Widgets and App Intents (needs an Xcode project and a signing team).
- A Mac silhouette view with ports overlaid.
- History persisted across launches.
- Localisation.
- Notarized releases if a maintainer with a Developer ID adopts the project.
