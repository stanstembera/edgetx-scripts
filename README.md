# edgetx-scripts

EdgeTX/OpenTX telemetry scripts for flight tracking on 128x64 LCD radios.

## Scripts

### DLGF3K.LUA — DLG Flight Telemetry

Real-time altitude graph with flight state tracking for DLG sailplanes.

**Features:**
- Live altitude vs. time graph with auto-scaling axes
- Automatic flight state detection (ready → launch climb → gliding → stopped)
- Tracks launch altitude, max altitude, flight duration and lap (glide) time
- Flight logbook with CSV export to SD card
- Audio feedback on state changes
- Configurable launch switch (SA–SH) with persistent config
- Configurable launch switch position (UP/DOWN)
- Configurable stop mode: altimeter-based (ALT) or manual switch (SW)
- Barometric sensor auto-reset on init

**Setup menu** (long-press **[ENT]** in idle state):

| Setting    | Options    | Description                                      |
|------------|------------|--------------------------------------------------|
| Switch     | SA–SH      | Which switch controls launch                     |
| Launch     | UP / DOWN  | Switch position to activate launch mode          |
| Stop       | ALT / SW   | ALT = altimeter landing detection, SW = manual   |

- **ALT mode** (default): flight stops when altitude drops below threshold AND switch is off
- **SW mode**: flight stops only when switch is flipped off — useful when landing below threshold altitude

**User-adjustable settings** (edit in script):

| Variable       | Default | Description                          |
|----------------|---------|--------------------------------------|
| `yMaxInit`     | 40      | Initial max altitude on graph (m)    |
| `xMaxInit`     | 30      | Initial max time on graph (s)        |
| `tresholdAlt`  | 2       | Altitude threshold for detection (m) |
| `saveLog`      | true    | Enable CSV logging to SD card        |
| `audioState`   | true    | Enable audio feedback                |

**Required sensors:** Alt, VSpd, RxBt

**Log files:** `/LOGS/<ModelName>-LogBook-YYYY-MM-DD.csv`

---

### MOTOR.LUA — Motor Model Telemetry

Real-time altitude graph with flight tracking for motor-powered models.

**Features:**
- Live altitude vs. time graph with auto-scaling axes
- Simple two-state flight tracking (stop ↔ flying)
- 3-position switch support: motor on / off / telemetry reset
- GPS speed display with max speed tracking (requires ELRS GPS)
- Falls back to VSpd display when GPS is not available
- GPS speed blinks when satellite count is low (< 6)
- Battery cell voltage (Cels) and RxBt display with low-voltage warning
- Flight logbook with CSV export to SD card
- Audio feedback on state changes
- Configurable motor switch (SA–SH) and position with persistent config

**Setup menu** (long-press **[ENT]** in idle state):

| Setting    | Options    | Description                                      |
|------------|------------|--------------------------------------------------|
| Switch     | SA–SH      | Which switch controls the motor                  |
| Motor on   | DOWN / UP  | Switch position to activate motor / start flight |

With a 3-position switch, the opposite position resets telemetry (flight counter, barometer, graph).

**Display layout (128x64):**

```
 Alt[m]          #Flight
 Duration[s]     Bat[V]
 Speed[km/h]
 max:Speed       RxB[V]
 ModelName
```

**User-adjustable settings** (edit in script):

| Variable       | Default | Description                          |
|----------------|---------|--------------------------------------|
| `yMaxInit`     | 40      | Initial max altitude on graph (m)    |
| `xMaxInit`     | 30      | Initial max time on graph (s)        |
| `saveLog`      | true    | Enable CSV logging to SD card        |
| `audioState`   | true    | Enable audio feedback                |

**Required sensors:** Alt, VSpd, RxBt, Cels

**Optional sensors:** GSpd, Sats (ELRS GPS)

**Log files:** `/LOGS/<ModelName>-LogBook-YYYY-MM-DD.csv`

---

### RESULT.LUA — Flight Results

Companion telemetry page that displays lap times of the last 5 recorded flights. Reads data from the `logBook` populated by DLGF3K.

## Installation

1. Copy desired scripts from `128x64/SCRIPTS/TELEMETRY/` to `SCRIPTS/TELEMETRY/` on your radio's SD card.
2. In EdgeTX, go to **Model Setup → Telemetry → Screens** and add the script as a telemetry screen.
3. Optionally add `RESULT` as a second telemetry screen (for DLGF3K).
4. Long-press **[ENT]** on the telemetry screen to configure the switch.

## Hardware

- Designed for radios with **128x64 pixel LCD** displays (e.g. FrSky Taranis Q X7, RadioMaster Zorro)
- Requires a barometric altitude sensor (e.g. FrSky FVAS-02)
- Optional: ELRS GPS module (e.g. RadioMaster ELRS GPS) for speed tracking in MOTOR script

## License

[MIT](LICENSE) — Copyright 2023 stanstembera
