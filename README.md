<p align="center">
  <img src="docs/images/icon-256.png" width="128" height="128" alt="Bus Stop app icon: a turquoise glass bus-stop sign with a USB-C port on it">
</p>

<h1 align="center">Bus Stop</h1>

<p align="center"><strong>A live map of the ports on your Mac.</strong></p>

Bus Stop is a free, open-source menu bar app for macOS. It shows the physical ports on your Mac, what is plugged into each one, how fast each link runs and how much power flows through it. Hubs, docks and Thunderbolt chains appear as trees, every device is labelled with the port it hangs off, and plain-English diagnostics tell you when a drive is stuck at USB 2 speed or a cable is holding a link back. Everything stays on your Mac: no network code, no telemetry, no accounts.

![The Bus Stop popover open below its menu bar icon, showing the Studio desk demo setup](https://raw.githubusercontent.com/static74/BusStop/screenshots/studioDesk-popover.png)

*The popover: the charger and its USB-PD contract, a diagnostic, and one card per port with the devices behind it, their link speeds and power.*

![The Bus Stop topology window, showing the Mac, its ports and the devices behind them as a graph](https://raw.githubusercontent.com/static74/BusStop/screenshots/studioDesk-topology.png)

*The topology window: the Mac, its ports and every device behind them, with each link drawn by speed. The sidebar leads to the port and device tables, power charts, the event log and diagnostics.*

Both screenshots show the Studio desk demo setup. Demo mode (Settings › Advanced) shows the same setups on your own Mac, with nothing plugged in. [More screenshots](https://github.com/static74/BusStop/tree/screenshots) cover the other demo setups and every settings pane.

## Features

- **A port map in the menu bar.** One card per port in physical order, or one line per port, with what is connected, the link speed and the power in or out. Optional live text next to the icon: total watts, device count, or a pinned port's speed or watts.
- **Real port names.** "Left Front · USB-C" instead of "Port 2", from the Mac itself or a per-model catalogue. Rename any port, or find one by plugging something into it (Settings › Ports › Identify a Port).
- **Hubs, docks and daisy chains** as trees, with device counts and power rolled up to each hub and to the Mac. A Thunderbolt dock shows as one device with what is plugged into it, not as its internal parts.
- **Link speeds** for every device and port, such as "USB 3.2 Gen 2 @ 10 Gb/s" or "USB4 v2 / TB5 @ 80 Gb/s", and cable details when the port reports them: active or passive, optical.
- **Power.** Watts in and out per port, the charger with its active USB-PD contract ("20 V × 4.7 A") and every profile it offers, battery state, a sparkline in the popover and charts of system and per-port power over the last 10 minutes, hour, day or week.
- **Diagnostics in plain English.** A USB 3 device running at USB 2 speed, a Thunderbolt link slowed by its cable, a charger too weak for the Mac, a battery not charging, a bus-powered hub over its budget, a very deep chain, liquid in a port, a port that cut power.
- **Flaky connections.** A device that keeps disconnecting, a link that keeps changing speed or a drive slower than it was on the same port, with the likely culprit: the cable, the port, a hub or the device.
- **Port health.** Each port's plug events, connections, overcurrents and connection errors over the last 7 days next to the hardware's all-time counts, with a note when one port has far more problems than its siblings.
- **Instant change detection.** Plug and unplug events show up at once, in an event log kept between launches, with optional notifications.
- **A topology window** with the graph, a Mac Outline that places each port where it sits on the case, sortable port and device tables, power charts, the event log, diagnostics and an inspector down to the raw IORegistry keys.
- **Desktop widgets** in Large and Extra Large: Ports, Power and Health. Bus Stop must be running to keep them current.
- **Export** a JSON snapshot, a Markdown report or a raw capture for bug reports, with serial numbers redacted by default.
- **A command-line tool**, `busstop`, with text, JSON, Markdown and raw output, a watch mode and the demo setups.
- **Settings** for Dark, Light or Match System, nine data-colour presets or Match System, text size, background opacity, popover layout, menu bar content, notifications and launch at login.

## Requirements

- macOS 26 Tahoe or later. Bus Stop is designed for macOS 27.
- Apple silicon recommended. On an Intel Mac with macOS 26 the port controllers do not publish per-port detail, so the map is less complete.

## Install

Download [`BusStop.dmg`](https://github.com/static74/BusStop/releases/latest/download/BusStop.dmg) from the [latest release](https://github.com/static74/BusStop/releases/latest), open it and drag **Bus Stop** onto the Applications folder beside it. Releases are signed with a Developer ID and notarized by Apple. Keep it in `/Applications`: the desktop widgets appear in Edit Widgets only from there.

To check the download, put `BusStop.dmg.sha256` from the release next to the image and run `shasum -a 256 -c BusStop.dmg.sha256`.

Bus Stop lives in the menu bar: left-click the icon for the port map, right-click it for the menu. While one of its windows is open it also shows a Dock icon, which you can turn off in Settings › General.

### Build from source

With Xcode 27 or Xcode 26.6 installed:

```sh
git clone https://github.com/static74/BusStop.git
cd BusStop
scripts/install.sh              # build, install to /Applications and open
scripts/install.sh --link-cli   # the same, plus a link to the busstop command
```

A build from source includes the widgets, but macOS shows them only when the app is signed with an Apple developer certificate. [CONTRIBUTING.md](CONTRIBUTING.md#testing-widgets) explains how.

## Command-line tool

The app bundle contains `busstop` at `Bus Stop.app/Contents/Helpers/busstop`; `scripts/install.sh --link-cli` links it into `/usr/local/bin`, or `~/.local/bin` when that is missing or not writable.

```
busstop                         # human-readable tree
busstop --json                  # the snapshot as JSON
busstop --markdown              # a Markdown report
busstop --raw > capture.json    # raw IORegistry capture, for bug reports
busstop --watch                 # print connection changes as they happen
busstop --demo studioDesk       # any of the above against a demo setup
busstop --input capture.json    # read a capture saved with --raw instead of this Mac
```

Serial numbers are redacted from every output unless you add `--no-redact`. `busstop --help` lists every option and the demo setups (`studioDesk`, `travel`, `dockStation`, `unplugged`, `flakyCable`).

`busstop --demo studioDesk` prints:

```
MacBook Pro (14-inch, 2026, M5 Pro) · macOS 27.0 · demo
Power: 140W USB-C Power Adapter · 28 V × 5 A · 62 W in · Charging · 76% · 4 W to ports
├─ Left Rear · MagSafe   140W USB-C Power Adapter   ↓ 62 W
├─ Left Center · USB-C   USB4 v2 / TB5 @ 80 Gb/s
│  └─ Studio Display XDR · 80 Gb/s
│     └─ Studio Display XDR Hub · 10 Gb/s
│        ├─ PSSD T9 · 10 Gb/s · 4.5 W
│        └─ Studio Display XDR Camera · 480 Mb/s · 2.5 W
├─ Left Front · USB-C   USB 3.2 Gen 2 @ 10 Gb/s   ↑ 4 W
│  └─ USB3.1 Hub · 10 Gb/s · 4 W
│     ├─ DataTraveler 3.0 · 480 Mb/s · 2.5 W
│     ├─ Keychron K8 Pro · 12 Mb/s · 0.5 W
│     └─ USB Optical Mouse · 1.5 Mb/s · 0.5 W
├─ Right Front · SD Card   (empty)
├─ Right Rear · HDMI   (empty)
└─ Right Center · USB-C   (empty)

Displays
├─ Color LCD · 3024 × 1964 @ 120 Hz · built-in
└─ Studio Display XDR · 5120 × 2880 @ 120 Hz · Left Center · USB-C

Diagnostics
└─ Warning: DataTraveler 3.0 is running at USB 2 speed
```

## Privacy

- No network code, no analytics, no crash reporting, no accounts.
- Bus Stop only reads IORegistry properties, the power-source API, the display list, the SMC's read-only power keys, and the Mac's model, chip and macOS version. It never ejects, powers off or reconfigures anything, and it never reads the computer name.
- Settings and port names are stored in the app's preferences. The event log, power history and port counts are saved in `~/Library/Application Support/io.github.static74.busstop/history.json`, readable only by your account. It holds device names, display serial numbers and Thunderbolt device IDs, and a list of the device serial numbers that appear in its events, so the widgets can hide them. It never holds the Mac's serial number. Settings › Advanced › History clears it or turns saving off, and demo mode never touches it.
- The widgets read a copy of what they show from a file the app shares only with them; clearing the history deletes it too. Nothing else is written unless you export.

## How it works

macOS already knows which controller drives each port, what is plugged in, the speed each link negotiated and the power flowing through it. Bus Stop reads that information and turns it into a map of ports and the devices behind them. It only ever reads; it never changes anything. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/SPEC.md](docs/SPEC.md) have the details.

## Contributing

Bug reports with a raw capture (`busstop --raw > capture.json`) are the most useful thing you can send. [CONTRIBUTING.md](CONTRIBUTING.md) covers building, testing, adding a Mac model to the port catalogue and turning a capture into a test fixture.

## Credits

- **[PortScope](https://github.com/azenla/portscope)** by Alex Zenla (MIT): the per-model catalogue of physical port locations.
- **[The USB ID Repository](http://www.linux-usb.org/usb-ids.html)** (3-clause BSD License): the names of USB vendors, for devices that do not report their own. The list is built into the app; Bus Stop never downloads it.
- **[WhatPort](https://github.com/darrylmorley/whatport)** and **[WhatCable](https://github.com/darrylmorley/whatcable)** by Darryl Morley (MIT): research on Apple's port controllers, SMC power channels and Thunderbolt chain attribution.
- The Linux kernel's Thunderbolt driver ([`drivers/thunderbolt/tb_regs.h`](https://github.com/torvalds/linux/blob/master/drivers/thunderbolt/tb_regs.h)) documents the link speed codes Bus Stop decodes. No kernel code is used.

Full licence texts are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), which every build also carries in `Bus Stop.app/Contents/Resources`.

## Licence

Bus Stop is released under the [MIT License](LICENSE).

Apple, Mac, macOS, MagSafe and Xcode are trademarks of Apple Inc. Thunderbolt is a trademark of Intel Corporation. USB-C and USB4 are trademarks of the USB Implementers Forum. HDMI is a trademark of HDMI Licensing Administrator, Inc. Bus Stop is not affiliated with or endorsed by any of them.
