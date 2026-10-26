# Desktop widgets: plan

ROADMAP item 14. Work happens on one branch (`feat/widgets`) and stays unmerged until the whole feature is done; a placeholder widget never ships. When it merges, the lasting decisions move to `docs/decisions.md` and this file is deleted.

## Scope

Large and Extra Large widgets on the macOS desktop. Small and Medium are out of scope for now.

| Widget | Large | Extra Large |
|---|---|---|
| **Ports** | One row per physical port in physical order: device, link speed, watts, a diagnostic badge | The same rows, plus the devices behind each hub and dock, as a tree |
| **Power** | Charger and its USB-PD contract ("20 V × 4.7 A"), battery, total watts in and out, a last-hour chart | Adds watts per port and a 24-hour chart |
| **Health** | Current diagnostics in plain English, flaky connections with their likely culprit, or "All links healthy" | Adds the recent event timeline and a 7-day health strip per port |

Dropped: the Mac Outline widget. Deferred: Port Focus (a widget where the user picks the port) and Displays. Port Focus needs a configuration intent, which needs the App Intents metadata that SwiftPM does not generate; it can follow ROADMAP 13 (Shortcuts and App Intents). `systemExtraLargePortrait` arrives in macOS 27; it may suit Ports later, behind an availability check.

Every widget has four states: **live**; **demo** (a Demo badge, when `isDemo`); **stale** ("Bus Stop isn't running", once the data is older than 5 minutes, scheduled as a second timeline entry); and **empty** ("Open Bus Stop", when there is no data yet).

## What is already proven (2026-10-26)

- A SwiftPM executable target, wrapped by `scripts/build-app.sh` into `Contents/PlugIns/BusStopWidgets.appex`, works as a widget extension. No Xcode project. The Hello, world widget on this branch showed in Edit Widgets in all four sizes on macOS 27.0.1.
- The extension must link with `-e _NSExtensionMain`, as Xcode does and as Apple's own widgets are; a widget that starts in its `WidgetBundle`'s own `main` crashes at launch.
- The extension must carry `com.apple.security.app-sandbox`, and is signed before the app.
- **The extension must be signed by a team.** chronod leaves ad hoc signed extensions out of the gallery ("Requested to add extension, but purging instead because we shouldn't cache it"). An Apple Development certificate from team H4Z248B45P was enough; release builds use the Developer ID from the same team. Ad hoc builds (pull request CI, other people's source builds) still bundle the extension, but no widget appears.
- The app must be in `/Applications`.

Not yet proven: the App Group, notarization with group entitlements, and a Developer ID build on a clean Mac (see the release gate below).

## Architecture

```
PortStore.ingest ──► WidgetPayload (redacted, JSON) ──► App Group container ──► widget TimelineProvider ──► views
                 └─► WidgetCenter.reloadAllTimelines()
```

- **The widget never reads hardware.** The sandbox blocks the SMC and parts of IOKit. The app publishes everything the widgets show; the extension only decodes it.
- **App Group `H4Z248B45P.io.github.static74.busstop`.** On macOS a team-prefixed group needs no provisioning profile, and since macOS 15 both processes must claim it (the unsandboxed app included) and find it with `containerURL(forSecurityApplicationGroupIdentifier:)`. `build-app.sh` reads the team ID from the signing certificate's OU, writes it into both Info.plists (`BusStopTeamID`), and adds the group to both entitlements. With ad hoc signing there is no team, no group entitlement and no key, and the app writes no payload.
- **`WidgetPayload`** (BusStopCore, Codable):
  - the snapshot through `Exporter.redacted(_:)`, without raw property bags;
  - power samples: the in-memory last 10 minutes (`PowerHistory`) and 24 hours at 5-minute steps from `HistoryArchive.powerSamples`;
  - the newest 20 events;
  - port health (make `PortHealth` Codable);
  - the `dataColor` setting, so widgets use the user's data colours;
  - `capturedAt`, `isDemo` and a schema version.
- **Writer** at the end of `PortStore.ingest` (every live and demo snapshot, renames and settings changes pass through it). It writes atomically, mode 0600, then asks for a reload. It writes only when what the widgets show has changed (power rounded to whole watts) and at most once a minute when only power changed. Clear History, and turning "Keep history between launches" off, delete the payload, since it holds events.
- **Shared views** move from BusStopApp into a new `BusStopUI` library that both the app and the extension link: `Lagoon`, `DataPalette`, the parts of `Components` the widgets use, and `PowerCharts`. Known ties to cut: `GlassIconButton` reads `AppSettings.shared.glassTint`; `TextSizeSetting` lives in `AppSettings.swift`; BusStopApp builds with `.defaultIsolation(MainActor.self)`, so the moved code needs the same setting or explicit isolation. Store-bound views (`CompactPortRow`, `PortCardView`, `PowerStripView`) are not moved; the widgets get their own views built from the same parts and from `PortDeviceTree` and `PopoverText`, which take plain values.
- **Rendering.** Desktop widgets turn monochrome (vibrant) when a window covers the desktop, and macOS 26 and 27 add tinted and clear styles. Link speed is always written as text, never shown by colour alone. Use `containerBackground(for: .widget)`, `widgetAccentable()` and `\.widgetRenderingMode`.
- **Deep links.** A `busstop://` URL scheme in `Support/Info.plist`, handled in `AppDelegate`, routing through the page names `Automation.swift` already parses: `busstop://topology/power`, `busstop://port/<PortKey>`. Tapping a widget opens that page; tapping a port row selects the port.
- **Size.** The extension is 88 KB today. Linking BusStopCore adds the USB vendor and port catalogues; measure it, and split a small data target out of Core only if the extension grows past a few MB.

## Milestones

Each milestone is one or more commits on this branch.

1. **Build setup.** Done: the target, `Support/Widgets-Info.plist`, `Support/Widgets.entitlements`, `build-app.sh` assembly, version stamping and inside-out signing. Still to do: `smoke-test.sh` checks that the extension exists, is signed, is sandboxed and imports `_NSExtensionMain`.
2. **Data path, end to end.** App Group entitlements and team ID stamping in `build-app.sh`; `WidgetPayload`; the writer and reload in `PortStore`; the Hello widget changed to show "N ports · updated 2 min ago" from the payload. This proves the pipe before any real view is built.
3. **`BusStopUI` extraction.** A pure move with no behaviour change; the app's tests stay green.
4. **Ports widget**, Large and Extra Large.
5. **Power widget**, Large and Extra Large.
6. **Health widget**, Large and Extra Large.
7. **Deep links.**
8. **Docs and release gate.** Then the PR, a cold review of the exact head, and the merge.

## Tests

- **Core:** the payload round-trips; it contains no serial numbers; it stays under a size bound for every demo scenario.
- **App:** the writer's change detection and throttle; Clear History deletes the payload; URL routing.
- **Views:** render every widget for every demo scenario at Large and Extra Large with `ImageRenderer`, as `CompactPopoverTests` and `ThemeContrastTests` do, and check that nothing is clipped or empty. Also in vibrant rendering mode.
- **Smoke test:** the extension's layout, signature, entitlements and entry point.

## Testing on a Mac

```
SIGN_IDENTITY=<Apple Development or Developer ID identity or SHA-1 hash> scripts/build-app.sh
osascript -e 'quit app "Bus Stop"'
ditto "build/Bus Stop.app" "/Applications/Bus Stop.app"
open "/Applications/Bus Stop.app"
```

Then right-click the desktop › Edit Widgets › search "Bus Stop". If two identities share a name, pass the SHA-1 hash from `security find-identity -v -p codesigning`. An Apple Development certificate needs Apple's WWDR G3 intermediate in the keychain. To debug: `pluginkit -m -p com.apple.widgetkit-extension -v`, and chronod's messages through `/usr/bin/log` (in zsh, a bare `log` is a shell builtin).

## Release gate (before merging)

Start `release.yml` by hand (it runs everything except publishing). Install the notarized Developer ID build on a Mac with no development certificates, on macOS 26 and 27, and check:

- notarization accepts the app and extension with App Group entitlements;
- the widgets appear in the gallery and show live data;
- no "access data from other apps" prompt appears;
- the widgets look right in full colour, monochrome, tinted and clear styles.

## Docs to update

- `docs/SPEC.md`: remove widgets from the non-goals (line 27) and the decision table (line 426); describe the payload in §6 Privacy (where it lives, what it holds, redaction, mode 0600, deleted with history).
- `docs/ARCHITECTURE.md`: the extension in the bundle layout, the BusStopUI target, the data flow.
- `docs/decisions.md`: SwiftPM-built extension instead of an Xcode project; team-signed only; App Group over writing into the extension's container.
- `README.md`: widgets in the features; a note that widgets need a team-signed build in `/Applications`.
- `docs/ROADMAP.md` (move item 14 to done) and `CHANGELOG.md`.

## Risks

- **Notarization with App Group entitlements** is untested; the release gate covers it.
- **App data protection prompts.** Apple's guidance is that a team-prefixed group avoids them; a forum report says same-team access can still prompt. Release gate.
- **Reload limits.** Apple said in 2022 that macOS widgets have no reload budget; that may be out of date. The writer's throttle keeps reloads rare either way, and the stale state covers missed reloads.
- **Contributors without a team** can build and test everything except seeing the widgets in the gallery; view tests cover the rendering.
