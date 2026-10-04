# Bus Stop: product and technical specification

Version 1.0 (October 2026). Status: implemented in this repository.

Bus Stop is a free, open-source (MIT) macOS menu bar utility that shows every physical port on a Mac, what is plugged into each one, how fast each link runs, and how much power flows through it. It is an open alternative to the commercial ViewPorts app ("See what's connected", $6.99, macOS 26+), rebuilt from public information and original code, and designed for macOS 27 "Golden Gate" with a turquoise-on-true-black Liquid Glass look.

---

## 1. Goals and non-goals

### Goals

1. Show a live map of the Mac's physical ports: USB-C / Thunderbolt, MagSafe, USB-A, HDMI.
2. For each port, show what is connected (hubs, docks, displays, drives, chargers, phones, input devices), the negotiated link speed, and power in or out.
3. Show the full device chain: hubs, docks and daisy-chained Thunderbolt / USB4 devices, with every device labelled by the port it ultimately hangs off.
4. Roll power and device counts up to each hub and to the host.
5. Detect plug and unplug events instantly and keep a short event history.
6. Stay 100% local. No network access, no telemetry, no accounts.
7. Look at home on macOS 27: Liquid Glass controls, true black surfaces, turquoise accent.
8. Be easy to build from source with nothing but Xcode 27 (or Xcode 26.6) and SwiftPM.

### Non-goals (v1)

- Network ports, Wi-Fi, Bluetooth, AirPlay, VPNs. Bus Stop is about physical connectors only.
- Intel Macs. macOS 27 runs only on Apple silicon. Bus Stop builds for macOS 26+ and will run on an Intel Mac with macOS 26, but port-controller detail is unavailable there and the app says so.
- Mac App Store distribution. The App Sandbox blocks parts of the IOKit access Bus Stop needs (SMC power channels, some notifications).
- Widgets and App Intents. Both need an Xcode project, a team ID and App Group signing, which conflicts with a zero-setup open-source build. A command-line tool (`busstop`) covers scripting instead.
- Changing anything. Bus Stop is read-only: it never ejects, powers off or reconfigures a port.

---

## 2. Feature inventory

### 2.1 Parity with ViewPorts

Public description of ViewPorts (search snippets of viewports.app; the site itself, its screenshots and the r/macapps launch thread were not reachable from the build environment):
"macOS menu bar utility that maps every port, device, and power draw on your Mac, with live topology, hub and daisy-chain support, and link speeds — all local, no telemetry."

| ViewPorts feature | Bus Stop implementation |
|---|---|
| Live port data in the menu bar | Status item with icon plus optional live text (total watts, device count, or both) |
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

- Physical port names from a per-model catalogue ("Left Rear", "Right Center"), with user renaming.
- Charger card: name, rated watts, active PD contract (volts and amps), full list of offered power profiles.
- Cable information when the port exposes it: active or passive, optical.
- Diagnostics with plain-English explanations:
  - device running at USB 2.0 on a port that supports USB 3 or better
  - Thunderbolt link slower than both ends support (cable bottleneck)
  - charger below the Mac's needs, or not charging
  - bus-powered hub over its power budget
  - deep daisy chain
- Event timeline (connect, disconnect, speed change, charger change) with timestamps.
- Power sparkline for system input and per-port output over the last few minutes.
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
- Optional text next to the icon, monospaced digits: none, total power ("38 W"), device count ("5"), or both ("5 · 38 W").
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
5. **Footer.** "Updated just now", Demo badge when in demo mode, button "Open Topology".

### 3.3 Topology window

`Window` scene, default 1100 × 700, resizable, remembers frame. `NavigationSplitView` with:

- **Sidebar** (system Liquid Glass sidebar): Overview, Ports (one row per port), Devices (flat list), Power, Events, Diagnostics.
- **Detail**:
  - *Overview*: the topology graph. Host node on the left, port nodes in the middle column, device trees fanning out to the right. Links are drawn as curved turquoise paths whose thickness and brightness scale with link speed. Small light pulses travel along active links (disabled with Reduce Motion). Each link carries a speed chip; each port and hub node carries a power badge. Clicking a node selects it.
  - *Ports / Devices*: tables with sortable columns (name, port, speed, power, vendor, IDs).
  - *Power*: charger details with every power profile, system input / load / battery chart, per-port output chart.
  - *Events*: reverse-chronological timeline with filters.
  - *Diagnostics*: list of findings with explanations and suggested fixes.
- **Inspector** (trailing, toggleable): all known fields of the selected port or device, plus an "IORegistry keys" disclosure with raw values for power users.
- **Toolbar**: Refresh, Tree/Graph toggle, Export menu, Inspector toggle, search field.

### 3.4 Settings window

Tabs:

- **General**: Launch at login (SMAppService, with status and an "Open Login Items" fallback), show menu bar item, show Dock icon while a window is open, hide empty ports, port order (physical / connected first).
- **Menu Bar**: icon style, text content, power units precision.
- **Appearance**: background opacity slider (60–100%, default 88%), glass tint strength, text size (S/M/L/XL), Reduce Motion override for link animation.
- **Notifications**: toggles for device connected, device disconnected, link downgraded, charger connected/disconnected, diagnostics.
- **Ports**: list of the Mac's ports with editable names and a "Reset names" button.
- **Advanced**: refresh cadence for power polling (1/2/5 s), show raw IORegistry keys in the inspector, demo mode toggle and scenario picker, export raw capture, open the project page.

### 3.5 Notifications

Local `UserNotifications`. Title names the device; body names the port and link, e.g. "Samsung T9 connected · Left Front · USB 3.2 Gen 2 @ 10 Gb/s". Downgrade alerts name both speeds. Rate-limited so a dock with 10 devices yields one grouped notification.

### 3.6 Command-line tool

`busstop` (built alongside the app, also embedded in the app bundle at `Contents/MacOS/busstop`):

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

- True dark. Surfaces are black or near-black so the Mac's glass and the turquoise accent carry the light.
- Liquid Glass is used for controls and navigation (header control cluster, toolbar, sidebar) and never for content cards, following Apple's HIG ("Don't use Liquid Glass in the content layer").
- Turquoise is the only accent. Status colours (amber, coral) appear only for warnings and errors.
- Legibility wins over translucency. The popover backing opacity is adjustable, and Reduce Transparency forces it to 100%.

### 4.2 Colour tokens

| Token | Hex | Use |
|---|---|---|
| `background` | `#000000` | Window and popover base |
| `surface` | `#070D0E` | Cards |
| `surfaceRaised` | `#0D1719` | Hover, selected rows, inspector groups |
| `stroke` | `#3EE6D4` at 16% | Card borders, separators |
| `accent` | `#3EE6D4` | Turquoise: active states, links, primary text accents |
| `accentDeep` | `#0FA3A0` | Fills behind accent text, pressed states |
| `accentGlow` | `#8AFFF3` | Link pulses, fastest links, focus rings |
| `accentMuted` | `#1C5F5A` | Inactive links, empty-port rings |
| `textPrimary` | `#EAFBF8` | Titles and values |
| `textSecondary` | `#9BBAB5` | Labels and subtitles |
| `textTertiary` | `#5E7B77` | Hints, disabled |
| `powerIn` | `#7BF5B0` | Charging / power in |
| `warning` | `#FFC266` | Warnings |
| `critical` | `#FF6B7A` | Errors |

Link-speed ramp (colour and stroke width of topology links): USB 1/2 `#3C5E5A` 1.5 pt; 5 Gb/s `#22A69B` 2 pt; 10 Gb/s `#3EE6D4` 2.5 pt; 20 Gb/s `#5FF0E0` 3 pt; 40 Gb/s `#8AFFF3` 3.5 pt; 80 Gb/s and faster `#C9FFF9` 4 pt with glow.

### 4.3 Typography

SF Pro via system fonts. Titles `.headline` semibold; values `.body` with `.monospacedDigit()`; chips `.caption` semibold with rounded design; machine name `.title3` bold. All sizes scale with the Text Size setting through `dynamicTypeSize`.

### 4.4 Materials and glass

- Popover: system popover glass, `darkAqua` appearance, a `#000000` backing at the user's opacity (default 88%) so a hint of wallpaper glass shows at the edges.
- Header controls: `GlassEffectContainer` with `.glassEffect(.regular.tint(accent.opacity(0.22)).interactive())` buttons.
- Topology window: `containerBackground(.black, for: .window)`, glass sidebar and toolbar from the system, cards solid.
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
| `BusStopCore` | macOS, Linux | Pure Swift. Raw capture model (`RawSnapshot`), output model (`HostSnapshot`), `TopologyBuilder`, port labelling and catalogue, formatters, diagnostics, event diffing, power history, export, demo scenarios. No IOKit. Fully unit-tested on Linux and macOS. |
| `BusStopKit` | macOS | IOKit capture (`RegistryCapture` → `RawSnapshot`), live monitoring (`LiveMonitor`: IOKit notifications, power-source notifications, display reconfiguration, power polling), SMC power channel reader, machine info. |
| `BusStop` | macOS | The app: AppKit status item and popover, SwiftUI views, settings, notifications, launch at login. |
| `busstop` | macOS | Command-line tool. |
| `BusStopCoreTests` | macOS, Linux | Unit tests with fixtures. |

The manifest declares macOS-only targets inside `#if os(macOS)`, so `swift build` and `swift test` work on Linux for the core.

### 5.2 Data flow

```
IOKit / IOPS / SMC / CoreGraphics
        │  (BusStopKit.RegistryCapture, background queue)
        ▼
   RawSnapshot  ── Codable, platform-neutral, exportable as "raw capture"
        │  (BusStopCore.TopologyBuilder, pure function)
        ▼
   HostSnapshot ── ports → device trees, power summary, diagnostics, displays
        │  (BusStopCore.SnapshotDiffer)
        ├──► [ConnectionEvent] → event log, notifications
        ▼
   PortStore (@Observable, @MainActor) → SwiftUI views, status item text
```

- `LiveMonitor` triggers a full capture on any IOKit match/terminate/interest notification (debounced 250 ms), on power-source and display changes, and on a timer (power polling every 2 s while UI is visible, every 10 s otherwise for the menu bar text).
- Captures run on one serial background queue and never overlap. Results are delivered to the main actor.
- Demo mode swaps the capture source for `DemoScenarios`, which produce `RawSnapshot` values, so the same builder path is exercised.

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
2. Catalogue entry for `hw.model` with matching connector and number.
3. Catalogue entry by rank among same-connector ports (non-contiguous numbering such as {1, 2, 4}).
4. Generic "USB-C 2", "MagSafe", "HDMI".

**USB device attribution** (most to least reliable):
1. `UsbIOPort` path on an ancestor; parse the last path component `Port-<Type>@<hex>`.
2. IOPort-plane parent transport's `ParentPortType` / `ParentPortNumber`.
3. Thunderbolt tunnel: controller chain contains `AppleUSBXHCITR` or a dock xHCI; follow `apciecN` ↔ `acioN` ↔ host switch lane `Socket ID` = port number.
4. `usb-drdN` `port-number`.
5. Otherwise "Unattributed" (shown in an "Other devices" section). Internal devices behind `usb-auss` / `AppleUSBXHCIAUSS` and Apple internal hubs (`USBPortType == 2`) are excluded.

**USB device tree.** Parent = nearest `IOUSBHostDevice` ancestor. Hubs are `bDeviceClass == 9`. A USB 3 hub and its USB 2 companion (same vendor, consecutive ports) are shown as one hub when both are present.

**Speed.** `UsbLinkSpeed` (bits/s) first; else `Device Speed` (0 Low 1.5 Mb/s, 1 Full 12 Mb/s, 2 High 480 Mb/s, 3 SuperSpeed 5 Gb/s, 4 SuperSpeed+ 10 Gb/s, 5 SuperSpeed+ 20 Gb/s); else `USBSpeed` (`tIOUSBHostConnectionSpeed`: 1 Full, 2 Low, 3 High, 4 Super, 5 Super+, 6 Super+ 2x2). Never mix the two enums.

**Device power.** `UsbPowerSinkAllocation` (mA at 5 V) → mW = mA × 5. Legacy `Requested Power` ×2 mA as last resort. Hub roll-up = own allocation + descendants; hubs with `kUSBHubPowerSupply > 0` are marked self-powered and their downstream draw does not count toward the port.

**Thunderbolt / USB4.**
- Link rate per lane from `Current Link Speed`: 0x8 → 10 Gb/s, 0x4 → 20 Gb/s, 0x2 → 40 Gb/s (Linux `tb_regs.h` codes). 0 means idle.
- Lanes from `Current Link Width` bitmask: 0x1 one, 0x2 two, 0x4 / 0x8 asymmetric (three lanes one way, one the other).
- Label from total rate: 80 Gb/s and up "USB4 v2 / TB5", 40 Gb/s "Thunderbolt / USB4", 20 Gb/s "Thunderbolt / USB4 @ 20 Gb/s", 10 Gb/s "Thunderbolt @ 10 Gb/s". Never infer a protocol name from the speed code alone.
- Chain: switch `Depth` and parent switch. Host-root lane port `Socket ID` = physical port number. Downstream switches become `DeviceNode`s of bus `.thunderbolt` with `Device Vendor Name` / `Device Model Name`.
- USB devices behind a Thunderbolt device are nested under it only when their name matches the switch's model name (fail closed); otherwise they stay at port level.

**Power.**
- Charger: `AdapterDetails` / IOPS adapter: `Name`, `Manufacturer`, `Watts`, `AdapterVoltage` (mV), `Current` (mA), `UsbHvcMenu` (PDOs, keys `MaxVoltage`/`MaxCurrent` or `Voltage`/`Current`), `UsbHvcHvcIndex` (active PDO), `IsWireless`.
- Which port the charger is on: `IOPortFeaturePowerSource` with a winning option, or `FeaturesEnabled` containing "Power In", or MagSafe with `ConnectionActive`.
- System input: `PowerTelemetryData.SystemPowerIn` (mW), `SystemLoad`, `BatteryPower`.
- Per-port output, best source first: SMC `DxJV × DxJI` joined by HPM `UUID` = `DxUI`; then `PowerOutDetails[].Watts` (mW) joined by `PortIndex` = USB-C port number; then the sum of USB allocations.

**Displays.** A display is attached to a port through `IOPortTransportStateDisplayPort` (`ProductName`) or a Thunderbolt "DP or HDMI Adapter" with a non-empty `Hop Table`. If exactly one port carries DisplayPort, all external displays go there. Otherwise displays without a confident port are listed under "Other displays".

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
| Overcurrent | `Overcurrent Count` increased since launch | Warning |

### 5.5 Threading and safety

- All IOKit work happens on one serial queue owned by `LiveMonitor`. Notification ports use `IONotificationPortSetDispatchQueue` on that queue.
- Per-key `IORegistryEntryCreateCFProperty` reads for volatile nodes (transport states, USB devices), to avoid crashes reported with bulk reads during teardown.
- Every `io_object_t` is released. Iterators are checked with `IOIteratorIsValid` and re-walked if invalidated.
- Keys starting with `Apple` are not API; every read tolerates missing keys and wrong types.
- The UI layer is `@MainActor`; core types are `Sendable` value types.

### 5.6 Persistence

`UserDefaults` only: settings, port renames, window frames. The event log and power history live in memory (last 500 events, last 10 minutes of samples). Nothing is written elsewhere unless the user exports.

---

## 6. Privacy and security

- No network code, no analytics, no crash reporting. The app does not request the network client entitlement.
- Reads only: IORegistry properties, the power-source API and the SMC read selectors.
- Unsandboxed, hardened-runtime-compatible, ad-hoc signed in CI. Users who build from source run their own binary.
- Device serial numbers are shown in the inspector and included in exports; the export sheet has a "Redact serial numbers" option (on by default).

---

## 7. Build, packaging and distribution

- `swift build` builds everything on macOS; `swift test` runs the core tests on macOS and Linux.
- `scripts/build-app.sh` assembles `build/Bus Stop.app` (Info.plist with `LSUIElement`, icon, embedded CLI), ad-hoc signs it and zips it.
- `scripts/install.sh` builds and copies the app to `/Applications`. A locally built app carries no quarantine attribute.
- GitHub Actions:
  - `core-linux`: `swift:6.4-noble` container, build and test the core.
  - `macos-27`: `xcode-27` runner (macOS 27, Xcode 27, Swift 6.4), build, test, assemble the app, run the CLI against demo data and the live (virtual) machine, upload the zip.
  - `macos-26`: `macos-26` runner with Xcode 26.6 for backward compatibility.
- Releases: tagged builds attach the ad-hoc-signed zip. README explains "Open Anyway" in System Settings › Privacy & Security for downloaded builds.

---

## 8. Testing

- Unit tests in `BusStopCoreTests` cover: `PlistValue` coding, property accessors, speed and power formatting, port parsing, label resolution (exact, rank fallback, user override), USB attribution order, hub roll-ups, Thunderbolt link decoding, charger and PDO parsing, per-port power joins, diagnostics, event diffing, demo scenarios, JSON export round-trip.
- Fixtures are hand-built from real public IORegistry dumps (macOS 26.3 MacBook Neo `IOPort` plane, macOS 27 MacBook Air M2 `AppleSmartBattery`, Thunderbolt `system_profiler` captures) and from the demo scenarios.
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
| Widgets / App Intents | Deferred | Require team signing and an Xcode project |
| Homebrew | Not in v1 | Homebrew disabled unsigned casks in September 2026 |
| Licence | MIT | Matches the repository; MIT-licensed references (WhatPort, WhatCable, PortScope) are credited in `THIRD_PARTY_NOTICES.md`; no GPL code used |
| Appearance | Always dark | The requested look is true dark; light mode would dilute it |

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
- GitHub Actions runner images: https://github.com/actions/runner-images
