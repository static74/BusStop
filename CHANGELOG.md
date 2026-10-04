# Changelog

All notable changes to Bus Stop are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-04

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

[1.0.0]: https://github.com/static74/BusStop/releases/tag/v1.0.0
