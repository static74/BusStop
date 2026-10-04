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

## Phase 4: review

Independent reviewers check correctness (IOKit object lifetimes, concurrency, key handling), spec conformance, visual design and accessibility. Confirmed findings are fixed and re-verified in CI.

## Future work

- Widgets and App Intents (needs an Xcode project and a signing team).
- A Mac silhouette view with ports overlaid.
- History persisted across launches.
- Localisation.
- Notarized releases if a maintainer with a Developer ID adopts the project.
