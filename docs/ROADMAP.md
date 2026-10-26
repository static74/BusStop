# Bus Stop roadmap

Planned work after 1.0, roughly in priority order within each group. Items move to the changelog when they ship. Nothing here adds network access or telemetry: anything that sends data off the Mac is opt-in, local-network only, and off by default.

## Correctness on real hardware

1. **Validation on real Macs and capture fixtures.** Collect raw captures (`busstop --raw`) from as many Mac models, docks, displays, hubs and chargers as possible, and turn each into a regression fixture under `Tests/BusStopCoreTests/Fixtures`. Every topology rule that was written from documentation alone gets a real capture behind it. Start with the setups already reported: a Thunderbolt dock feeding monitors and USB hubs. The first one is in: an Anker Prime Thunderbolt 5 dock with two monitors and USB hubs on a MacBook Pro (`Fixtures/AnkerPrimeTB5.json`).
2. **"Identify this port" flow.** A guided check in Settings: "plug something into the port you want to name" lights up the port that changed and lets the user confirm or correct its name. It fixes the catalogue for Macs whose port locations are wrong or missing, and can produce a catalogue entry to send upstream.

## Cables and power

3. **Cable report card.** One page per cable seen in a port: what the e-marker says (rated speed, current, voltage, Extended Power Range, active or optical, vendor), what was actually negotiated over it, and a plain verdict ("good for 40 Gb/s and 240 W"). It remembers cables by vendor and product ID so the same cable is recognised next time.
4. **Charging bottleneck explainer.** When the Mac charges slower than the charger could deliver, say which part is the limit (charger, cable rating, port, battery temperature or charge limit) and what would fix it.
5. **Charger history.** Remember chargers by their PD identity: profiles offered, highest contract, and when each was last seen.

## Automation and integrations

13. **Shortcuts and App Intents.** Actions such as "Get devices on port", "Get charging wattage" and "Is a device connected", so Shortcuts and automations can use Bus Stop's data. Needs a signing team, and the App Intents metadata SwiftPM does not generate (the widgets showed a SwiftPM-built extension works otherwise).
15. **Rules and actions.** Simple local rules: "when this drive connects at USB 2 speed, notify me", "when the dock disconnects, run this shortcut".
16. **CLI webhook and MQTT output (opt-in, local).** `busstop --watch` can post events to a local webhook or MQTT broker for home-automation setups. Off by default, local network only, and documented as the one feature that sends data anywhere.

## Distribution and reach

17. **Sparkle updates.** In-app updates with signed appcasts, now that releases are signed with a Developer ID.
18. **Homebrew tap.** `brew install --cask busstop` from a project tap, with the CLI linked automatically.
19. **Localisation.** Move user-facing strings into string catalogues and accept translations, starting with the languages contributors offer.

## Done since 1.0

- Releases are signed with a Developer ID and notarized, so they open without the "Open Anyway" step.
- The topology map pans freely by dragging, zooms with the scroll wheel or a pinch, stays sharp at every zoom, and shows a cable's details in the inspector when its link is clicked.
- Devices behind a Thunderbolt dock are drawn under the dock, and a dock's monitors hang off the dock on the map, in the list and in the command-line tree.
- A hub chip's USB 2 half is merged into its USB 3 half even when the port has several hubs at its root.
- A Thunderbolt dock's built-in hubs and USB functions fold into the dock's card and are listed in its inspector, so the map draws only devices joined by real cables (checked against the Anker Prime capture).
- A Cables section in the sidebar lists every link below each port.
- A Power mode colours the map's links by watts, with pulses that follow the power.
- USB vendor names come from a built-in copy of the usb.ids list when a device reports none, and a cable's e-marker vendor is named.
- One port can be pinned to the menu bar, so its link speed or watts show next to the icon.
- A compact popover layout shows one line per port, with each port's devices a click away.
- A Mac Outline page draws the Mac with each port where it physically sits, coloured by what is plugged in and how fast it runs.
- The event log, power and per-port counters are saved between launches in a local file with size and age caps, a Clear History button and a switch to stop saving; the Power page charts the last hour, day or week from it.
- Devices that keep disconnecting, links that keep changing speed and devices slower than before on the same port raise a warning that names the likely culprit (cable, port, hub or device).
- Each port shows its plug events, connections, overcurrents, liquid detections and connection errors over the last 7 days next to the hardware's all-time counts, with a gentle note when a port has far more problems than its siblings; the overcurrent warning now lasts 24 hours across relaunches.
- A light Lagoon theme in Settings › Appearance (Dark, Light or Match System), with Dark as the default.
- Desktop widgets: Ports, Power and Health, each in Large and Extra Large, fed by the app through an App Group and shown in team-signed builds such as releases. A widget where the user picks the port waits for item 13, since it needs App Intents.
