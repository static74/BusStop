# Changelog

All notable changes to Bus Stop are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Topology map: drag to pan like a web map, and zoom around the pointer with a mouse scroll wheel. Trackpads still pan with two fingers and zoom with a pinch. Zoom now runs from 25 % to 200 %.
- Click a link in the map to inspect it: the negotiated speed, the power across it and, for the cable in one of the Mac's own ports, what its e-marker chip says it is rated for (speed, power, current, voltage, EPR), with a note when the cable or the device is what limits the link. Hovering a link highlights it.
- A Cables section in the window's sidebar lists every link below each port as "parent → child" with its speed. Clicking one opens it in the inspector and moves the map to it.
- A Data / Power toggle on the map. In Power mode links are coloured from grey through deep red, orange and amber to gold as watts rise, chips show watts (a port's measured reading, or "≤" a USB power budget), and pulses run the way the power flows, such as from a dock into the Mac.
- Port and device inspectors link to the cable and link page; the port's cable section shows rated power, maximum voltage and EPR support.

- `docs/ROADMAP.md` with the planned features after 1.0.

### Changed

- Links that run together in the map no longer look brighter where they overlap, and links leaving one card start from separate points instead of a single one.
- A monitor that reaches a port through a Thunderbolt dock is drawn under the dock in the map.

### Fixed

- Devices behind a Thunderbolt dock are shown under the dock even when no USB device carries the dock's name (docks use generic hub chips such as "USB3.1 Gen2 Hub"). The cable's own USB 2 half of a dock's hub goes under the dock too.
- A USB 3 hub's USB 2 half no longer appears as a separate "USB2.0 Hub" when the port has several hubs at its root, or when the hub reports no link speed.
- A Thunderbolt 5 dock whose USB 3 and USB 2 root hubs come from different vendors (Intel and Fresco Logic on the Anker Prime) shows one hub tree instead of two. The roots merge when the hubs below them are companions, and those merge too. A real capture of this dock is now a test fixture.
- Monitors driven from a Thunderbolt dock's DisplayPort outputs hang off the dock in the map, the list and the command-line tree, not off the Mac's port beside it.
- A USB4 v2 / Thunderbolt 5 port no longer shows 120 Gb/s while its dock shows 80 Gb/s. The idle second lane of a bonded link reports an asymmetric width with no bandwidth; the link now comes from the lane that carries traffic, as System Information reports it.
- The link page for the cable in a Mac port shows the power across it (a dock's charging, say), and the port inspector's "Cable and link" opens that page when one device is plugged in.
- The zoom buttons zoom around the middle of the map instead of its top-left corner.
- The map is drawn at screen resolution at every zoom, so links are no longer blurry at 200 %, and it draws only what is on screen, so panning and zooming a large map no longer lag. It can be dragged in any direction, a second drag no longer snaps it back to where it started, and it shows no scroll bars.
- Clicking a link in the map opens the inspector when it is closed, since the link is described only there.

## [1.0.0] - 2026-10-12

The first release.

### Added

- Menu bar item with a popover that lists every physical port on the Mac (USB-C and Thunderbolt, MagSafe, USB-A, HDMI) in physical order, with what is connected, the active transports, link speeds and power in or out. Optional live text next to the icon: total watts, device count or both.
- Device trees for USB hubs, docks and Thunderbolt / USB4 daisy chains, with device counts and power allocations rolled up to each hub and to the Mac. Every device is labelled with the port it hangs off.
- Link speed labels such as "USB 3.2 Gen 2 @ 10 Gb/s" and "USB4 v2 / TB5 @ 80 Gb/s", decoded from USB speed codes and Thunderbolt link speed and width registers.
- Port names from a per-model catalogue of physical locations ("Left Front · USB-C"), based on PortScope's data, with user renaming.
- Charger card: name, rated watts, the active USB-PD contract, every offered power profile, battery state and a sparkline of system input power.
- Per-port power output from the SMC power channels or the battery controller's port details where available, falling back to USB power allocations.
- Topology window with a graph of host, ports and devices, port and device tables, power charts, an event timeline, diagnostics and an inspector with raw IORegistry keys.
- Plug and unplug detection through IOKit notifications, with an event log and optional notifications for connections, disconnections, link downgrades and charger changes.
- Diagnostics: USB 3 device running at USB 2 speed, Thunderbolt link slower than both ends support, slow charger, not charging, bus-powered hub over budget, deep Thunderbolt chain, liquid detected, overcurrent.
- Export as JSON snapshot, Markdown report or raw IORegistry capture, with serial numbers redacted by default.
- Demo mode with four sample setups: Studio desk, Travel, Dock station and Unplugged.
- `busstop` command-line tool with text, JSON, Markdown and raw output, `--watch` for live connection events, `--demo`, `--input` for saved captures, `--no-redact` and `--no-smc`. Serial numbers are redacted from every format by default, watch mode included, device names are stripped of control characters before they reach the terminal, and a failed write to standard output ends the command with status 1.
- Settings for launch at login, menu bar content, text size, background opacity, notifications, port names and power polling.
- Lagoon visual design: true-black surfaces, a turquoise accent and Liquid Glass controls on macOS 26 and 27.
- App icon: a turquoise glass bus-stop sign with a USB-C port, on a near-black squircle.
- `scripts/build-app.sh`, `scripts/install.sh` and `scripts/smoke-test.sh` for building, installing and checking the app bundle; CI on Linux, macOS 26 and macOS 27; tagged releases with a universal, ad-hoc-signed zip and its SHA-256 checksum. The app bundle and the zip carry Bus Stop's licence and the MIT notices of PortScope, WhatPort and WhatCable.
- Screenshots of the app in demo mode, captured by CI on macOS 27 and published to the `screenshots` branch by a separate job that holds the only write token.

[Unreleased]: https://github.com/static74/BusStop/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/static74/BusStop/releases/tag/v1.0.0
