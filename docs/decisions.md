# Decisions

Dated records of choices that shape the code, with the alternatives that were turned down. Newest first.

## 2026-10-19: History is a local JSON file

**Question.** Roadmap item 6 asks for the event log, power history and per-port statistics to survive a relaunch, with a size cap and a way to clear it. Where and how is it stored, how often is it written, and how does it stay away from demo data?

**Decision.**

- **Format.** One JSON file, `~/Library/Application Support/io.github.static74.busstop/history.json`, folder 0700 and file 0600. The folder name is hard-coded, because `Bundle.main.bundleIdentifier` is nil under `swift run`. The format is `HistoryArchive` in `BusStopCore`, with a `schemaVersion` and one section per `hw.model`. Inside a section, ports are keyed by `PortKey.description`, not by `"<hw.model>#<PortKey>"`: the section already separates models.
- **Contents and caps.** Events, newest 5,000 and at most 30 days old. Power as one average per minute (system input, battery, system load, each port) for 7 days, without minimum and maximum, since nothing would read them. Per-port increases in the three hardware counters, and liquid detections, per local calendar day for 90 days, so "the last 7 days" means the user's days. About 5 MB at most, by dropping the oldest entries. `PowerSample` gains `systemLoadMilliwatts`.
- **Dates** use `JSONEncoder`'s default (seconds as a number), which keeps the milliseconds that event ids carry.
- **Decoding.** Lists are decoded entry by entry, so one event of a kind this version does not know drops only that event. A file that does not parse is renamed `history-corrupt-<ms>.json`. A file with a newer `schemaVersion` is never overwritten; Settings says so.
- **Gaps are signalled by the app, not inferred from timestamps.** The first capture after launch, `NSWorkspace.didWakeNotification`, a change of source, or a capture dated before the last one counts no deltas. There are no stored gap markers; a missing power minute is the gap.
- **Saves.** At most every 5 minutes when there are new events (checked once a minute, so the first event after a quiet spell saves within a minute), every 15 minutes when only power changed, and synchronously at `willSleepNotification` and quit, on a serial utility queue with an atomic write. Re-ingesting the same capture (a setting change, a port rename) records nothing.
- **Demo mode.** Launching in demo never reads the file. Entering demo saves the live archive and holds it aside; leaving restores it. Demo captures go into their own archive, which is never saved and starts over at each scenario change, so two scenarios with the same Mac model never mix.
- **Settings.** A History section in Settings › Advanced rather than a new tab, which would change the Automation values and the screenshots. Turning "Keep history between launches" off deletes the file after a confirmation; turning it back on in the same session starts empty, so the deleted history is never written back.
- **Delivery.** Roadmap items 6 to 8 ship as four pull requests instead of the eight steps first planned: this file and its store (with the Events page that now reads a multi-session log), the Power page ranges, the flaky-connection detector, and port health. The archive already records what the later ones read (system load, per-port days, the last overcurrent).
- **Roadmap.** Shipped items are deleted from `docs/ROADMAP.md` without renumbering the rest. Markdown renders an ordered list from its first number, so the gaps do not show, and renumbering in every PR of four parallel lanes would conflict each time.

**Why.** JSON in one file is easy to inspect, delete and test with fixtures, and it is read only once, at launch. Power changes on every capture, so saving it every minute would rewrite a few megabytes 1,440 times a day; events are rare and matter more, so they save quickly, but a cable that keeps reconnecting can add events every minute, so they too wait 5 minutes after the last save. Since PR #15, captures while the screens sleep come only on hardware changes and can be hours apart, so any "more than 30 s apart is a gap" rule would throw away a night's plug counts.

**Risks.**

- The file holds display serial numbers and Thunderbolt device UIDs inside event ids, and device names in titles, unredacted, like port names in the preferences. SPEC §6 and the README say so.
- Without a wake notification (a missed one), counters that moved during sleep would be counted on the day of the wake.
- A crash loses at most 5 minutes of events and 15 minutes of power.
- Rewriting the whole file every 15 minutes while idle costs a few megabytes of writes each time. Not measured over a long run yet.

**Rejected alternatives.**

- *UserDefaults.* Not meant for megabytes, and it is rewritten as a whole on every change anyway.
- *SQLite, Core Data or SwiftData.* Incremental writes would be cheaper, but they bring a schema and migrations, and the archive would stop being a plain value type that the Core tests build and check without a store. Not worth it at a few megabytes.
- *ISO 8601 dates.* They drop fractional seconds and so change event ids on a round trip.
- *Gaps from timestamps.* Wrong while the screens sleep (above).
- *Saving everything every 30 to 60 seconds,* as first planned: several gigabytes of writes a day.
- *Feeding saved samples through `PowerHistory`.* Its window is measured from the newest sample and it clears itself when the clock goes back; the popover's 10-minute buffer stays as it is.

## 2026-10-19: A pinned port shows speed and watts in short form

**Question.** Roadmap item 10 lets one port's watts or link speed sit next to the menu bar icon. What does the segment look like, where is the pin stored, and what happens to a pin made in demo mode?

**Decision.** The title is the existing text, then the pinned port's segment, joined with " · " ("5 · 38W · 40G ↓61W"). The segment uses `Format.compactDataRate` ("40G", "480M", "1.5M": `dataRate` without "b/s" and spaces, the same way `compactPower` drops the space) and `compactPower` with the existing precision setting, behind a plain "↓" for power in or "↑" for power out. "≤" marks a figure that is not measured: a USB power budget or a PD contract. The default shows both speed and power, and either half drops out when the port has nothing for it, so a charging port shows only "↓61W"; an empty port shows "–". The port's name goes in the tooltip and VoiceOver label, not the title. Pins are stored per Mac model in `menuBarPinnedPorts`, like `portNames`, but a demo pin is stored under `demo:<model>`: demo scenarios use real model ids (Mac17,9 and others), so without the prefix pinning a demo port would replace the pin on a real Mac of that model. A pin for a port the Mac does not have adds nothing and stays stored. `StatusItemController.menuBarTitle` is the only builder; the Settings preview calls it too, which also fixes the preview leaving out unattributed USB power that the menu bar includes.

**Why.** Menu bar space is scarce, and next to a number a unit letter is enough: "40G" reads as a link speed, "61W" as power. Showing both by default means one setting covers charging ports and data ports. Per-model storage keeps the pin right after Migration Assistant moves settings to a Mac with different ports.

**Risks.**

- "40G" could be read as gigabytes. The tooltip and the Settings caption spell it out.
- With the popover closed, measured watts refresh about every 10 s and a contract or budget only on a hardware change or the 60 s full capture, so the pinned figure can trail what is plugged in by that much.
- `portNames` still shares one key between demo and live data on the same model. Left for a separate change.

**Rejected alternatives.**

- *The port's name in the title ("Left Rear 40G").* Too wide for a menu bar item; the tooltip carries it.
- *Full units ("40 Gb/s", "61 W").* Twice the width for no extra meaning in context.
- *Polling faster while a port is pinned.* It undoes the energy saving of power-only polls for one figure the user can refresh by opening the popover.
- *One global pin.* Wrong on a second Mac or after migration, where port keys mean different ports.
- *The title builder and the pinned-value enum in Core.* `MenuBarTextMode` and `PowerPrecision` already live in the app and `menuBarText` was already a pure static function there, so only the unit formatting moved to Core. The roadmap plan's separate Core formatting PR was folded into this one for the same reason.

## 2026-10-19: Port positions on the Mac outline come from the catalogue's location text

**Question.** The planned Mac outline page has to put each port where it sits on the chassis. The port's label cannot be used, because `label.location` becomes the user's name once a port is renamed. Where does the position come from?

**Decision.** `PortLabeler.label` also returns the catalogue location it used ("Left Front", "Rear (left)", or only "Rear" from the capability heuristic), and `TopologyBuilder` stores it as `PhysicalPort.catalogLocation`, which a rename leaves alone. `ChassisLayout.resolve` (Core) turns the text into slots:

1. A live port goes where its `catalogLocation` says. It sorts at its catalogue row, found by connector and location; a port placed only by area sorts with the first row of its connector on that face, ties by port number.
2. Catalogue rows become passive slots only when no live port has their connector (Ethernet, the power inlet, an SD slot macOS does not report). A connector with live ports never draws its rows a second time, even when the labeler placed those ports by area.
3. Laptop sides sort rear, center, front, then catalogue order. Desktop faces sort by connector (first catalogue row on that face), then qualifier ("leftmost" to "rightmost"), then catalogue order. Slot `i` of `n` sits at `(i + 1) / (n + 1)`, so no two slots share a place.
4. A port with no location, or one the parser cannot read, is unplaced.

The chassis family (laptop, Mac mini, Mac Studio, Mac Pro, iMac, or another desktop) comes from the machine name, which is the catalogue's marketing name or the name guessed from the model prefix, and falls back to a laptop when the Mac has a battery.

**Why.** The catalogue already carries the position, as text in a few fixed forms, and every one of the 326 rows parses. Desktop qualifiers are relative within one connector, not absolute: the Mac Studio lists USB-C and USB-A both at "Rear (left)", and the 27-inch iMac has USB-C at "Rear (left)" and USB-A at "Rear (leftmost)". So desktop faces group by connector before the qualifier. Connector and location are unique within every model, so the layout finds a port's row itself and the port needs no stored index. `HostSnapshot.worstSeverity(on:)` sits in Core next to it, so the outline's badge and the popover can share it.

**Rejected alternatives.**

- *Store the catalogue row index on `PhysicalPort`.* Redundant while connector and location are unique, which a test checks, and it would tie saved snapshots to the generated file's row order.
- *Match the catalogue again inside the layout.* It would lose the builder's evidence (the Thunderbolt sockets and sibling capabilities) that decides when a row is rejected.
- *Hand-edit `PortLocationCatalog+Data.swift` to add coordinates.* The file is generated from PortScope's data and is never edited by hand.
- *Generic laptop and desktop fallbacks as separate families.* An unknown Mac with a battery already draws as a laptop; one `other` case covers the rest.

## 2026-10-19: Background polls read power only, and stop while the screens sleep

**Question.** The weekend soak (`docs/soak-2026-10-19.md`) found about 420 captures an hour, all night, each walking the whole I/O Registry and opening a powerd connection. The polls only exist to keep power figures current. How much of that can go?

**Decision.** A poll tick or `AppleSmartBattery` interest runs a power-only capture: `RegistryCapture.refreshPower` re-reads the battery service and SMC and copies the rest, port counters included, from the last capture. Every other notification, the UI appearing, and any capture more than 60 s (`LiveMonitor.maximumTopologyAge`) after the last full one re-read everything. Every capture pushes the next poll back one interval. `PortStore` pauses polling while the screens sleep or another user's session is active; hardware notifications still capture, and resuming runs a full capture.

**Why.** Topology changes already post IOKit match, terminate, interest and display notifications, so re-walking it every 10 s found nothing new. A power-only capture also skips the power-source API, so powerd is contacted only on full captures. Nobody can see the menu bar while the screens sleep. The 60 s floor covers any per-port PD value that changes without a notification, without first proving where each one comes from.

**Risks.**

- A per-port value that changes without a notification can be up to 60 s stale.
- Port counters (plug, connection, overcurrent) in a power-only capture are copies, and while polling is paused full captures are sparse. History built on these captures has to treat long gaps as gaps, not as zero change.
- If a wake or session-active notification were missed, power text would stay frozen until the next hardware change.

**Rejected alternatives.**

- *Cache the powerd reads and invalidate them on `kIOPSNotifyPowerSource`.* That notification fires only on an AC/battery switch, not when one of two chargers is unplugged, so the cache would go stale. Skipping the API on power-only captures removes the round-trip anyway.
- *Prove every per-port PD source has a notification and drop the 60 s floor.* Not checked on every Mac and dock; the floor costs one full capture a minute.

## 2026-10-16: Bus Stop builds on macOS only

**Question.** `BusStopCore` was kept buildable on Linux, with a CI job in the `swift:6.4-noble` container, so that contributors without a Mac could work on parsing and topology. Is that still worth it?

**Decision.** No. The package builds on macOS only. `Package.swift` declares every target without `#if os(macOS)`, the `core-linux` CI job is gone, and CONTRIBUTING, ARCHITECTURE, SPEC and README no longer describe a Linux build. The split between targets stays: `BusStopCore` has no IOKit, AppKit or SwiftUI, so its tests run on saved captures and demo data, without the hardware or a running app. It may now use other Apple frameworks, such as `os.Logger` or CryptoKit.

**Why.** The app only runs on macOS, and the project has no contributors without a Mac. The Linux build ruled out Apple frameworks in the core and had to be kept in mind in every change, for no user. The macOS 26 job runs the same core tests on every pull request.

**Risks.**

- Nothing now fails the build if `BusStopCore` imports IOKit, AppKit or SwiftUI. Code review has to catch it.
- Someone without a Mac can no longer run the tests.

**Rejected alternatives.**

- *Keep the Linux job as a check on the core's imports.* A whole platform build is a heavy way to enforce a rule about imports.
- *Keep the Linux build but drop the CI job.* A build nobody runs breaks without anyone noticing.

## 2026-10-14: The map's controls get their own hosting views

**Question.** The map's Zoom Out, Actual Size, Zoom In and Fit buttons and its Data/Power picker carry `.help`, but often showed no tooltip. List mode was also reported to lose its chips' tooltips at the 2 s refresh, while a 5 s poll and the menu-bar popover were fine. The suspects were the 30 fps pulse `TimelineView` and `PortStore` replacing the snapshot on every poll, even when nothing changed. What stops the tooltips?

**Decision.** `GraphControlHost` hosts the picker and the zoom cluster each in its own `NSHostingView`, sized to its content, and passes the Text Size setting and the accent tint on. The pulses keep running, and the store still replaces the snapshot on every poll. `GraphControlHostTests` checks that the map has the two hosting views, that ⌘=, ⌘-, ⌘0 and ⌘9 still reach the zoom buttons, and that the hosted content follows Text Size.

**Why.** Measured on macOS 27 with a probe library loaded into a demo build (`DYLD_INSERT_LIBRARIES`, on a copy signed without the hardened runtime). It logs AppKit's tooltip calls and every mouse-moved, entered and exited event the app receives. The pointer was moved either in-process (a faked mouse location) or for real, by the agent's computer-use tool.

- SwiftUI's `.help` does not add AppKit tooltip rectangles. Each `NSHostingView` has one `NSViewDynamicToolTipManager`, which asks SwiftUI for the help text under the pointer. When the pointer rests for about half a second where there is none, the manager stops asking. It adds a 4 × 4 pt tracking area at the pointer and waits for the window server to report the pointer leaving it. The map, the zoom cluster and the picker shared the detail column's hosting view, so one manager served them all, and it waited like this whenever the pointer rested on the map.
- The window server normally reports the pointer entering such an area at once, and leaving it later. Sometimes it reports no entry, and then no exit either. The manager then waits until the pointer passes back over that spot, and no control in its hosting view shows a tooltip until then. In three tries with the pointer resting on the map and then moving to a zoom button, Zoom Out and Zoom In showed their tooltips. Actual Size showed none, in exactly this way, while Zoom Out's tooltip was still fading out.
- The pulses are not the cause. With the pointer faked in-process on Zoom In, the manager's calls, the cursor-rect resets and the tracking-area changes were the same with `-animateLinks NO` as with the pulses running, and the tooltip appeared both times. With the real pointer, Zoom In showed its tooltip with the pulses running, and Zoom Out failed as above with them off (about 2 % CPU, so nothing was animating).
- List mode did not reproduce. Each List row has its own hosting view. With the real pointer, chips on two rows showed their tooltips after about 1.6 s and kept them across the following refreshes. That held in the demo at its 2 s tick and on this Mac's live ports at a 2 s poll. The probe saw no tooltip calls from a refresh. So skipping an unchanged snapshot would change nothing here, and in the demo the readings change every tick anyway.
- While the agent controls the screen, the Claude app shrinks to a floating 520 × 720 pt window at the top right of the screen (window level 3), which screenshots leave out. Pointer events over it go to Claude, so nothing under it shows a tooltip. The menu-bar popover sits above it, so its tooltips work. That explains failures in agent-driven sessions wherever the window ran under it: the first List-mode runs here had their chips under it and showed no tooltips. Runs that move the pointer must keep the window clear of it.

With the controls in their own hosting views, the probe finds each control's help text through that view's own manager instead of the map's. This has not yet been checked with the real pointer.

**Risks.**

- A manager can still stall inside one hosting view, for example after resting on the few points between two zoom buttons.
- Environment values set above the map reach the hosted controls only if `GraphControlHost` passes them on. Today that is Text Size and the accent tint; the window's root font does not reach them, which changes nothing because every text in them sets its own `lagoonFont`.
- The map's body runs on every frame of a drag or pinch, and each run gives both hosts a new root view. That costs two small re-renders per frame; it was not measured against the 16.7 ms p95 budget.
- Scroll-wheel zoom still works over the controls, because it watches the window's events. A drag that starts on a control did not pan the map before this change either.
- The window server's behaviour is observed on macOS 27, not documented, and may change.

**Rejected alternatives.**

- *Pause the pulses, or move them out of the map's hosting view.* They do not affect the tooltips.
- *Skip reassigning an unchanged snapshot, or make List rows equatable.* List rows kept their tooltips at a 2 s refresh.
- *Drop the zoom cluster's glass, or its `.interactive()`.* Both were built. The failures first blamed on the glass were the stalled manager; the picker shared it and showed its tooltip in the tries where the window server had reported the waiting area.
- *Draw the controls' tooltips on the map, as for the chips (`GraphTooltipState`).* More code, and with a manager of their own the controls no longer depend on the map's.

## 2026-10-14: CI runs once per pull request, and the paid runner only by hand

**Question.** When should GitHub Actions run, given that the CI minutes cost money?

**Decision.** `ci.yml` runs on pull requests (each push to an open pull request runs it again) and when started by hand. Branch pushes and merges to `main` run nothing. The `macOS 27 (Xcode 27)` job, the only CI job on the `xcode-27` runner, runs only when the workflow is started by hand. `screenshots.yml` runs only by hand. `release.yml` still runs on `v*` tags.

**Why.** Each pull request ran CI three times: once for the push to its branch, once for the pull request (the two concurrency groups differ, `refs/heads/…` and `refs/pull/…/merge`, so neither cancelled the other), and once after the merge to `main`, which also ran Screenshots. The repository is public, so the standard `ubuntu-24.04` and `macos-26` runners are free; the run timing API lists no billable minutes for them. The `xcode-27` runner is a custom label that the timing API leaves out, which points to a paid larger runner, and four `xcode-27` jobs ran for every pull request. With this change a pull request runs on the free runners only, and the release workflow still tests on `xcode-27` before it publishes.

**Risks.**

- A pull request is no longer built against Xcode 27 unless someone starts CI by hand. macOS 26 with Xcode 26.6 and Linux still build and test it, and a release runs the full test and smoke test on Xcode 27.
- README screenshots are only as new as the last manual Screenshots run.

**Rejected alternatives.**

- *Keep `push` and filter it to `main`.* That still repeats the pull request's run after every merge.
- *Skip CI for documentation-only changes with `paths-ignore`.* The free runners make the saving small, and a skipped run is easy to mistake for a passing one.

## 2026-10-14: A dock's built-in USB parts leave the device tree

**Question.** On a MacBook Pro with an Anker Prime Thunderbolt 5 dock (`Tests/BusStopCoreTests/Fixtures/AnkerPrimeTB5.json`), the map drew the dock as eight cards: the dock, its USB 3 root hub ("USB3 HUB", joined to the dock by a 10 Gb/s line that looked like a cable), two USB functions named after the dock, two VIA hubs and the Ethernet and card reader on one of them. Which USB devices are part of the dock, and how should they be shown?

**Decision.** `DockParts` moves a dock's built-in parts out of its `children` into `DeviceNode.internalParts`, a flat list; whatever hangs off a part moves up to the dock, with `internalParentID` naming the part. The rules start at the dock and only go down through parts, so nothing behind an external hub can be folded:

- A. A hub directly below the dock, on the Mac's own xHCI, with `UsbTunnel` true, when it is the only `UsbTunnel` root on the port and the dock is the port's only switch with a live USB tunnel.
- B. A USB device with the dock switch's own `Device Vendor ID` / `Device Model ID`, when no other switch reports that pair.
- C. A hub or billboard on a captive port (`USBPortType` 1, both halves of a merged hub) of a hub folded by C or D.
- D. A hub holding a B device on a captive port; with two or more such hubs, B and D are off.
- E. A device that is not a hub, on a hub folded by C.

Counts are drawn devices only. The map, the list, the Cables section and the command-line tree do not mention the parts, so the tree reads like the map. Detail views do: the dock's inspector lists them with name, vendor, speed and power, VoiceOver for the dock (window and popover) says how many there are, and the popover's Copy Details and the dock's bullet in a Markdown report name them on a "Built in: …" line. JSON exports carry them in `internalParts`. Power roll-ups and the USB 2 fallback and hub budget diagnostics read the unfolded tree (`DeviceNode.unfolded()`), so their numbers do not change and a built-in hub's finding points at the dock. A device that becomes a part, or stops being one, raises no connect or disconnect event.

**Why.** On this capture, by registry ID:

- Only the Intel root hub (556, 8087:5787) has `UsbTunnel`; it sits on the Mac's `AppleT8142USBXHCI` (`usb-drd0-port-ss`), and the dock switch (469, JHL9580) is the only downstream switch whose USB adapter has a non-empty `Hop Table`. Its Fresco Logic USB 2 half (554) merges with it.
- The switch reports `Device Vendor ID` 0x291A (Anker) and `Device Model ID` 0x83B5; its `Vendor ID` / `Device ID` are Intel's chip IDs. Exactly two USB devices are 291A:83B5: "Anker Thunderbolt 5 Docking Station" at 12 Mb/s on Fresco port 5 (765) and "Anker Prime Docking Station" at 480 Mb/s with a billboard interface (433).
- 433 sits on port 5 of the VIA hub 600/733 with `USBPortType` 1, which ties that hub to the dock (D). Without D, 600, 433 and 801 all stay.
- The VIA hub 801/094 on port 2 of that hub is captive on both halves (C). The reporter, who owns the dock, confirmed that "USB 10/100 LAN" (0BDA:8156) and "USB Storage" (05E3:0764) on it are the dock's Ethernet and card reader (E).
- The Intel and Fresco root ports report `USBPortType` 0 for every device, the dock's own 12 Mb/s function included, so a captive flag on a root port is not evidence (C starts below D).
- `non-removable`, the hub-port flag `RegistryKeys.swift` reads, is on none of the 32 USB records.

The "billboard" (325, 0BDA:5452, class 0x11, 2.5 W) stays. Its vendor string is "Cable Matters Inc.", it is USB 2 only on Fresco port 3 while the Intel half of port 3 is empty, which is how a USB-C to DisplayPort cable running all four lanes for video looks, and the Gigabyte M32U on the dock runs at 32.4 Gb/s (HBR3 × 4). The reporter confirmed it is a Cable Matters USB-C to DisplayPort cable. `USB Port Map` was not used as evidence. The Realtek 4-port hub (638/710) and the VIA hub 829/264 with the iPad and keyboard behind it stay too: they are external hubs plugged into the dock.

Result: seven parts, one dock card instead of eight, drawn with two displays and three USB devices (the Realtek hub, the Cable Matters billboard and the VIA hub), and counts of 19 below the dock and 20 in all, down from 26 and 27.

**Risks.**

- Rule E would hide a device plugged into a dock port that is wired to a captive internal hub. Hubs on such a hub stay visible with everything behind them.
- Thunderbolt 3 and 4 docks with their own PCIe xHCI, daisy-chained docks, and docks that report no or shared identity fold less or nothing: their parts stay as cards, as before.
- While a dock enumerates, its parts can appear as cards for a capture or two before the USB tunnel's `Hop Table` is live. That raises no events either way.
- Device counts drop: the window subtitle, the menu bar text, All Devices and every roll-up count only drawn devices. JSON snapshots carry the parts in `internalParts`.
- Built-in parts have no rows in All Devices; searching for one finds the dock.

**Rejected alternatives.**

- *Match by name or vendor* ("Docking Station", VIA, Realtek, 12 and 480 Mb/s functions). VIA and Realtek hubs appear inside and outside the dock on this capture.
- *`non-removable` hub-port flags.* Not present on any record.
- *`USBPortType` 5 (USB-C) as the root signal.* The Fresco half reports 5 as well, and so does every synthetic test device; `UsbTunnel` on the Mac's own controller is specific.
- *Location ID prefixes.* They say which controller and tier a device is on, not who owns the port: external devices on the dock's ports share the prefix.
- *Captive flags anywhere below the dock.* The root ports' flags are not reliable, and a wrong flag on a root port would fold an external monitor or hub plugged into the dock.
- *Count every device and label the count.* The reporter chose drawn devices only. A "7 built-in parts" suffix on the dock's line in the command-line tree and in Markdown was built and taken out, so those match the map; detail views name the parts instead.
- *Dim or collapse the internal hubs instead of folding them.* They would still read as cables.
- *Drop the parts.* The inspector should list them, and power roll-ups and diagnostics still need them.

## 2026-10-14: The map draws its own tooltips for chips and badges

**Question.** Hovering a speed chip, transport chip or power badge on a map card showed no tooltip, although each carries `.help`. How should the map explain its chips?

**Decision.** On the map, chips and badges publish their rectangles in layout coordinates through a preference (`GraphTooltipRegionsKey`), measured in one named coordinate space per card before the zoom. A card reports the pointer in that same space, and the map's hit layer reports it for the link chips, which never take the pointer. `GraphTooltipState` finds the smallest chip under the pointer and shows its text in `GraphTooltipOverlay`, drawn above the drawing group so it keeps its size and stays sharp at every zoom. It never takes the pointer. It appears after the system's `NSInitialToolTipDelay` (one second unless set), or after 0.1 s when moving on from another tooltip. It hides on a mouse-down, a pan or zoom, a Data/Power switch, when the window stops appearing active, and when its chip goes away; after a click it stays hidden until the pointer leaves the chip. It fades only without Reduce Motion, and its border is the accent under Increase Contrast. The chips' `.help` stays everywhere else (popover, List mode, tables, inspector): an environment value, `showsChipHelp`, is false only inside the map. Accessibility labels are unchanged; the tooltip is hidden from VoiceOver.

The regions are kept out of observation and the map's body never reads tooltip state. Only the overlay observes the tooltip on screen, which changes only when a tooltip appears, disappears or its text changes. Each chip keeps its rectangle with `onGeometryChange` in the card's own space, which a pan or zoom does not change. So the tooltip adds no redraws of the map, and a pan or zoom publishes no new regions; a snapshot redraws the map as before (see the 16.7 ms p95 budget under "Map cards and chips render after the zoom").

**Why.** Checked by hand on main in the topology window. With link animation on (the default), the map's own Zoom In button showed no tooltip, while the toolbar's buttons did. With `-animateLinks NO` in the demo, Zoom In showed its tooltip. So the 30 fps pulse `TimelineView` keeps the system's tooltips from appearing anywhere over the map. It may not be the only cause: on real hardware with `-animateLinks NO` and a 5 s poll, Zoom In still showed no tooltip in two tries. Card chips showed no tooltip even with animation off, in the demo and on real hardware, so the cards add a cause of their own. The suspects, not proven, are the chips sitting inside each card's `Button` label and the snapshot being replaced every poll. A map-drawn tooltip sidesteps all of these without pausing the pulses. A headless hosting-view test confirms that the regions pass through the drawing group and that a `ViewThatFits` publishes only the chips it shows.

List mode in the topology window also loses native tooltips at the demo's 2 s cadence (it showed them at a 5 s poll; the menu-bar popover shows them at 2 s). That looks like a window-level problem; it is not fixed here and is to be filed as a follow-up.

The pulse conclusion was wrong, and the List-mode failure did not reproduce. The pulses do not affect the system's tooltips; AppKit's tooltip tracking for the map's hosting view can stall whatever the pulses do, which is what the `-animateLinks NO` runs saw. "The map's controls get their own hosting views", later the same day, has the measurements.

**Rejected alternatives.**

- *Pause the pulses while the pointer rests.* The card chips showed no tooltip with the pulses off either.
- *One `.help` on each card's `Button`, summarising its chips.* Not per chip, it still depends on the system tooltip over the animating map, and the link chips stay uncovered.
- *One map-wide `.help` whose text follows the pointer.* Whether the system re-arms it when the text changes is undocumented. (This entry also said the pulses suppress it; they do not, see above.)
- *Clear views carrying `.help` above the drawing group.* They would take clicks, hover and pointer styles from the cards and links.
- *Let the link chips take the pointer.* They would take hover and clicks from the links under them.

## 2026-10-14: No page sets the minimum width of the topology window's detail column

**Question.** With the inspector open, the topology window crashed on the Events page at 1000 pt wide and narrower (issue #5). AppKit raised an exception because the window needed more update-constraints passes than it has views. How should the pages and the detail column share the width?

**Decision.** `TopologyWindowView` gives the detail column `.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)`, so no page passes a minimum width to the split view. A page that is still wider than the column runs past its right edge, under the inspector, never under the sidebar. Pages also fit narrow columns on their own: the Events header puts the filter and Clear under the title when one row does not fit (`ViewThatFits`), and a diagnostic's Show buttons stack the same way. `TopologyWindowLayoutTests` hosts the whole window as `WindowManager` does, with the inspector open, and lays it out for a second.

**Why.** `NavigationSplitView` hosts each column in its own `NSHostingView`, with a constraint that keeps the column at least as wide as its fitting width, at priority 999.9. The fitting width includes the safe-area insets, and the detail column runs under the floating sidebar (232 pt) and the inspector (330 pt), so those are its insets. When the page inside sets a minimum width, the column's width and its insets keep invalidating each other. At 1000 pt the Events column settled at 535 pt wide with a right inset of 0, where every other page's column was 1000 pt wide with insets of 232 and 330. With the fix, the Events column is 1000 pt wide too, and its constraint is 562 pt, the two insets and nothing from the page. Measured on macOS 27. The root view's own minimum (860 pt from `.frame(minWidth: 860)`) was the same on every page and with or without the fix, so `sizingOptions = [.minSize]` in `WindowManager` is not involved.

The threshold does not follow from the page's minimum width. The Events page measured 303.5 pt at every text size (its filter popup alone is 199.5 pt and does not grow with Text Size), and it crashed from 900 pt up to 1080 pt, but not at 1100 pt. Diagnostics with one finding measured 207 pt and crashed at 900 and 1000 pt, but not at 1050 pt. Devices and Power never crashed, and no page crashed with the inspector closed. With the fix, the Events page reports 85 to 99 pt (Small to Extra Large), the floor of its empty-state text.

Each half was measured on its own in the window test. The detail column frame alone ends the crash on both pages. The adaptive Events header alone ends it on Events but not on Diagnostics, so the frame is the fix and the header keeps Clear from being clipped (at 1040 pt it was).

**Rejected alternatives.**

- *Raise the window's minimum width.* SPEC §3.3 promises 900 × 600, and Events crashed up to 1080 pt.
- *Remove `.fixedSize()` from the Events filter.* Measured: still crashed at 900 pt.
- *Only the adaptive Events header.* Measured: Diagnostics with a finding still crashed.
- *`.clipped()` on the detail column.* It would also cut the page background off where it runs up under the transparent title bar (see the next entry).
- *Close the inspector when the window is narrow.* It overrides the user's choice, and the inspector is where Events and Diagnostics show what they select.

## 2026-10-13: The topology window's title bar is transparent where nothing scrolls under it

**Question.** With the inspector open, the toolbar's search field straddled the end of a gray band over the detail column, because the inspector's black runs up under the toolbar. How should the toolbar strip look?

**Decision.** The title bar is transparent on the map (an overview or port page in Graph mode), the All Ports and All Devices tables, Events, and Diagnostics while it has no findings. `TopologyWindowView` sets it through `HostingWindowObserver`. On those pages the toolbar strip shows the window's black over the page and the inspector alike (SPEC §4.1, "true dark"). Power, the List overview and Diagnostics with findings keep the system's opaque title bar. The Export menu hides its chevron.

**Why.** Over the map, which has no scroll view, the title bar drew an opaque gray band (40/255), while the inspector's black ran up under the toolbar. The search capsule began just left of that boundary. The map is clipped to its frame, so a transparent title bar there shows only black. The rows of the two tables and of Events scroll only below their page header, and Diagnostics has no scroll view while it has no findings, so nothing passes under the strip on those pages either.

Pages that scroll need the opaque title bar. A transparent bar on every page was built first. Under it, rows scrolled up showed crisp under the title and the toolbar buttons on the List, Power and Diagnostics pages. With the opaque bar, those rows stay hidden or dimmed as before.

With the inspector open, the opaque-bar pages measure 8 to 16/255 over the detail column against 3 to 5 over the inspector, so no page shows a seam. On main, Power and Diagnostics turned gray (30/255) once the window had shown the map; switching the title bar back to opaque resets that. Whether the window is active makes no difference.

The Export button is a `Menu`, whose disclosure chevron pushed the share icon left of centre.

**Rejected alternatives.** Each was built and captured.

- *A transparent title bar on every page.* Rows scrolled under it showed crisp under the title and buttons. `.scrollEdgeEffectStyle(.hard, for: .top)` hid them only on AppKit lists and tables, not on SwiftUI `ScrollView` pages such as Power.
- *`.toolbarBackground(.black, for: .windowToolbar)` with the background visible.* The band stayed gray.
- *`.scrollEdgeEffectHidden(true, for: .top)` on the map.* The band stayed gray.
- *Stop the inspector's background at the toolbar.* It left a step in the strip's gray from 42 to 35 and a hairline that ended at the column boundary.
- *`.scrollEdgeEffectStyle(.soft, for: .top)` alone.* The gray band stayed.
- *Search in the sidebar.* Search disappears from the window when the sidebar is collapsed.
- *`.searchable` on the detail column, `DefaultToolbarItem(kind: .search)` declared before the buttons, a fixed `ToolbarSpacer` before search, or hiding the window toolbar's background.* None of them moved the field off the seam or removed the band.

## 2026-10-13: Map cards and chips render after the zoom, in one drawing group

**Question.** How should the map's cards and speed/power chips stay sharp at every zoom, as the links already do?

**Decision.** The chips layer and the cards share one `drawingGroup()` in `GraphMap`. Each card keeps its `scaleEffect` and `position`, but the group renders them after the zoom, at the screen's resolution, instead of enlarging a bitmap drawn at 100 %. Everything inside the group must be pure SwiftUI drawing (text, shapes, SF Symbols): a drawing group shows glass, materials, `ProgressView`, `Menu`, `TextField`, system-styled controls and `NSViewRepresentable`s as placeholders. The system focus ring is lost inside the group too, so each selectable card draws its own `accentGlow` ring while it has keyboard focus. The map leaves the view tree while the topology window is closed, so the group's textures are freed; the window itself is kept for reuse.

**Why.** At 200 % a card matched a bilinear 2× enlargement of its 100 % render (mean difference 1.2/255), which looks pixelated on a 1× display and soft on Retina. With the drawing group it differs from that enlargement by 7.9, and its edge sharpness rises from 16.4 to 21.4. At 100 % the two renders match (mean difference 0.14/255). The remaining figures were measured in one session against main, on a 27-device dock. Panning and a 25 %–200 % zoom sweep held 16.7 ms p95 in both builds, on a 60 Hz display and on a 144 Hz display. On the 144 Hz display both builds paced at 60 fps, so at 60 fps the drawing group adds no frame cost; neither build was measured at a higher frame rate. With the window open, memory matches main before any zoom: 309 against 308 MB in a 1280 × 820 window at 1×, and 422 against 407 MB in a 1900 × 1000 window at 2×. After a zoom sweep it is higher: 393 against 347 MB at 1×, and 682 against 591 MB at 2×. Closing the window gives the group's textures back, because the map leaves the tree: the closed footprint was 142 against 129 MB at 1×, and 180 against 247 MB at 2×.

**Rejected alternatives.**

- *Lay the cards out at screen size with zoom-scaled fonts, paddings and icons.* Every shared chip, badge and icon would need a zoom parameter, and `Lagoon.font` rounds point sizes while SF Pro changes optical size at 20 pt, so truncation would shift between zoom steps.
- *Draw the cards in a `Canvas`, like SVG.* It duplicates all card and chip styling and rebuilds hit testing, hover, tooltips and accessibility by hand.
- *One drawing group per card.* More offscreen passes, for no gain.
- *Cap the zoom at 100 %.* It removes the zoom the map offers.

## 2026-10-13: The topology map draws through its own camera, not a scroll view

**Question.** How should the topology map pan and zoom, so that it stays sharp at 200 %, stays smooth on a large graph and pans freely like a web map?

**Decision.** The map has no `ScrollView`. `GraphCamera` holds a scale and an offset (a layout point `p` appears at `p × scale + offset`). Every canvas (backdrop, links, highlights, pulses) is the size of the window and draws through the camera; cards and speed chips are SwiftUI views placed through the camera and scaled with `scaleEffect`. Only what is on screen is drawn. A drag or pinch moves the camera on screen through gesture state and commits it when the gesture ends. The scroll-wheel monitor zooms for a mouse wheel and pans for trackpad scrolls and modified wheels, since no scroll view is left to take them.

**Why.** The graph used to be one canvas the size of the whole layout inside a scroll view, enlarged with `scaleEffect`. On a real dock with 27 devices that caused three problems:

- **Blur.** `scaleEffect` enlarges a `Canvas` as a bitmap, so links went soft above 100 %. This entry first claimed that SwiftUI text and shapes stay sharp under `scaleEffect`. The claim was wrong: cards and chips were enlarged as bitmaps too, and "Map cards and chips render after the zoom" corrected them the same day.
- **Lag.** Every canvas covered the whole layout, the pulse canvas redrew it 30 times a second, and the backdrop rebuilt its whole dot grid at every zoom step.
- **Panning.** A scroll view only moves within its content, so a graph that fits the window could not be dragged at all. Pan state also came from geometry callbacks that lag behind programmatic scrolls, which is the likeliest cause of a second drag snapping the map back.

**Rejected alternatives.**

- *Draw the canvases at the zoomed size inside the scroll view.* This keeps the scroll view but makes each canvas `layout × scale` large: several hundred megabytes of bitmap at 200 % on this graph, and slower, not faster.
- *Pad the scroll view's content by half a window on every side.* Tried first, to allow free panning. It quadrupled the area of every full-graph canvas, made the lag worse and still depended on the scroll view's geometry callbacks.
- *Keep the camera in `TopologyGraphView`.* Its body builds the layout and the strokes. A camera there would rebuild them on every frame of a drag, so the camera is read only by `GraphMap`.
