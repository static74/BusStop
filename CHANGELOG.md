# Changelog

All notable changes to Bus Stop are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- The README is shorter and written for people using Bus Stop; build and project details live in CONTRIBUTING.md and docs/. The tagline in the About window, `busstop --help` and the Ports widget's description now says "the ports on your Mac" rather than "every port", since macOS does not report some SD card slots.

### Fixed

- The desktop widgets' data file and redacted exports no longer show the serial number of a device whose name includes it once the device is unplugged, in its events or in a "keeps disconnecting" finding, including after Bus Stop restarts. The history now keeps those serial numbers with the events that hold them. A history saved by 1.2.0 or earlier has no such list, so its older events are not covered.
- Redaction no longer removes short all-hex numbers, such as "2160" in "3840 × 2160", from names and text. A display's serial number could match them.
- The Settings tabs are sharp on non-Retina displays. They were drawn half a pixel off and looked blurry. Settings now has standard Mac toolbar tabs, each with its icon, and the window takes the name of the selected tab.

## [1.2.0] - 2026-10-26

### Added

- Settings › Appearance › Data colours: colour links by speed with a preset instead of Lagoon's turquoise. Sky, Iris, Orchid, Ember, Tangerine, Citrine, Fern and Graphite keep Lagoon's shift from dim to bright, and Match System follows the accent colour in System Settings. The map, its pulses and key, speed chips and the Mac Outline all follow; Power mode and the desktop widgets keep their colours. Lagoon stays the default.
- Desktop widgets, in Large and Extra Large. **Ports** has one row per port in physical order with its device, link speed, watts and any diagnostic, and in Extra Large the devices behind each hub and dock. **Power** shows the charger and its USB-PD contract, the battery, total watts in and out and a last-hour chart, and in Extra Large the watts per port and a 24-hour chart. **Health** shows current diagnostics and flaky connections with their likely culprit, or "All links healthy", and in Extra Large the recent events and each port's last 7 days. A widget shows a Demo badge in demo mode, "Bus Stop isn't running" when its data is more than 5 minutes old, and "Open Bus Stop" before it has any. Clicking a widget opens Bus Stop on that page.
- `busstop://` links: `busstop://topology/<page>` opens the topology window on a page (`overview`, `silhouette`, `allPorts`, `devices`, `power`, `events` or `diagnostics`), and `busstop://port/<type>/<number>` opens it with that port selected.
- For the widgets, the app writes what they show to `widget-payload.json` in its App Group container, atomically and readable only by your user account. The snapshot in it is redacted like an export and leaves out the raw IORegistry properties, so it holds no serial numbers. Clear History and turning off "Keep history between launches" delete it; with history off it leaves out the events, the 24-hour power and the port health.
- Widgets appear only in builds signed by a team and installed in `/Applications`. Release builds are; a build from source signed ad hoc bundles the widgets, but macOS leaves them out of Edit Widgets.
- Settings › Ports › Identify a Port: plug something into a port, or unplug it, and Bus Stop highlights that port so you can confirm or correct its name. Copy Catalogue Entry puts this Mac's port names on the clipboard as a catalogue entry you can send upstream. Nothing is sent over the network.

### Changed

- Ports are named from where the Mac itself says they are. Recent Macs publish each Thunderbolt port's position in the IORegistry ("back-left"), and Bus Stop now uses it ahead of its model catalogue, so a Mac mini with M4 shows "Rear (left)", "Rear (center)" and "Rear (right)" instead of three ports named "Rear". Ports without it use the catalogue as before. Raw captures (`busstop --raw`) include these positions.
- Ports that would share a name are numbered, such as "Front · USB-C 1" and "Front · USB-C 2".

### Fixed

- The app icon no longer shows as coloured noise at 16 and 32 px, as in the widget gallery's app list. The icon file stored those sizes in slots macOS reads as raw pixels; it is now made with `iconutil`.
- A USB 3 port now shows the rate the Mac reports for it. A Mac mini with M4 says "Gen 1" signalling for a 10 Gb/s hub, and Bus Stop showed the port at 5 Gb/s while the hub on it showed 10 Gb/s. A real capture of that Mac is now a test fixture.

## [1.1.2] - 2026-10-24

### Changed

- Release builds are signed with a Developer ID and notarized by Apple, so macOS opens a downloaded copy without the "Open Anyway" step in System Settings.
- Releases come as a disk image, `BusStop.dmg`, instead of a zip: open it and drag Bus Stop onto the Applications folder beside it.

## [1.1.1] - 2026-10-19

### Changed

- Power polling speeds up to every 2 seconds only while the topology window can be seen. A window that is minimised, hidden, covered by other windows or on another Space no longer keeps it fast.
- Background captures make fewer calls: the SMC's per-port contract (`DxMP`) and description (`DxDE`) keys are no longer read, since nothing showed them, and a Thunderbolt switch in the port plane is read with the common keys only. Raw captures (`busstop --raw`) no longer include those two SMC values.
- A port counter (plug events, connections, overcurrents) that reads lower than before keeps its earlier value as the starting point instead of starting over, so one glitched reading can no longer add a port's lifetime count to today.
- Reset All Settings also resets whether the sidebar's Cables section is expanded.

### Fixed

- Demo mode no longer shows or changes your own port names when a demo uses your Mac's model. Names given in demo mode are kept apart, as pins already were.
- A demo update that arrives just as demo mode is turned off is no longer treated as live, so it cannot post a notification for a demo device.
- A device that left with a hub and was plugged in elsewhere within a moment is no longer drawn twice, once live and once fading under the hub.
- A history file that can be neither read nor moved aside is no longer overwritten; Bus Stop leaves it alone and saves again once you clear the history.
- A clock set ahead and then put right no longer erases the saved history, for any Mac model and even when Bus Stop saves before its next reading, and power recording resumes at once instead of waiting for real time to catch up. While the clock is in doubt, old history is trimmed by the time of the last reading before the jump.
- A port whose plug count was missing for a while, such as across a sleep, no longer raises a false "keeps disconnecting" warning on the next replug.
- HDMI links, and DisplayPort or USB 3 links with no reported rate, are drawn in the accent colour on chips, the map and the Mac Outline instead of the USB 2 colour.
- A cable whose e-marker says USB 3.2 Gen 2 / USB4 Gen 2 is rated 20 Gb/s, not 10, so the inspector no longer says it limits a 20 Gb/s link it carries.
- A corrupt power reading at the bottom of the 64-bit range is dropped instead of crashing the app when it formats power.
- The port number of a `usb-drd` USB controller is read only from the controller itself, never from a node below it, which could place its devices on the wrong port.

### Security

- Redacted exports no longer leak a serial number that a device puts in its own name. A known serial is removed wherever it appears as a whole word: device, display and charger names, diagnostic text, every string of a raw capture (registry entry names included), `busstop --watch` lines and Copy Details. The CLI's default text tree is now redacted too; `--no-redact` keeps everything as before.
- Redacted exports drop EDID data whose serial fields cannot be found (shorter than one block, or bytes after the last whole block), and blank a DisplayID block that cannot be walked, instead of passing it through unchanged.

## [1.1.0] - 2026-10-19

### Added

- Bus Stop keeps its history between launches: the event log (up to 5,000 events or 30 days, was 500 events in memory), power averaged per minute for 7 days, and each port's plug, connection, overcurrent and liquid counts per day for 90 days. It is saved in `~/Library/Application Support/io.github.static74.busstop/history.json`, readable only by your user account, with one section per Mac model. Settings › Advanced › History shows its size, oldest entry and event count, clears it, or turns saving off (which deletes the file). Demo mode never reads or writes it, and `busstop --watch` still keeps nothing. The Events page shows the saved log and when it starts, and its Clear removes the saved events too; the sidebar badge counts events since launch.
- The Power page's charts cover the last 10 minutes, hour, 24 hours or 7 days. Ten minutes is the live reading; the longer ranges come from the saved history, averaged per minute (per 10 minutes for 7 days). Lines break where Bus Stop was not running or the Mac slept instead of joining across the gap (a lone reading shows as a dot), the time axis suits the range, and the chart header says when the readings start if that is later than the range. System load is now charted from the same readings, so it covers the whole range rather than only the time since the window first opened.
- Topology map: drag to pan like a web map, and zoom around the pointer with a mouse scroll wheel. Trackpads still pan with two fingers and zoom with a pinch. Zoom now runs from 25 % to 200 %.
- Click a link in the map to inspect it: the negotiated speed, the power across it and, for the cable in one of the Mac's own ports, what its e-marker chip says it is rated for (speed, power, current, voltage, EPR), with a note when the cable or the device is what limits the link. Hovering a link highlights it.
- A Cables section in the window's sidebar lists every link below each port as "parent → child" with its speed. Clicking one opens it in the inspector and moves the map to it.
- A Data / Power toggle on the map. In Power mode links are coloured from grey through deep red, orange and amber to gold as watts rise, chips show watts (a port's measured reading, or "≤" a USB power budget), and pulses run the way the power flows, such as from a dock into the Mac.
- Port and device inspectors link to the cable and link page; the port's cable section shows rated power, maximum voltage and EPR support.
- A USB device that reports a vendor ID but no vendor name now shows the vendor's name from a table built into Bus Stop. `scripts/generate-usb-vendors.py` generates the table from the USB ID Repository's `usb.ids` (version 2026.06.26), used under the 3-clause BSD License, whose notice is in `THIRD_PARTY_NOTICES.md`. A device's own vendor name always wins, and Bus Stop still makes no network requests.
- Bus Stop spots flaky connections. A device that disconnects and comes back on the same port 3 times in 10 minutes, a USB or Thunderbolt link that keeps switching between faster and slower, and a device running slower than it has before on the same port (such as a USB 3 drive that comes back at 480 Mb/s and no longer says it is USB 3) each raise a warning with the likely cause: the cable, the port, a hub or the device. Devices are followed across controllers by their serial number, or by port and position when they have none. Drops in the first 15 seconds after launch or wake, a device that comes back when the screens wake (many monitors drop off while they sleep), and devices present for under 2 seconds (a dock starting up), do not count, and a warning stays until 10 minutes pass without a new drop. The warnings notify under the diagnostics toggle, show in the Diagnostics page and the popover banner, and `busstop --watch` prints them as `!` lines.
- The device inspector has a Connection history section once a device has dropped or slowed down: reconnections in the last 10 minutes, its best and current link on this port, and the likely cause.
- The Events page's filter has a Problems choice: warning and critical findings and slower links.
- A Flaky cable demo setup (`flakyCable`): the Travel MacBook Air with an iPhone whose cable drops out every 8 seconds, so the flaky-connection warning appears after about 40 seconds.
- A Mac Outline page in the window's sidebar, under Map, draws the Mac with each port where it sits: a laptop seen from above, or the front and back of a desktop. Each port is coloured by what is plugged in and how fast it runs, or by watts when the Data / Power toggle is on Power, with a dot for a diagnostic. Click a port to inspect it; selecting a device marks its port, and search dims ports that do not match. Every port is shown, even with "Hide empty ports" on. Positions come from the PortScope catalogue and are approximate.
- `BUSSTOP_AUTOMATION=topology:<page>` opens the topology window on a page, such as `topology:silhouette`.
- Pin one port to the menu bar, from Settings › Menu Bar or "Pin to Menu Bar" in a port card's context menu, and its link speed, its power or both show after the menu bar text: "5 · 38W · 40G ↓61W". "≤" marks a USB power budget or charger contract rather than a measurement. The pinned port's name is in the item's tooltip and VoiceOver label, and its card shows a pin. Pins are kept per Mac model, and a pin made in demo mode never replaces the live one.
- A compact popover layout, in Settings › General › Ports, lists each port on one line: its name, what is connected ("Samsung T9", "3 devices" or the charger), its link speed and its power. An arrow beside a port shows the same device tree as the card, and the context menu and VoiceOver actions match the card's. The power card shrinks to one line in this layout. Cards stay the default.
- Port health. The port inspector's Statistics section is now Health: the hardware's all-time connections, plug events and overcurrent events, each with how many came in the last 7 days, plus liquid detections and connection errors (a device that left within 10 seconds, a slower link, a USB 2 fallback) in the last 7 days, from the saved history. A port with at least 3 times the connection errors per connection of the Mac's other ports of the same kind (at least 5 connections and 3 errors in 7 days) gets a gentle note in Diagnostics and the inspector, never a notification. In the popover, a port with a flaky connection, a flapping or slower link, or one that stands out gets a small health mark after its name, with the findings in its tooltip and VoiceOver label. `busstop --watch` applies the same rules to what it has seen since it started.
- Light theme: Settings › Appearance › Theme offers Dark (the default), Light and Match System. Light keeps the turquoise accent; faster links and more power draw darker instead of brighter, Power runs from gold to deep red, and nothing glows. Switching applies at once, to open windows too. Try it with `-theme light`.
- `docs/ROADMAP.md` with the planned features after 1.0.

### Changed

- Bus Stop uses much less energy in the background. Between hardware changes, the power poll now re-reads only the battery and SMC power values instead of the whole I/O Registry, and it does not contact powerd. The full topology is still re-read on every hardware notification and at least once a minute. A power update also pushes the next poll back, and polling stops while the screens are asleep or another user is logged in, with a full refresh on wake. Connect and disconnect events and notifications still fire while polling is paused.
- Reset All Settings also resets the map's Data / Power choice. The map and the Mac Outline share it.
- Links that run together in the map no longer look brighter where they overlap, and links leaving one card start from separate points instead of a single one.
- A monitor that reaches a port through a Thunderbolt dock is drawn under the dock in the map.
- Device counts (the window subtitle, the menu bar text, All Devices, port and dock roll-ups, Markdown reports and `busstop --watch`) count only the devices drawn on the map, so they no longer include a dock's built-in parts: 27 devices became 20 on the Anker Prime capture. The All Devices subtitle says when built-in parts are left out, and the Dock station demo shows 8 devices instead of 9.
- JSON snapshots: a dock's built-in parts move from its `children` to a new `internalParts` list, and a device that hangs off a built-in part records it in `internalParentID`. Snapshots without built-in parts are unchanged, and older exports still decode.
- A built-in hub's USB 2 fallback and power budget findings point at the dock, and its link speed changes are reported naming the dock. A device that becomes a built-in part, or stops being one, raises no connect or disconnect event.
- JSON snapshots: each port records where the model catalogue places it in `catalogLocation` ("Left Front", "Rear (left)"), which stays when the port is renamed. Older exports still decode.
- Inspector rows put each value on its own line under the field name, so a long value uses the inspector's full width instead of wrapping in a narrow right column. A value too long for one line wraps. The battery card on the Power page uses the same rows.
- VoiceOver says "up to" before a port card's power when it is a USB power budget or charger contract rather than a measurement, as the menu bar item does. A renamed port's VoiceOver actions include Restore Default Name, as its context menu does.
- The overcurrent warning comes from the saved history: it shows for 24 hours after a port's overcurrent counter last went up, even across a relaunch, and gives the count for the last 7 days. It used to compare with the count when Bus Stop started and last until it quit.
- On the Diagnostics and Events pages, a title that does not fit beside its severity chip or its times moves them under it, so at large text sizes in a narrow window a word such as "disconnecting" no longer breaks in the middle.

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
- Map cards and speed/power chips are now sharp at every zoom. They were drawn at 100 % and enlarged, which looked pixelated at 200 %, most visibly on non-Retina displays.
- With the inspector open, the toolbar no longer ends in a gray band that the search field overlapped. The Export button's icon is centred.
- The topology window no longer crashes on the Events page, or on Diagnostics while it lists a finding, when the inspector is open in a window narrower than about 1100 pt. Events' filter and Clear button move under the title when they do not fit beside it, instead of being clipped, and a finding's Show buttons stack the same way.
- Resting the pointer on a speed chip, transport chip or power badge on the map now shows what it means, such as "USB 3.2 Gen 2 @ 10 Gb/s" or "4.5 W to devices (allocated)". The map draws these tooltips itself, at the same size at every zoom; the chips on the links have them too.
- The map's zoom buttons and Data/Power picker no longer depend on the map's tooltip tracking, which could stall after the pointer rested on the map and leave them without tooltips until the pointer went back to the same spot; each now has its own.
- A Thunderbolt dock's own USB parts (its USB root hub, its internal hubs and its own USB functions, such as its firmware endpoints, Ethernet and card reader) no longer appear as separate devices joined to the dock by what looked like cables. The map, the list and the command-line tree show one dock card with the devices plugged into the dock's ports, and do not mention the parts. The dock's inspector lists the built-in parts with their vendor, speed and power; VoiceOver says how many there are; Copy Details in the popover and the dock's entry in a Markdown report name them on a "Built in" line. On the Anker Prime TB5 capture, eight cards (the dock and seven built-in parts) became one. The rules are strict: a part that cannot be told apart from an external device stays on the map, and power figures do not change.

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

[Unreleased]: https://github.com/static74/BusStop/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/static74/BusStop/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/static74/BusStop/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/static74/BusStop/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/static74/BusStop/releases/tag/v1.1.0
[1.0.0]: https://github.com/static74/BusStop/releases/tag/v1.0.0
