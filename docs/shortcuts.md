# Bus Stop in Shortcuts, Siri and Spotlight

Bus Stop answers questions about what's plugged into your Mac for Shortcuts, Siri and Spotlight. It also adds a Port widget and four Control Center controls.

These need a release build of Bus Stop in your Applications folder. A copy built from source without a developer team can't offer them to macOS. For that case, use [the command line](#from-the-command-line).

## Actions

In the Shortcuts app, search for "Bus Stop". Every action runs inside Bus Stop. If Bus Stop isn't running, the action starts it in the background, and only Identify Port and Open Bus Stop open a window.

| Action | Gives you |
|---|---|
| Get Ports | The ports, or only those with something plugged in |
| Get Devices | The devices, filtered by port, kind or name |
| Is Device Connected | Yes or no, for a device you pick |
| Get Link Speed | A device's speed, and whether it's at full speed |
| Find Cable For Device | The cables you own that carry a device at full speed |
| Get Charging | Watts in, and what holds charging back |
| Get Battery | The battery's percentage and whether it's charging |
| Get Diagnostics | Bus Stop's findings, from a level you pick upward |
| Get Current Setup | The setup you're at, if any |
| Run Setup Check | What's off at a setup |
| Get Cables, Get Chargers | Your Gear |
| Turn Rule On or Off | Switches one rule |
| Pause Rules, Resume Rules | Pauses every rule for some minutes, or until resumed |
| Identify Port | Opens Bus Stop on a port you pick, or Settings › Ports to identify one |
| Open Bus Stop | Opens a page |
| Export Report | A text, Markdown or JSON report, without serial numbers unless you ask |

A device keeps its identity between launches, so a shortcut made for your drive keeps finding it. A device's serial number is one of its properties: a shortcut reads it only when you ask for it.

In demo mode, the actions answer from the demo. Turn Rule On or Off and Pause Rules don't work there, since demo rules never run.

## Siri and Spotlight phrases

These work as soon as Bus Stop is installed. The two that name a device learn your devices' names once Show in Spotlight is on (below):

- "What's plugged into my Mac in Bus Stop?"
- "Why is my Mac charging slowly in Bus Stop?"
- "Is my *device* at full speed in Bus Stop?"
- "Which cable should I use for my *device* in Bus Stop?"
- "Check my setup in Bus Stop"
- "Identify a port in Bus Stop"
- "Pause Bus Stop rules"
- "Export a Bus Stop report"

## Spotlight

Turn on Settings › General › Show in Spotlight to find your devices, cables, chargers and setups by name in Spotlight. Spotlight's index is outside Bus Stop's encryption, so this is off until you turn it on. Names go in as given, without redaction. Turning it off clears what Bus Stop put there, and forgetting a cable or setup removes it.

While it's on, Bus Stop also tells Siri your devices' names, for the phrases that name a device. Turning it off stops that, but Siri may keep the names it already has.

## The Port widget and the controls

- **Port widget:** add it like any widget and pick a port with Edit Widget. It shows what's plugged in, the speed and the watts. The medium size adds what's behind a hub or dock, and the port's plug events over the last 7 days. Click it to open Bus Stop on that port.
- **Controls:** in Control Center or the menu bar, add:
  - **Charging:** watts in, marked when something holds charging back. It opens the Power page.
  - **Port:** a port you pick, with its speed. It opens Bus Stop on that port.
  - **Identify a Port:** opens Settings › Ports, where Identify a Port finds which port is which.
  - **Rules:** whether rules are on or paused. It opens Automations, where you pause and resume them.

## From the command line

Every copy of Bus Stop, including one built from source, has the `busstop` command. In Shortcuts, add **Run Shell Script** with:

```bash
"/Applications/Bus Stop.app/Contents/Helpers/busstop" --json
```

Then add **Get Dictionary from Input** to read what it printed.

For a quick yes or no, such as "Is my drive connected?", search the text output instead:

```bash
"/Applications/Bus Stop.app/Contents/Helpers/busstop" | grep -q "PSSD T9" && echo yes || echo no
```
