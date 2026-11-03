# Bus Stop and Home Assistant

Bus Stop can show up in Home Assistant as a device, with sensors for charging, the battery, the setup you're at and each port, and triggers for what happens. This page sets that up and gives a few automations to copy.

## Set it up

1. In Home Assistant, set up the MQTT integration and a broker (the Mosquitto add-on is the usual one), with a user name and password for Bus Stop.
2. In Bus Stop, open Settings › Integrations, click Add Destination › MQTT Broker…, and fill in:
   - **Broker:** your Home Assistant's address, such as `homeassistant.local`.
   - **User name** and **Password:** the ones from step 1.
   - Leave **Topic prefix** empty for `busstop/<this Mac's name>`.
3. Save it, then turn on **Home Assistant discovery**. Test Connection should say "Connected to … · broker accepted the login · test message sent".
4. In Home Assistant, a device named **Bus Stop on <your Mac>** appears under Settings › Devices & services › MQTT.

While the Mac sleeps its entities show as unavailable. Turning discovery off, or removing the destination while it is on and connected, removes the device; otherwise delete it in Home Assistant. Send to one broker from the app or from `busstop`, not both, since they share the device.

Bus Stop sends events as they happen, live values while it runs, and the discovery configs for a device named "Bus Stop on <your Mac>", only to the brokers and webhooks you add, under the prefix `busstop/<this Mac's name>` unless you change it. Home Assistant keeps a history of it, including the setup you're at; Bus Stop can't delete what Home Assistant keeps.

## Automations to copy

Replace `busstop_1a2b3c4d` with the start of your entities' ids, which Home Assistant shows on the device's page: `busstop_` and 8 letters and digits.

### Charge to 80% with a smart plug

Turn off the desk charger's smart plug when the battery passes 80%, and on again at 30%.

```yaml
automation:
  - alias: "Mac charger off at 80%"
    trigger:
      - platform: numeric_state
        entity_id: sensor.busstop_1a2b3c4d_battery
        above: 80
    action:
      - service: switch.turn_off
        target:
          entity_id: switch.desk_charger
  - alias: "Mac charger on at 30%"
    trigger:
      - platform: numeric_state
        entity_id: sensor.busstop_1a2b3c4d_battery
        below: 30
    action:
      - service: switch.turn_on
        target:
          entity_id: switch.desk_charger
```

### Lamp on when you dock

Turn on the desk lamp when you arrive at the setup named Desk.

```yaml
automation:
  - alias: "Desk lamp when docked"
    trigger:
      - platform: state
        entity_id: sensor.busstop_1a2b3c4d_setup
        to: "Desk"
    action:
      - service: light.turn_on
        target:
          entity_id: light.desk_lamp
```

### Backup drive at USB 2 speed

Notify your phone when the backup drive connects at USB 2 speed. Each trigger carries the event Bus Stop sent, so the automation can read its device and link.

```yaml
automation:
  - alias: "Backup drive is slow"
    trigger:
      - platform: mqtt
        topic: "busstop/desk-mac/triggers/device_connected"
    condition:
      - condition: template
        value_template: "{{ 'PSSD T9' in trigger.payload_json.title and '480 Mb/s' in trigger.payload_json.detail }}"
    action:
      - service: notify.mobile_app_phone
        data:
          message: "{{ trigger.payload_json.title }}: {{ trigger.payload_json.detail }}"
```

### Away mode

Say so when the laptop has been off its charger for an hour on a weekday.

```yaml
automation:
  - alias: "Laptop not charging"
    trigger:
      - platform: state
        entity_id: sensor.busstop_1a2b3c4d_charging_state
        to: "noCharger"
        for: "01:00:00"
    condition:
      - condition: time
        weekday: [mon, tue, wed, thu, fri]
    action:
      - service: notify.mobile_app_phone
        data:
          message: "Your laptop isn't charging"
```

## A webhook instead

Node-RED and Home Assistant's webhook triggers take Bus Stop's events as JSON, one `POST` each, exactly as `busstop --watch --json` prints them. Add Destination › Webhook…, paste the URL, and put a token in the header if the receiver wants one.
