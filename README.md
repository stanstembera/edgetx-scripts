# edgetx-scripts

EdgeTX/OpenTX telemetry scripts for DLG (Discus Launch Glider) flight tracking on 128x64 LCD radios.

## Scripts

### DLGF3K.LUA — Flight Telemetry

Real-time altitude graph with flight state tracking for DLG sailplanes.

**Features:**
- Live altitude vs. time graph with auto-scaling axes
- Automatic flight state detection (ready → launch climb → gliding → stopped)
- Tracks launch altitude, max altitude, flight duration and lap (glide) time
- Flight logbook with CSV export to SD card
- Audio feedback on state changes
- Configurable launch switch (SA–SH) with persistent config
- Barometric sensor auto-reset on init

**Display layout (128x64):**

```
 Alt[m]  #Flight
 ┌──────────────┐
 │   altitude    │
 │    graph      │
 └──────────────┘
 Time  Lap   Launch  RxBt
```

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

### RESULT.LUA — Flight Results

Companion telemetry page that displays lap times of the last 5 recorded flights. Reads data from the `logBook` populated by DLGF3K.

## Installation

1. Copy the `128x64/SCRIPTS/TELEMETRY/` folder to your radio's SD card under the same path.
2. In EdgeTX, go to **Model Setup → Telemetry → Screens** and add `DLGF3K` as a telemetry screen.
3. Optionally add `RESULT` as a second telemetry screen.
4. Long-press **[ENT]** on the DLGF3K screen to configure the launch switch.

## Hardware

- Designed for radios with **128x64 pixel LCD** displays (e.g. FrSky Taranis Q X7, RadioMaster Zorro)
- Requires a barometric altitude sensor (e.g. FrSky FVAS-02)

## License

[MIT](LICENSE) — Copyright 2023 stanstembera
