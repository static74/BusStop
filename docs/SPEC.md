# Bus Stop: product and technical specification

Version 1.0 (October 2026). Status: implemented in this repository.

Bus Stop is a free, open-source (MIT) macOS menu bar utility that shows every physical port on a Mac, what is plugged into each one, how fast each link runs, and how much power flows through it. It is an open alternative to the commercial ViewPorts app ("See what's connected", $6.99, macOS 26+), rebuilt from public information and original code, and designed for macOS 27 "Golden Gate" with a turquoise-on-true-black Liquid Glass look by default, and a light theme.

---

## 1. Goals and non-goals

### Goals

1. Show a live map of the Mac's physical ports: USB-C / Thunderbolt, MagSafe, USB-A, HDMI.
2. For each port, show what is connected (hubs, docks, displays, drives, chargers, phones, input devices), the negotiated link speed, and power in or out.
3. Show the full device chain: hubs, docks and daisy-chained Thunderbolt / USB4 devices, with every device labelled by the port it ultimately hangs off.
4. Roll power and device counts up to each hub and to the host.
5. Detect plug and unplug events instantly and keep an event history between launches.
6. Stay 100% local. No network access, no telemetry, no accounts.
7. Look at home on macOS 27: Liquid Glass controls, true black surfaces by default with a light theme, turquoise accent.
8. Be easy to build from source with nothing but Xcode 27 (or Xcode 26.6) and SwiftPM.

### Non-goals (v1)

- Network ports, Wi-Fi, Bluetooth, AirPlay, VPNs. Bus Stop is about physical connectors only.
- Intel Macs. macOS 27 runs only on Apple silicon. Bus Stop builds for macOS 26+ and will run on an Intel Mac with macOS 26, but port-controller detail is unavailable there and the app says so.
- Mac App Store distribution. The App Sandbox blocks parts of the IOKit access Bus Stop needs (SMC power channels, some notifications).
- App Intents. They need the App Intents metadata that Xcode generates and SwiftPM does not, and an Xcode project conflicts with a zero-setup open-source build. A command-line tool (`busstop`) covers scripting instead.
- Changing anything. Bus Stop is read-only: it never ejects, powers off or reconfigures a port.

---

## 2. Feature inventory

### 2.1 Parity with ViewPorts

Public description of ViewPorts (search snippets of viewports.app; the site itself, its screenshots and the r/macapps launch thread were not reachable from the build environment):
"macOS menu bar utility that maps every port, device, and power draw on your Mac, with live topology, hub and daisy-chain support, and link speeds — all local, no telemetry."

| ViewPorts feature | Bus Stop implementation |
|---|---|
| Live port data in the menu bar | Status item with icon plus optional live text (total watts, device count, or both), and one pinned port's speed or watts |
| Maps every port, device and power draw | Port roster from IOKit port controllers, USB and Thunderbolt device trees, power telemetry |
| Live topology | Topology window: host, ports, devices drawn as a connected graph with animated links |
| Hub and daisy-chain support | USB hub trees; Thunderbolt / USB4 switch chains (Route String / Depth) |
| Link speeds | Per device and per port, e.g. "USB 3.2 Gen 2 @ 10 Gb/s", "USB4 v2 / TB5 @ 80 Gb/s" |
| Power draw and connection speed per port, rolled up per host | Per-port watts in/out, per-hub allocation totals, host totals |
| Each device labelled by its port | Every device row carries its root port label, e.g. "Left Front · USB-C 2" |
| Detects connection changes instantly | IOKit matching and interest notifications, debounced at 250 ms |
| 100% local, no telemetry | No network entitlement, no network code |

### 2.2 Additions

These close gaps users reported against similar tools (WhatCable, WhatPort and PortScope issue trackers):

- Physical port names from a per-model catalogue ("Left Rear", "Right Center"), with user renaming. Settings › Ports › Identify a Port highlights the one port whose connection, transports or devices change after the user plugs into it or unplugs from it, and offers its name for confirming or correcting; Copy Catalogue Entry puts the ports' names on the clipboard as a PortScope `MacPortLocations.json` entry. Nothing is sent.
- Charger card: name, rated watts, active PD contract (volts and amps), full list of offered power profiles.
- Cable information when the port exposes it: active or passive, optical.
- Diagnostics with plain-English explanations:
  - device running at USB 2.0 on a port that supports USB 3 or better
  - Thunderbolt link slower than both ends support (cable bottleneck)
  - charger below the Mac's needs, or not charging
  - bus-powered hub over its power budget
  - deep daisy chain
  - a device that keeps disconnecting, a link that keeps changing speed, or a device slower than it has been on the same port, with the likely culprit (cable, port, hub or device)
- Event timeline (connect, disconnect, speed change, charger change) with timestamps.
- Power sparkline for system input over the last few minutes in the popover; on the Power page, charts of system and per-port power over the last 10 minutes, hour, 24 hours or 7 days.
- Tree view and flat list view.
- Export: JSON snapshot, Markdown report, raw IORegistry capture (for bug reports).
- Notifications on connect, disconnect and link downgrade, each with its own toggle.
- Demo mode with realistic sample setups, for screenshots and for trying the UI on a machine without accessories.
- Command-line tool `busstop` with `--json`, `--watch`, `--raw` and `--demo`.
- Settings for text size, background opacity (solid fallback for legibility), menu bar content, launch at login.

---

## 3. User experience

### 3.1 Menu bar item

- `NSStatusItem` with a template icon. Icon choices: Bus Stop sign (default), cable connector, bolt, ports grid.
- Optional text next to the icon, monospaced digits, compact to save menu bar space: none, total power ("38W"), device count ("5"), or both ("5 · 38W"). Power precision is automatic (one decimal below 10 W), whole watts, or one decimal.
- One port can be pinned, per Mac model, from Settings › Menu Bar or a port card's context menu. Its segment follows the text after " · ": link speed ("40G"), power ("↓61W" in, "↑4.5W" out), or both ("40G ↓61W", the default). "≤" marks a USB power budget or PD contract rather than a measurement ("↑≤4.5W"). A half with nothing to show drops out; an empty port shows "–". The port's name is not in the title; it is in the tooltip and the VoiceOver label ("Pinned: Left Rear USB-C, 40 gigabits per second, 61 watts in"). A pin for a port this Mac does not have adds nothing and stays stored. Demo pins are kept apart from live ones.
- Left click toggles the popover. Right click opens a menu: Open Topology, Refresh, Export submenu, Settings, About Bus Stop, Quit.
- Relaunching the app while it is running opens the popover.
- The item can be hidden from Settings; when hidden, launching the app opens the topology window.

### 3.2 Popover (380 pt wide, up to 640 pt tall, scrolls)

From top to bottom:

1. **Header.** Machine name ("MacBook Pro 14-inch, M5 Pro") and a one-line summary ("4 ports · 6 devices · 61 W in"). On the right, a glass control cluster: Refresh, Open Topology, Settings.
2. **Power strip.** Charger card when one is attached: charger name, watts, active contract "20 V × 4.7 A", a mini sparkline of system input power, battery state ("Charging · 82%"). On desktops: total power delivered to ports.
3. **Diagnostics banner** (only when there is a warning), collapsible.
4. **Port list.** One card per physical port, in physical order:
   - Leading status glyph: filled turquoise ring when something is connected, dim ring when empty.
   - Title: location label and connector ("Left Front · USB-C").
   - Chips: active transports with speed ("USB 3 · 10 Gb/s", "DisplayPort", "Thunderbolt · 40 Gb/s"), power badge ("↓ 61 W" in, "↑ 4.5 W" out).
   - Nested device tree with indentation guides. Each device shows name, kind icon, speed and allocated power. Hubs show "3 devices · 7.5 W" roll-ups and can collapse.
   - Empty ports are shown dimmed, or hidden with the "Hide empty ports" setting.
   - The port pinned to the menu bar has a pin after its title. A port with a flaky connection, a flapping or slower link, or one that stands out (§5.4) has a small health mark after its title, in the colour of its most severe finding; its tooltip lists the findings and the card's VoiceOver label ends with their titles. The card's context menu and VoiceOver actions offer Rename Port, Restore Default Name (when renamed), Pin to Menu Bar or Unpin from Menu Bar, and Show in Topology.
5. **Footer.** "Updated just now" and the button "Open Topology". (In demo mode a DEMO badge sits on the header's summary line.)

**Compact layout** (Settings › General › Ports › Popover layout; cards are the default). The port list becomes one card with one line per port, separated by hairlines: an arrow (when devices are connected), the connector icon, the port's short name, a pin when it is pinned and the card's health mark, then what is connected ("Samsung T9", "3 devices" counting every level, the charger's name, "Connected" or "Nothing connected"; a device that just left keeps its name while its ghost is shown), then the speed chip and power badge. The arrow, or the Show Devices VoiceOver action, reveals the same device tree as the card, so nothing is lost; every arrow is closed again when the popover next opens. Each line has the card's context menu, VoiceOver label and actions, and renames in place the same way; its VoiceOver label also says the port's link speed, which the card's transport chips say on their own. The power strip becomes one line: a symbol, the charger's name, the battery state or "Accessories", and a power badge, with no sparkline. The diagnostics banner, Other devices and Displays are unchanged. Hide empty ports and port order apply as with cards.

### 3.3 Topology window

An `NSWindow` hosting SwiftUI, default 1280 × 820 when the screen allows (never smaller than 900 × 600), resizable, remembers its frame. The graph fits the window width on open and keeps fitting until the user zooms. `NavigationSplitView` with:

- **Sidebar** (system Liquid Glass sidebar): Overview and Mac Outline (under Map), Ports (one row per port), Cables, Devices (flat list), Power, Events, Diagnostics. Cables is a collapsible section with one group per port that has something plugged in, labelled with its number of links. Each group lists every link below that port in tree order as "parent → child" with its negotiated rate. Links to a dock's built-in parts are not listed, since those parts are not in the tree (§5.4 "Built-in dock parts"); a dock whose parts Bus Stop cannot recognise can still show links that run inside it. Clicking a row reveals the link: the window goes to a page that shows it, opens the inspector on it and moves the map to it.
- **Detail**:
  - *Overview*: the topology graph. Host node on the left, port nodes in the middle column, device trees fanning out to the right. Links are drawn as curved turquoise paths whose thickness and colour strength (brighter in Dark, darker in Light) scale with link speed. Small light pulses travel along active links (disabled with Reduce Motion). Each link carries a speed chip; each port and hub node carries a power badge. Resting the pointer on a chip or badge shows what it means in a tooltip the map draws itself, the same size at every zoom and after the system's tooltip delay (see `docs/decisions.md`). Clicking a node selects it. Overlapping links never look brighter than one link: glows (Dark only) share one layer and strokes are solid colours.
    - *Moving around*: drag anywhere on the map to pan it, like a web map (open hand over the map, closed hand while dragging); the content follows the pointer in any direction, and at least 80 pt of the graph always stays on screen. A mouse scroll wheel (including wheels with smooth scrolling) zooms around the pointer, about 10 % per notch; a trackpad's or Magic Mouse's two-finger scroll pans (with momentum), a wheel with a modifier pans (Shift sideways), and a pinch zooms around where it started. Zoom runs from 25 % to 200 %; the zoom buttons zoom around the middle of the map. Panning or zooming ends fitting; Zoom to Fit brings it back. When the window or the inspector changes the map's size, the middle of the map stays in the middle. The map has no scroll view and no scroll bars: it is drawn through a camera (scale and offset) at the size of the window, so it stays sharp at any zoom and draws only what is on screen, and the pulses rest while a drag or pinch is in progress (see `docs/decisions.md`).
    - *Links*: hovering a link highlights it and shows a pointing hand; clicking within about 6 pt of it selects it, and it stays outlined while selected. The inspector then shows the link: "Mac → port" or "parent → child", the negotiated generation, rate and lanes, and the power across it (for the cable in a Mac port, the port's own power reading, such as a dock charging the Mac). For the cable in one of the Mac's own ports (the Mac → port line and the line from the port to what is plugged into it), it also shows the cable's e-marker data: rated speed, rated power (240 W for a 5 A, 50 V EPR cable, otherwise 20 V × rated current), current, voltage, EPR support, active or passive, optical, PD revision and IDs, plus one sentence when the cable or the device limits the link. A cable without a readable e-marker gets a plain explanation of what that usually means. For links further along, the inspector says the Mac cannot read that cable's chip.
    - *Data and Power*: a toggle beside the legend (remembered between launches) switches what the links show. Data colours links by negotiated speed with rate chips. Power colours them on a heat ramp where more watts always means more contrast (§4.2). In Dark it gets brighter as watts rise: grey for no power, then deep red (under 5 W), orange (5–15 W), amber (15–45 W) and gold (45 W and up); amber and gold glow, and each step is at least 3.4:1 on the black map. In Light it gets darker, from gold (under 5 W) through amber and rust to deep red (45 W and up), nothing glows, and each step is at least 3:1 on the light map. Chips show watts, and pulses run the way the power flows. The cable in a Mac port (the Mac → port line and the line from the port to what is plugged into it) carries the port's reading, towards the Mac when the Mac charges from that port. A link further along carries the USB power budget of the child and everything below it, shown as a ceiling ("≤4.5 W"), because macOS reports what a device is allowed to draw, not what it draws.
  - *Mac Outline*: a generic outline of the Mac with each port where `ChassisLayout` (§5.4) puts it, drawn with shapes at their final size. A laptop is seen from above with the hinge at the top, so "Left" is the user's left. A Mac mini, Mac Studio or Mac Pro gets a front and a back elevation, each only when it has ports; an iMac gets only its back. The back is drawn as seen from behind, so "Rear (left)" is on the viewer's left, and is captioned "Back, seen from behind". A Mac the catalogue and its name do not identify gets a plain box. Every port in the snapshot is drawn, empty ones too, even when "Hide empty ports" is on. In Data mode a port is dim when empty, the link colour for its speed, the accent colour when connected with no data rate (HDMI, DisplayPort) and the charging colour when only a charger is plugged in; in Power mode it takes the power colour of its reading, on the same theme-aware ramp as the map. A dot in the severity colour marks a port with a diagnostic about it or a device on it, and the port's tooltip and VoiceOver label name the severity. Clicking a port selects it and opens the inspector; selecting a device marks its port; search dims ports that match neither themselves, a device on them nor a display macOS reports on them. Ports stay at least one port button (42 pt) apart; a column too narrow for that scrolls the outline sideways. Catalogue connectors macOS does not report (Ethernet, the power inlet, an SD slot) are outlined and do nothing. Ports with no place are listed under "Not placed". The Data / Power toggle and the legends sit over the bottom edge, as on the map, plus a key for empty, no-rate and charger ports. Captions say positions are approximate and come from the PortScope catalogue; a Mac with no known positions is told CONTRIBUTING.md explains how to add it, and an unlisted Mac placed by kind only is told so. A reveal while this page is open stays on it when the selection is the Mac or belongs to a port.
  - *Ports / Devices*: tables with sortable columns (name, port, speed, power, vendor, IDs).
  - *Power*: charger details with every power profile, system input / load / battery chart, per-port output chart. A segmented picker beside the title (under it when the column is narrow) picks the charts' range: 10 min (the live buffer, `PowerHistory`), 1 h and 24 h (saved minutes, §5.6) or 7 d (saved minutes averaged per 10 minutes). The range is not remembered between launches. Lines break at gaps longer than 30 s (10 min) or 2.5 points (other ranges), such as sleep or time Bus Stop was not running; a reading alone between two gaps shows as a dot. The time axis shows seconds for 10 min, hours and minutes for 1 h and 24 h, and weekday and date for 7 d. The system chart's header gives the range, plus "since <time>" when the readings start later than the range reaches. The minute in progress joins the saved ranges once it ends.
  - *Events*: reverse-chronological timeline of the saved event log (§5.6) with filters, grouped by day. The subtitle gives the number of events and when the oldest happened ("12 events since Oct 4, 09:15"). The filter menu offers All events, Problems (warning and critical findings and slower links) and each event kind. The filter menu and Clear sit beside the title, or under it when the column is too narrow for one row. An event's times sit beside its title, or under it when the title does not fit beside them on one line, so the title never breaks inside a word. Clear removes this Mac model's events from the saved history too, and with them the connection errors counted from them (§5.4 "Port health"). The sidebar's Events badge counts only events since launch.
  - *Diagnostics*: list of findings with explanations and suggested fixes. The severity chip sits beside a finding's title, or under it when both do not fit on one line.
- **Inspector** (trailing, toggleable): all known fields of the selected port, device or link, plus an "IORegistry keys" disclosure with raw values for power users. A dock's inspector has a "Built into this dock" section listing each built-in part (§5.4) with its name, vendor, speed and power; parts are not selectable, and searching for one finds the dock. A device that has dropped and come back, or runs slower than it has on this port, gets a "Connection history" section: reconnections in the last 10 minutes, its best link on this port, its current link, and the likely cause once it counts as flaky (§5.4 "Connection health"). A selected device or display that disconnects stays selected: the inspector says it is disconnected and shows it again when it returns, so a device that keeps dropping out can still be inspected. A device that becomes one of a dock's built-in parts selects the dock instead, and a port macOS stops reporting selects the Mac. A port's Health section gives the hardware's all-time Connections, Plug events and Overcurrent events counters, each with how many came in the last 7 days ("7 total · 2 in the last 7 days") and left out when the port lacks that counter, then liquid detections and connection errors in the last 7 days. The 7-day figures come from the saved history (§5.6), the totals from the hardware. It ends with the stands-out finding's explanation when the port has one (§5.4 "Port health").
- **Toolbar**: Refresh, Tree/Graph toggle, Export menu, Inspector toggle, search field.

### 3.4 Settings window

Toolbar tabs, each with an icon; the window takes the selected tab's name:

- **General**: Launch at login (SMAppService, with status and an "Open Login Items" fallback), show menu bar item, show Dock icon while a window is open, popover layout (cards / compact), hide empty ports, port order (physical / connected first).
- **Menu Bar**: icon style, text content, power units precision, pinned port (None or one of this Mac's ports) and what it shows (power, link speed, or both).
- **Appearance**: theme (Dark, the default; Light; Match System, which follows System Settings › Appearance), data colours (a preset, Lagoon by default, or Match System; §4.2), background opacity slider (60–100%, default 88%), glass tint strength, text size (S/M/L/XL), Reduce Motion override for link animation.
- **Notifications**: toggles for device connected, device disconnected, link downgraded, charger connected/disconnected, diagnostics.
- **Ports**: list of the Mac's ports with editable names and a "Reset names" button.
- **Advanced**: refresh cadence for power polling (1/2/5 s), a History section (§5.6: "Keep history between launches", on by default, which asks before turning off and deleting the file; size on disk, oldest entry and event count; "Clear History…" with a confirmation), show raw IORegistry keys in the inspector, demo mode toggle and scenario picker, export raw capture, open the project page.

### 3.5 Notifications

Local `UserNotifications`. Title names the device; body names the port and link, e.g. "Samsung T9 connected · Left Front · USB 3.2 Gen 2 @ 10 Gb/s". Downgrade alerts name both speeds. Rate-limited so a dock with 10 devices yields one grouped notification. New warning and critical findings, the connection health ones included (§5.4), notify under the diagnostics toggle, and each finding alerts at most once every 30 minutes.

### 3.6 Command-line tool

`busstop` (built alongside the app, also embedded in the app bundle at `Contents/Helpers/busstop`, because `busstop` and `BusStop` would collide in `Contents/MacOS` on a case-insensitive disk):

```
busstop                 # human-readable tree
busstop --json          # HostSnapshot as JSON
busstop --raw           # raw IORegistry capture as JSON (for bug reports / test fixtures)
busstop --watch         # print events as they happen (Ctrl-C to stop)
busstop --demo <name>   # run any of the above against a demo scenario
busstop --version
```

---

## 4. Visual design system: "Lagoon"

### 4.1 Principles

- Dark by default. Surfaces are black or near-black so the Mac's glass and the turquoise accent carry the light. In the light theme (Settings › Appearance › Theme: Light, or Match System on a light Mac), surfaces are near-white and ink carries the meaning; nothing glows. The theme is set on the whole app (`NSApp.appearance`), so every window, the popover and the system controls follow it, and a change applies at once to open windows.
- Liquid Glass is used for controls and navigation (header control cluster, toolbar, sidebar) and never for content cards, following Apple's HIG ("Don't use Liquid Glass in the content layer").
- Turquoise is the only accent. Status colours (amber, coral) appear only for warnings and errors.
- Legibility wins over translucency. The popover backing opacity is adjustable, and Reduce Transparency forces it to 100%.

### 4.2 Colour tokens

Each token has a Dark value and a Light value (`Lagoon.themed(dark, light)`), and resolves to whichever appearance it is drawn in. Dark is the default; Settings › Appearance › Theme picks Light or Match System. Dark values are frozen by `ThemeContrastTests`, which also holds the Light values to these minimum contrasts on `background`, `surface` and `surfaceRaised`: 12:1 for `textPrimary`, 6:1 for `textSecondary`, 4.5:1 for `textTertiary`, `accent`, status colours and chip text on its own tinted fill, and 3:1 for link and power strokes, `accentGlow` and chart series. The deliberately dim tiers (`accentMuted`, USB 2 links, no power) read at least as well in Light as in Dark. Card hairlines are exempt in both themes.

| Token | Dark | Light | Use |
|---|---|---|---|
| `background` | `#000000` | `#F6FAF9` | Window and popover base |
| `surface` | `#070D0E` | `#FFFFFF` | Cards |
| `surfaceRaised` | `#0D1719` | `#E9F2F1` | Hover, selected rows, inspector groups |
| `stroke` | `#3EE6D4` at 16% | `#096D68` at 18% | Card borders, separators |
| `strokeStrong` | `#3EE6D4` at 34% | `#096D68` at 40% | Highlighted and Increase Contrast borders |
| `accent` | `#3EE6D4` | `#096D68` | Turquoise: active states, links, primary text accents |
| `accentDeep` | `#0FA3A0` | `#08635E` | Fills behind accent text, pressed states |
| `accentGlow` | `#8AFFF3` | `#0A8F86` | Link pulses, fastest links, focus rings |
| `accentMuted` | `#1C5F5A` | `#5E9E97` | Inactive links, empty-port rings |
| `textPrimary` | `#EAFBF8` | `#0B1F1D` | Titles and values |
| `textSecondary` | `#9BBAB5` | `#3D5A56` | Labels and subtitles |
| `textTertiary` | `#5E7B77` | `#4D6763` | Hints, disabled |
| `powerIn` | `#7BF5B0` | `#166E3D` | Charging / power in |
| `warning` | `#FFC266` | `#8F5300` | Warnings |
| `critical` | `#FF6B7A` | `#B22436` | Errors |
| `onAccent` | `#000000` | `#FFFFFF` | Text and icons on accent fills |
| `linkHighlightMix` | `#FFFFFF` | `#000000` | What a hovered or selected link's core mixes toward |
| `pulseMix` | `#FFFFFF` | `#FFFFFF` | What power pulses mix toward |
| `shadow` | black at 50% | black at 15% | Under map tooltips |
| `well` | `#FFFFFF` at 6% | `#0B1F1D` at 6% | Faint fill behind small previews (menu bar icon tiles) |
| `menuBarBackdrop` | `#1B2A3A` to `#0E1A1C` | `#E4ECEB` to `#F2F6F5` | Stand-in menu bar in the Settings › Menu Bar preview |
| `menuBarItemHighlight` | `#FFFFFF` at 14% | `#0B1F1D` at 14% | Pressed-item highlight in that preview |

Every colour in the app comes from `Theme.swift` (`Lagoon` and `PowerChartPalette`). The only literals elsewhere are the wallpaper in the Appearance preview and the menu bar icon's template ink.

Link-speed ramp (colour and stroke width of topology links), Dark / Light: USB 1/2 `#3C5E5A` / `#7A9592` 1.5 pt; 5 Gb/s `#22A69B` / `#0B6961` 2 pt; 10 Gb/s `#3EE6D4` / `#005A52` 2.5 pt; 20 Gb/s `#5FF0E0` / `#004B44` 3 pt; 40 Gb/s `#8AFFF3` / `#003C37` 3.5 pt; 80 Gb/s and faster `#C9FFF9` / `#002E2A` 4 pt. In Dark the ramp gets brighter as speed rises and the two fastest tiers glow; in Light it gets darker and nothing glows.

Data colours (Settings › Appearance). The link-speed ramp above is the Lagoon preset, the default. Sky, Iris, Orchid, Ember, Tangerine, Citrine and Fern take Lagoon's shape (OKLCH lightness and chroma arc: muted at USB 2, most vivid around 10 Gb/s, washing toward white in Dark and toward ink in Light) at the hue of a macOS accent colour, and Graphite is the same arc without colour; the values live in `DataPalette`. Each preset also has the accent (links with no rate, active trunks), idle-trunk and pulse colours drawn with it, which for Lagoon are `accent`, `accentMuted` and `accentGlow`. Every preset meets Lagoon's Light targets (links and pulses 3:1, chip text 4.5:1 on its own tint) and reads at least as well as Lagoon in Dark. Match System uses the preset nearest the system accent colour (Graphite for Graphite, Sky for Multicolor's blue) and follows changes live. The palette applies to map links, pulses and the key, speed and transport chips, and the Mac Outline in Data mode; Power mode, the desktop widgets and the rest of the UI keep their colours. The warm presets overlap Power mode's heat ramp; see the roadmap.

Power ramp, Dark / Light: none `#636363` / `#858585`; under 5 W `#B6322D` / `#9B7300`; 5–15 W `#DE6129` / `#994A00`; 15–45 W `#EF9D32` / `#9A2B16`; 45 W and more `#F6D653` / `#831922`. Dark runs from deep red to gold and Light from gold to deep red, so more power always means more ink.

Power chart series, Dark / Light: system input `#0FA396` / `#00887B`, battery `#5E7CE2` / `#4A66CC`, system load `#45A86A` / `#2F8A50`, fourth port `#A56BD8` / `#8E52C2`, other ports `#7A8A88` / `#6B7A78`.

### 4.3 Typography

SF Pro via system fonts. Titles `.headline` semibold; values `.body` with `.monospacedDigit()`; chips `.caption` semibold with rounded design; machine name `.title3` bold. All sizes scale with the Text Size setting (90 %, 100 %, 115 %, 130 %) through the `lagoonFont` modifier and the `lagoonTextScale` environment value, because macOS does not scale text styles with `dynamicTypeSize`.

### 4.4 Materials and glass

- Popover: system popover glass in the app's appearance (`NSApp.effectiveAppearance`, kept in step with the app even while it is open, so a light or dark menu bar does not change it), a `background` backing at the user's opacity (default 88%) so a hint of wallpaper glass shows at the edges.
- Header controls: `GlassEffectContainer` with `.glassEffect(.regular.tint(accent.opacity(0.22)).interactive())` buttons.
- Topology window: the `background` token, true black in Dark. Where nothing scrolls under the toolbar (the map, the All Ports and All Devices tables, Events, and Diagnostics while it has no findings), the title bar is transparent, so the toolbar strip shows the window's background over the page and the inspector alike. The other pages (Power, the Mac Outline, the List view of the overview or a port, and Diagnostics with findings) keep the system's title bar, which hides or dims rows scrolled under it. Sidebar and toolbar controls are system glass; cards are solid.
- On macOS 27 SDK builds, AppKit glass views opt into the new interactive bounce (`NSGlassEffectView.effectIsInteractive`), guarded by `#if compiler(>=6.4)` and `#available(macOS 27, *)`.

### 4.5 Motion

- Link pulses: 1.6 s loop, speed-scaled, off under Reduce Motion.
- Device insert: fade and slide 8 pt, spring response 0.35.
- Removal: 1.5 s "disconnected" ghost state before the row disappears, so a flaky cable does not make the list jump.

### 4.6 Icons

- App icon: turquoise glass bus-stop sign with a port glyph, on a black continuous-corner squircle, art at 824 px inside a 1024 px canvas (Tahoe/Golden Gate margin).
- Device kinds use SF Symbols (`externaldrive.fill`, `display`, `keyboard`, `computermouse`, `iphone`, `cable.connector`, `powerplug.fill`, `headphones`, `camera`, `network`, `square.stack.3d.down.right` for hubs and docks).

### 4.7 Accessibility

VoiceOver labels on every card and graph node ("Left Front USB-C port, Samsung T9 connected at 10 gigabits per second, 4.5 watts"). Full keyboard navigation in the popover and window. Respects Reduce Motion, Reduce Transparency, Increase Contrast.

---

## 5. Architecture

### 5.1 Modules (Swift Package, tools 6.2, macOS 26+)

| Target | Platforms | Responsibility |
|---|---|---|
| `BusStopCore` | macOS | Pure Swift. Raw capture model (`RawSnapshot`), output model (`HostSnapshot`), `TopologyBuilder`, port labelling and catalogue, formatters, diagnostics, event diffing, power history, the saved history's format (`HistoryArchive`), export, demo scenarios. No IOKit, AppKit or SwiftUI. Fully unit-tested. |
| `BusStopKit` | macOS | IOKit capture (`RegistryCapture` → `RawSnapshot`), live monitoring (`LiveMonitor`: IOKit notifications, power-source notifications, display reconfiguration, power polling), SMC power channel reader, machine info. |
| `BusStopUI` | macOS | SwiftUI views and theme shared by the app and the widgets: `Lagoon`, chips and badges, device rows, power charts, the widget views. Reads no hardware. |
| `BusStop` | macOS | The app: AppKit status item and popover, SwiftUI views, settings, notifications, launch at login, the widget payload writer. |
| `BusStopWidgets` | macOS | The desktop widget extension, sandboxed. Decodes the payload the app writes; never reads hardware. |
| `busstop` | macOS | Command-line tool. |
| `BusStopCoreTests` | macOS | Unit tests with fixtures. |

### 5.2 Data flow

```
IOKit / IOPS / SMC / CoreGraphics
        │  (BusStopKit.RegistryCapture, background queue)
        ▼
   RawSnapshot  ── Codable, platform-neutral, exportable as "raw capture"
        │  (BusStopCore.TopologyBuilder, pure function)
        ▼
   HostSnapshot ── ports → device trees, power summary, diagnostics, displays
        │  (BusStopCore.HistoryArchive.record: power minutes, port counter deltas)
        │  (BusStopCore.HistoryArchive.portHealth → ports: for DiagnosticsEngine)
        │  (BusStopCore.ConnectionHealth.observe → extra findings for DiagnosticsEngine)
        │  (BusStopCore.SnapshotDiffer)
        ├──► [ConnectionEvent] → event log (HistoryArchive), notifications
        ▼
   PortStore (@Observable, @MainActor) → SwiftUI views, status item text
```

- `LiveMonitor` triggers a full capture on any IOKit match/terminate/interest notification (debounced 250 ms, a burst never delays a capture by more than 1 s), on power-source and display changes, and when the popover or a window appears. Between those, a power-only capture keeps the menu bar text current: it re-reads the battery service and SMC power and copies everything else, port counters included, from the last capture. It runs on a timer (every 2 s while UI is visible, every 10 s otherwise) and on `AppleSmartBattery` interest. A capture is full whenever the last full one is more than 60 s old.
- Every capture pushes the next poll back one interval. While the screens sleep or another user's session is active, polling stops and battery interest is ignored; other notifications still capture, and resuming runs one full capture.
- Captures run on one serial background queue and never overlap. Results are delivered to the main actor.
- Demo mode swaps the capture source for `DemoScenarios`, which produce `RawSnapshot` values, so the same builder path is exercised.
- `PortStore` records each new capture into its `HistoryArchive` once: a settings change or a port rename rebuilds from the same capture and records nothing. New events are appended to the archive, and the event log the views show is this Mac model's section of it (§5.6).
- Each new capture also goes to `ConnectionHealth` once, before diagnostics are evaluated; its findings are passed to `DiagnosticsEngine.evaluate(…, extra:)` and reused when the same capture is rebuilt. The first capture after launch, wake, a change of source or a clock set back is marked as after a gap, and so is every capture between `willSleepNotification` and `didWakeNotification`, since a capture can arrive before the wake notification. `ConnectionHealth` alone also takes the first capture after the screens wake as a gap, since many monitors drop off while the screens sleep. `busstop --watch` marks only its first capture.

### 5.3 Raw capture (`RawSnapshot`)

Each record keeps its IORegistry properties as a `PropertyBag` (`[String: PlistValue]`), so new keys never need a schema change and fixtures can be captured from real Macs with `busstop --raw`.

- `machine`: `hw.model`, `hw.targettype`, OS version, whether a battery is present.
- `portNodes`: every node in the `IOPort` registry plane (macOS 26+) plus all `IOAccessoryManager` / `IOPort` services found by class matching, each with `parentID`, class name, name, location and properties. This covers ports, transport states (`IOPortTransportStateCC/USB2/USB3/DisplayPort/CIO`), features (`IOPortFeaturePowerIn`, `IOPortFeaturePowerSource`, LDCM), PD components (SOP, SOP', SOP'') and Apple charger identity (`IOPortTransportProtocolAppleUVDM`).
- `hpmControllers`: `UUID` of each port's parent HPM device (join key for SMC channels).
- `usbDevices`: every `IOUSBHostDevice` with derived ancestry: nearest parent USB device, controller class chain, `UsbIOPort` path, `usb-drdN` `port-number`, and the IOPort-plane transport it hangs under.
- `thunderboltSwitches`: every `IOThunderboltSwitch*` with its `IOThunderboltPort` children, parent switch and `acioN` index.
- `battery`: selected `AppleSmartBattery` keys (`AdapterDetails`, `PowerTelemetryData`, `PowerOutDetails`, `PortControllerInfo`, `ExternalConnected`, `IsCharging`, `FullyCharged`, `CurrentCapacity`, `MaxCapacity`, `NotChargingReason`, `BatteryInstalled`).
- `adapter`: `IOPSCopyExternalPowerAdapterDetails()`.
- `smcChannels`: per-port live power from SMC keys `DxUI`, `DxJV`, `DxJI`, `DxPR` (x = 1…4).
- `displays`: CoreGraphics online displays with vendor, model, serial, resolution, refresh and built-in flag.

### 5.4 Topology rules (`TopologyBuilder`)

**Ports.**
- A port is a node with `PortTypeDescription` and `PortNumber` and without `ParentPortType`. Skip `BuiltIn == false` (inductive, virtual).
- Kind from `PortTypeDescription`: "USB-C", "MagSafe 3"/"MagSafe", "USB-A", "HDMI"; fallback `PortType` (2 USB-C, 17 MagSafe 3, 6 HDMI).
- Stable key `"<PortType>/<PortNumber>"`; MagSafe and USB-C can share a number.
- Connected: `ConnectionActive`, or any active non-CC transport, or any attributed device.
- Active transports: `TransportsActive` intersected with transport nodes whose `Active == Yes` and `Tunneled == No`. `IOAccessoryUSBSuperSpeedActive` is ignored (it goes stale).

**Labels.**
1. User override (keyed by `hw.model` + port key).
2. The Mac's own `port-location` ("back-left"), read from the device-tree node that drives the port (an `hpmN` controller, up to four `IOService` levels above the port) when that node's `port-number` is the port's or it has none. It is written in the catalogue's words: a desktop face then a qualifier ("Rear (left)", "Rear (center)"), or a laptop side then a place along it ("Left Rear"). Unknown words are kept, capitalised. Ports without it (the plain USB ports of a Mac mini, older Macs) go on to step 3.
3. Catalogue entry for `hw.model` with matching connector and number.
4. Catalogue entry by rank among same-connector ports (non-contiguous numbering such as {1, 2, 4}).
5. Capability heuristic on compact desktops and on models whose rows mix Thunderbolt and plain USB-C: "Rear" for Thunderbolt ports and "Front" for the others, when the catalogue's rows (or, for an unlisted Mac mini, the model alone) say so.
6. Generic "USB-C 2", "MagSafe", "HDMI".

Ports that steps 2 to 5 give the same title are numbered in port order, which follows the hardware or catalogue placement where there is one and the port number otherwise: "Front · USB-C 1", "Front · USB-C 2". User and generic names are never numbered.

The location from steps 2 to 5 is also kept apart from the label, as `PhysicalPort.catalogLocation`, so a renamed port keeps its place. `ChassisLayout` turns it into a face of the Mac (left, right, front, rear) and an order along it: laptop sides read "Rear/Center/Front"; desktop qualifiers ("leftmost" to "rightmost") order the rows of one connector. Catalogue rows for connectors macOS does not report (Ethernet, the power inlet, some SD slots) become passive slots. A port with no readable location is left unplaced.

**USB device attribution** (most to least reliable):
1. `UsbIOPort` path on an ancestor; parse the last path component `Port-<Type>@<hex>`.
2. IOPort-plane parent transport's `ParentPortType` / `ParentPortNumber`.
3. Thunderbolt tunnel: controller chain contains `AppleUSBXHCITR` or a dock xHCI; follow `apciecN` ↔ `acioN` ↔ host switch lane `Socket ID` = port number.
4. `usb-drdN` `port-number`.
5. Otherwise "Unattributed" (shown in an "Other devices" section). Internal devices behind `usb-auss` / `AppleUSBXHCIAUSS` and Apple internal hubs (`USBPortType == 2`) are excluded.

**USB device tree.** Parent = nearest `IOUSBHostDevice` ancestor. Hubs are `bDeviceClass == 9`. A USB 3 hub and its USB 2 companion are shown as one hub when both are present: same vendor and a matching name on the same physical port, and below the first level also the same downstream port and tier depth. Which half is which comes from the negotiated link speed, or from the declared USB version (`bcdUSB`) when there is no speed. At the first level, candidates are ranked by name, then by sharing the USB 3 half's host controller (top byte of `locationID`), then by product ID apart from its top four bits (VIA numbers the halves 0x0822 and 0x2822). When the best candidates still tie, nothing is merged. A first-level pair from different vendors (a Thunderbolt 5 dock's Intel USB 3 hub and its Fresco Logic USB 2 hub) merges only when it is the one pair whose child hubs are companions themselves. Trees are cut at 32 levels and Thunderbolt chains at 64 to stay safe on malformed captures.

**USB vendor names.** A device's vendor name is its own `USB Vendor Name`, else `kUSBVendorString`; empty strings and placeholders such as "xxxxxxxx" count as missing. When a device has a vendor ID but no name of its own, the name comes from a table of USB vendor IDs that is built into Bus Stop, generated from the USB ID Repository's `usb.ids` by `scripts/generate-usb-vendors.py` and used under the 3-clause BSD License. The table holds vendors only, not products. A device's own name always wins: the table fills in names only after a USB 3 hub and its USB 2 companion are merged, so the merged hub keeps either half's own name. Bus Stop never fetches the list at run time.

**Speed.** `UsbLinkSpeed` (bits/s) first; else `Device Speed` (0 Low 1.5 Mb/s, 1 Full 12 Mb/s, 2 High 480 Mb/s, 3 SuperSpeed 5 Gb/s, 4 SuperSpeed+ 10 Gb/s, 5 SuperSpeed+ 20 Gb/s); else `USBSpeed` (`tIOUSBHostConnectionSpeed`: 1 Full, 2 Low, 3 High, 4 Super, 5 Super+, 6 Super+ 2x2). Never mix the two enums.

**Device power.** `UsbPowerSinkAllocation` (mA at 5 V) → mW = mA × 5. Legacy `Requested Power` ×2 mA as last resort. Hub roll-up = own allocation + descendants; hubs with `kUSBHubPowerSupply > 0` are marked self-powered and their downstream draw does not count toward the port. A dock's built-in parts count as they did in the tree: roll-ups follow `internalParentID`, so a self-powered built-in hub still stops the roll-up for the devices behind it.

**Thunderbolt / USB4.**
- Link rate per lane from `Current Link Speed`: 0x8 → 10 Gb/s, 0x4 → 20 Gb/s, 0x2 → 40 Gb/s (Linux `tb_regs.h` codes). 0 means idle.
- Lanes from `Current Link Width` bitmask: 0x1 one, 0x2 two, 0x4 / 0x8 asymmetric (three lanes one way, one the other). A host port's link comes from its lanes that report a non-zero `Link Bandwidth` when it has any: on a bonded USB4 v2 link the idle second lane can report an asymmetric width with a bandwidth of 0.
- Label from total rate: 80 Gb/s and up "USB4 v2 / TB5", 40 Gb/s "Thunderbolt / USB4", 20 Gb/s "Thunderbolt / USB4 @ 20 Gb/s", 10 Gb/s "Thunderbolt @ 10 Gb/s". Never infer a protocol name from the speed code alone.
- Chain: switch `Depth` and parent switch. Host-root lane port `Socket ID` = physical port number. Downstream switches become `DeviceNode`s of bus `.thunderbolt` with `Device Vendor Name` / `Device Model Name`.
- A USB-C port takes one plug, so when a Thunderbolt chain is attached, every USB device on that port reaches the Mac through it. A tunnelled USB device goes under the chain device whose model name it matches (exactly one match), else under the only chain device with a live USB tunnel. Anything else, including the USB 2 half of a dock's hub (it arrives on the cable's own USB 2 pair), goes under the head of the chain, the device the cable is plugged into, which is always a true ancestor. When the port has several chain heads and no other evidence, the device stays at port level. A display tunnelled through the chain (a dock's DisplayPort output) goes under the head of the chain on the same terms.

**Built-in dock parts.** A Thunderbolt 5 dock tunnels its USB hub to the Mac's own USB controller, so its root hub, its internal hubs and its own USB functions appear in the registry as USB devices like any other. They are moved out of the dock's `children` into `DeviceNode.internalParts` (`DockParts`), so the map, the list and the command-line tree show one dock card, with the devices plugged into the dock's ports hanging off it. A device moved up to the dock records the part it hangs off in `internalParentID`, and so does a part below another part; `DeviceNode.unfolded()` rebuilds the original tree. The rules only apply to a dock that heads its port's tree and is the port's only switch with a live USB tunnel, and they work top-down, so a device is built in only when what it hangs off is built in:
- A. *Root hub*: a USB hub directly below the dock, on the Mac's own xHCI (`AppleT…USBXHCI`, not a tunnelled or dock controller), with `UsbTunnel` true, when it is the only `UsbTunnel` USB root on the port. A merged USB 2 half goes with it.
- B. *Identity*: a USB device whose `idVendor` / `idProduct` equal the dock switch's `Device Vendor ID` / `Device Model ID` (the dock's own IDs; the switch's `Vendor ID` / `Device ID` are the chip's), both 1 to 0xFFFF, when no other switch reports the same pair.
- C. *Captive*: a hub or billboard (`bDeviceClass` 0x11, or only class 0x11 interfaces) with `USBPortType` 1 (both halves of a merged hub), on a hub folded by C or D. Not on the root hub's ports: root ports report 0 for every device, the dock's own included, so their flags are not evidence.
- D. *Identity holder*: a hub with a B device on a captive port. When more than one hub in the dock qualifies, B and D are both off.
- E. A device that is not a hub, on a hub folded by C. Hubs on such a hub stay, with everything behind them.

Anything that matches no rule moves up to the dock with its subtree. Every rule fails closed: without `UsbTunnel` (Thunderbolt 3 and 4 docks bring their own PCIe xHCI), with a second tunnelled root or a second switch with a live USB tunnel (daisy chains), or without a valid, unique dock identity, less or nothing folds. Rule E would hide a device plugged into a dock port that is wired to a captive internal hub; hubs on such a port stay visible. Device counts (`descendantCount`, `PhysicalPort.deviceCount`, `HostSnapshot.deviceCount`) count drawn devices only. Power roll-ups and the USB 2 fallback and hub budget diagnostics read the unfolded tree, so a built-in hub still explains the devices behind it; its finding points at the dock. A device that becomes a part or stops being one raises no connect or disconnect event, and a part's link changes are reported against the dock. See `docs/decisions.md` (2026-10-14).

**Power.**
- Charger: `AdapterDetails` / IOPS adapter: `Name`, `Manufacturer`, `Watts`, `AdapterVoltage` (mV), `Current` (mA), `UsbHvcMenu` (PDOs, keys `MaxVoltage`/`MaxCurrent` or `Voltage`/`Current`), `UsbHvcHvcIndex` (active PDO), `IsWireless`.
- Which port the charger is on, strongest evidence first: an `IOPortFeaturePowerSource` with a winning option (when several ports have one, the `[*]`-marked source wins, then the one within 5 % of the adapter's watts, then the most power; a remaining tie leaves the charger without a port), then a connected MagSafe port, then `FeaturesEnabled` containing "Power In", then an Apple charger identity (`AppleUVDM` "User String").
- System input: `PowerTelemetryData.SystemPowerIn` (mW), `SystemLoad`, `BatteryPower`.
- Per-port output, best source first: SMC `DxJV × DxJI` joined by HPM `UUID` = `DxUI`; then `PowerOutDetails[].Watts` (mW) joined by `PortIndex` = USB-C port number; then the sum of USB allocations.

**Displays.** A display is attached to a port through `IOPortTransportStateDisplayPort` (`ProductName`) or a Thunderbolt "DP or HDMI Adapter" with a non-empty `Hop Table`. If exactly one port carries video and exactly one external display is left, it goes there. Several remaining displays go to the single video port only when that port shows enough display links for all of them (DisplayPort transports or live Thunderbolt display tunnels). Otherwise displays without a confident port are listed under "Other displays". Software displays, which no framebuffer publishes (Sidecar, AirPlay, virtual displays, DisplayLink), are dropped before attribution, so they never reach a port or "Other displays".

**Diagnostics.**

| Rule | Condition | Severity |
|---|---|---|
| USB 2 fallback | USB device with `bcdUSB ≥ 0x0300` running at ≤ 480 Mb/s, on a port that supports USB3 | Warning |
| Thunderbolt bottleneck | Supported link speed mask allows a faster code than the current one on both ends | Info |
| Slow charger | Charger watts < 30 W on a laptop with `IsCharging == false` and `ExternalConnected` | Warning |
| Not charging | `NotChargingReason != 0` while connected | Info |
| Hub over budget | Bus-powered hub whose descendants allocate more than 4.5 W (USB 3) / 2.5 W (USB 2) | Warning |
| Deep chain | Thunderbolt depth > 5 | Info |
| Liquid detected | `LDCM_LiquidDetected == Yes` | Critical |
| Overcurrent | `Overcurrent Count` went up in the last 24 hours, from the saved history (§5.6), so the warning survives a relaunch; the text gives the count for the last 7 days | Warning |
| Flaky connection | One device disconnected and came back on the same Mac port 3 or more times in 10 minutes (Connection health, below) | Warning |
| Link flapping | A USB or Thunderbolt link changed direction (faster, slower) 3 or more times in 10 minutes on the same port, not counting the 15 seconds after a gap | Warning |
| Speed regression | A USB or Thunderbolt device runs slower than its best link this session on the same Mac port in the same hub socket, which supports USB 3 or Thunderbolt, and USB 2 fallback does not already name it | Warning |
| Port stands out | Over the last 7 days, a port with at least 5 connections and 3 connection errors has at least 3 times the errors per connection of the median of the Mac's other ports of the same kind that had at least 5 connections too (at least 2 of them; the median counts as at least 0.05) (Port health, below) | Info |

**Connection health** (`ConnectionHealth`, fed every new capture once, in order). Devices are followed by `DeviceIdentity`, so a device keeps its identity when it comes back on another controller: a USB device with a plausible serial (not empty, not all zeros, never seen on two devices at once) by vendor, product and serial; one without by vendor, product, Mac port and route (the `locationID` without its controller byte); a hub by vendor, name (without speed words) and depth on the Mac port, so it keeps its identity when it loses its SuperSpeed half; Thunderbolt devices and displays by their ids. A key two devices would share is dropped. Identities stay in memory and never reach the file, an event or a finding id.
- A *cycle* is a device leaving and coming back to the same Mac port. A leave counts only for the top-most device of what left together, after the device had been present for 2 seconds (a dock enumerating in stages), and not within 15 seconds of a gap (launch, wake, change of source), when devices re-enumerate. A device that comes back on another port moved, and one that comes back more than 10 minutes after it left was away; neither is a cycle. On a Mac port whose devices did not change, half the increase in `Plug Event Count` between two back-to-back readings adds cycles to the device plugged into it, because a replug can be faster than a capture; at most 2 per capture, so one bad reading cannot raise a finding by itself. A capture dated before the last one (a clock set back) clears everything on record.
- A finding stays until its 10-minute window has had no new cycle or reversal, so it does not toggle; a speed regression stays until the link is back or the device is gone. Finding ids are fixed at first raise: `flakyConnection:<device id>`, `flakyConnection:port:<port key>`, `linkFlapping:<device id>`, `speedRegression:<device id>`. A dock's built-in part is reported as the dock.
- The likely culprit, in the finding's text ("Likely cause: the cable."): the device when it cycled on two or more Mac ports; the hub when two or more devices behind one hub that stayed connected each raised a flaky finding, mentioning power when the hub is bus-powered; the port when three or more devices plugged straight into it each raised one there and cycled on no other port, mentioning liquid or overcurrent when the port reports them; otherwise the cable, then the device.
- DisplayPort links are left out, since they retrain on a mode change or wake, and Thunderbolt 5 Bandwidth Boost (80 ↔ 120 Gb/s) is not a change (`SnapshotDiffer.linkChange`).

**Port health** (`HistoryArchive.portHealth`, read from the saved history before diagnostics are evaluated). For each port, over the last 7 local calendar days (today and the 6 before): the increases in Plug Event Count, ConnectionCount and Overcurrent Count, liquid detections, the time of the last overcurrent increase, and *connection errors* from the event log: a device that left the port within 10 seconds of connecting to it (not when the clock was set back in between), a slower USB or Thunderbolt link (DisplayPort retrains on mode changes and wake), and a USB 2 fallback finding (a slowdown and the fallback it raises in the same capture count once, each part of a dock counts on its own, and a device's fallback counts once per port, since it returns on every plug-in when the cable is the cause). Overcurrents are not connection errors, so a port is never reported twice for them. The all-time totals the inspector shows are the hardware counters themselves. The stands-out rule never compares ports of different kinds or different Macs, and its finding is info only, so it never notifies. `PortControllerInfo` error counters (HardReset, ShortDetect, VdoFail) are not used: which port each one belongs to is not verified.

### 5.5 Threading and safety

- All IOKit work happens on one serial queue owned by `LiveMonitor`. Notification ports use `IONotificationPortSetDispatchQueue` on that queue.
- Per-key `IORegistryEntryCreateCFProperty` reads for volatile nodes (transport states, USB devices), to avoid crashes reported with bulk reads during teardown.
- Every `io_object_t` is released. Iterators are checked with `IOIteratorIsValid` and re-walked if invalidated.
- Keys starting with `Apple` are not API; every read tolerates missing keys and wrong types.
- The UI layer is `@MainActor`; core types are `Sendable` value types. Lagoon's dynamic colour providers are `nonisolated` and `@Sendable`, because AppKit resolves colours on any thread.

### 5.6 Persistence

Settings, port renames, menu bar pins and window frames are in `UserDefaults`. History is saved in `~/Library/Application Support/io.github.static74.busstop/history.json` (the folder name is fixed, since `swift run` has no bundle identifier). Apart from the widget payload (§6), nothing else is written unless the user exports.

- **What is kept**, in one section per Mac model (`hw.model`): the event log (newest 5,000 events, none older than 30 days); power averaged per minute (system input, battery, system load and each port's watts) for 7 days; each port's increases in Plug Event Count, ConnectionCount and Overcurrent Count, and liquid detections, per local calendar day for 90 days; and the time of each port's last overcurrent increase. The file is capped at about 5 MB by dropping the oldest entries. A clock set back drops the saved power and port days dated after it. After the clock steps forward by more than a day, ages are measured from the last capture before the step, for every Mac model, until the clock has held for a day, so a clock set wrongly ahead and then put right does not wipe the history, and a Mac used only every few days is still trimmed one session late. A clock left wrong across a gap of more than a day is trusted: the wall clock is the only time Bus Stop saves, so it cannot tell that step from a long sleep. The popover's sparklines and the Power page's 10-minute range use the in-memory 10-minute buffer (`PowerHistory`); the Power page's 1 h, 24 h and 7 d ranges read the saved minutes (§3.3).
- **Counting.** A counter increase is counted only between two captures Bus Stop saw back to back. The first capture after launch, wake, a change of source or the clock being set back counts nothing, and so does any capture between sleep and the wake notification, so changes while Bus Stop was not watching are not attributed to the wrong day. A counter that goes down counts nothing and keeps its earlier value as the baseline, so one low reading does not count the whole count again when it comes back; a real reset comes with a reboot or wake, which is already a gap. Gaps are signalled by the app, not inferred from time: while the screens sleep, captures come only on hardware changes and can be hours apart, and their deltas still count.
- **Saving.** A serial background queue writes the file atomically: new events at most every 5 minutes (within a minute after a quiet spell), power-only changes every 15 minutes, and at once when the Mac goes to sleep and when Bus Stop quits. The folder is mode 0700 and the file 0600.
- **Reading.** The file is read once at launch, straight into the store; restored events never notify. An entry that does not decode (an event kind from a newer version) is dropped on its own. A file that cannot be read is renamed `history-corrupt-<ms>.json` and a new one is started. A file written by a newer version is left untouched and never overwritten; Settings says so.
- **Demo mode** never reads, shows or writes the saved history, including when Bus Stop launches straight into demo mode. Entering demo mode saves the live history and sets it aside; it comes back when demo mode ends. Each demo scenario starts with an empty history of its own.
- **Turning it off** ("Keep history between launches") deletes the file, corrupt copies and a newer version's file included; that session's history stays in memory only, and turning it back on starts an empty history rather than saving it again. Launching with `-keepHistory NO` neither reads nor writes the file for that launch; it stays on disk. Turning it on mid-session reads the file and keeps that session's events. Clear History deletes it for every Mac model.
- `busstop --watch` keeps nothing between runs and never touches the file. It keeps an archive in memory for the run, so the overcurrent and stands-out rules work the same way.

---

## 6. Privacy and security

- No network code, no analytics, no crash reporting. The app does not request the network client entitlement.
- Reads only: IORegistry properties, the power-source API and the SMC read selectors.
- Unsandboxed, with the hardened runtime. Pull request builds are signed ad hoc; releases are signed with a Developer ID and notarized. Users who build from source run their own binary.
- The saved history (§5.6) stays on the Mac, readable only by the user's account (mode 0600). It records the Mac's model identifier (`hw.model`), never its serial number or computer name. Like port names, it is not redacted: event titles carry device names, and event ids carry display serial numbers (`display:<vendor>:<product>:<serial>`) and Thunderbolt device UIDs (`tb:<UID>`). Clear History, or turning "Keep history between launches" off, deletes it.
- The desktop widgets never read hardware: the extension is sandboxed, and the app hands it a payload, `widget-payload.json` in the App Group container `<team>.io.github.static74.busstop` (`~/Library/Group Containers/`). The app writes it atomically, readable only by the user's account (mode 0600). It holds the snapshot through the same redaction as exports, without the raw IORegistry properties, so it carries no serial numbers; device and port names stay. It also holds the last 10 minutes and 24 hours of power, the newest 20 events and each port's health over 7 days. Clear History, or turning "Keep history between launches" off, deletes it, since it holds events; with history off, the payload written afterwards leaves out the events, the 24-hour power and the port health. An ad hoc build has no team, so no App Group and no payload.
- Device serial numbers are shown in the inspector and included in exports; the export sheet has a "Redact serial numbers" option (on by default). Redaction also replaces per-unit identifiers: Thunderbolt router UIDs (also inside `tb:` device ids), HPM controller and SMC channel UUIDs, USB and DisplayID container IDs, `ConnectionUUID`, EDID and DisplayID serial fields, and the computer name. A known serial number is also removed wherever it appears as a whole word in names, diagnostic text and property strings, since some devices put it in their product name. EDID data shorter than one 128-byte block, and bytes after the last whole block, are dropped, and a DisplayID block whose structure cannot be walked is blanked, because their serial fields cannot be found. Stand-ins keep their shape so a redacted raw capture still builds the same topology. `busstop --watch`, the CLI's text tree and "Copy Details" apply the same redaction.

---

## 7. Build, packaging and distribution

- `swift build` builds everything; `swift test` runs the core, Kit and app tests.
- `scripts/build-app.sh` assembles `build/Bus Stop.app` (Info.plist with `LSUIElement`, icon, embedded CLI), signs it (ad hoc, or with the identity in `SIGN_IDENTITY`) and zips it. `scripts/make-dmg.sh` packs the app and a link to `/Applications` into `build/BusStop.dmg`. `scripts/notarize.sh` has Apple notarize the zip or the disk image and staples the ticket to the app or the image.
- `scripts/install.sh` builds and copies the app to `/Applications`. A locally built app carries no quarantine attribute.
- GitHub Actions, on pull requests:
  - `macos-27`: `xcode-27` runner (macOS 27, Xcode 27, Swift 6.4), build, test, assemble the app, run the CLI against demo data and the live (virtual) machine, upload the zip. Runs only when the workflow is started by hand, because the runner is paid.
  - `macos-26`: `macos-26` runner with Xcode 26.6 for backward compatibility.
- Releases: tagged builds attach `BusStop.dmg`, with the app and the image each signed with the Developer ID, notarized and stapled. Without the signing secrets the release workflow signs ad hoc, and the release notes explain "Open Anyway" in System Settings › Privacy & Security.

---

## 8. Testing

- Unit tests in `BusStopCoreTests` cover: `PlistValue` coding, property accessors, speed and power formatting, port parsing, label resolution (exact, rank fallback, user override), USB attribution order, hub roll-ups, Thunderbolt link decoding, charger and PDO parsing, per-port power joins, diagnostics, event diffing, the history archive (caps, local-day counter deltas, lossy decoding, newer-schema refusal), the power history window, chassis layout, device identity, connection health and port health, demo scenarios, JSON export round-trip. `BusStopAppTests` covers saving, restoring and clearing history with a temporary folder, including that demo mode leaves the file byte-identical, plus event grouping and the Problems filter, the pinned menu bar port, the Mac Outline (paint, search, spacing, and a narrow window in `TopologyWindowLayoutTests`), notifications and the power chart's series. `ThemeContrastTests` resolves every Lagoon colour in both appearances: Dark matches its frozen hex values and Light meets the §4.2 contrast targets; `ThemeSettingTests` covers the theme setting.
- Fixtures are hand-built from real public IORegistry dumps (macOS 26.3 MacBook Neo `IOPort` plane, macOS 27 MacBook Air M2 `AppleSmartBattery`, Thunderbolt `system_profiler` captures) and from the demo scenarios. Redacted `busstop --raw` captures from real setups are kept as JSON test resources (`Tests/BusStopCoreTests/Fixtures/*.json`).
- CI runs the CLI on the macOS runner (a virtual machine with few accessories) to prove that live capture does not crash and produces valid JSON.

---

## 9. Decisions log

The project was specified and built without a product owner in the loop. These are the defaults chosen and why.

| Question | Decision | Reason |
|---|---|---|
| Physical or network ports? | Physical | ViewPorts maps USB-C/Thunderbolt ports, devices and power |
| Minimum macOS | 26.0, designed and tested for 27 | Xcode 26.6 users can still build; macOS 27 APIs are guarded |
| MenuBarExtra or NSStatusItem? | `NSStatusItem` + `NSPopover` hosting SwiftUI | Needs right-click menu, live text, reopen behaviour, popover appearance control |
| Xcode project or SwiftPM? | SwiftPM plus a bundling script | No project file to maintain, builds identically in CI and locally |
| SMC power reading | Included, optional, fails closed | It is the only live per-port output source on many Macs |
| App Intents | Deferred | Need App Intents metadata that SwiftPM does not generate |
| Homebrew | Not in v1 | Homebrew disabled unsigned casks in September 2026 |
| Licence | MIT | Matches the repository; MIT-licensed references (WhatPort, WhatCable, PortScope) and the USB ID Repository's vendor list (used under its BSD-3-Clause option) are credited in `THIRD_PARTY_NOTICES.md`; no GPL code used |
| Appearance | Dark by default; Light and Match System in Settings › Appearance | The requested look is true dark; a light option serves people who run macOS in light mode |

---

## 10. References

- ViewPorts: https://viewports.app/ (search snippets only)
- Apple, Liquid Glass and SwiftUI: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views, https://developer.apple.com/documentation/swiftui/glass, https://developer.apple.com/documentation/appkit/nsglasseffectview
- macOS 27 release notes: https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes
- WWDC26 Platforms State of the Union: https://developer.apple.com/videos/play/wwdc2026/102/
- HIG Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- IOUSBHostFamily definitions: `IOUSBHostFamilyDefinitions.h` (Apple SDK)
- IOPS keys: https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPSKeys.h
- Linux Thunderbolt registers: https://github.com/torvalds/linux/blob/master/drivers/thunderbolt/tb_regs.h
- WhatPort (MIT): https://github.com/darrylmorley/whatport
- WhatCable (MIT): https://github.com/darrylmorley/whatcable
- PortScope (MIT, port-location catalogue): https://github.com/azenla/portscope
- USB ID Repository (GPL-2.0-or-later or BSD-3-Clause, used under BSD-3-Clause; USB vendor names): http://www.linux-usb.org/usb-ids.html
- GitHub Actions runner images: https://github.com/actions/runner-images
