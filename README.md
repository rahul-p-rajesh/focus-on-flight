# Contrail

A personal macOS focus app. Each session is a flight between two places on Earth at
real speed: you look down on satellite scenery with town names and airports moving
under a small white plane, with ambient sound you choose and the travel time left always
in view. Pick how long you want to fly and choose from real airports that far away.

## Run it

```bash
./scripts/build-app.sh
open build/Contrail.app
```

Requires macOS 26 on Apple silicon. Builds with Xcode or with only the Command Line
Tools (the scripts fall back to the Command Line Tools if the Xcode licence has not
been accepted).

## Test it

```bash
./scripts/test.sh
```

Unit tests cover the route maths, flight timing and track, pause-aware clock,
airport search, made-up place names, destination suggestions, logbook summaries
and CSV export.

## How it works

| Part | Where |
|---|---|
| Route maths, timing, flight track, naming, logbook | `Sources/ContrailCore` (no UI, unit-tested) |
| App model, flight session | `Sources/Contrail/AppModel.swift`, `FlightSession.swift` |
| Moving scene, HUD, desktop panel | `Sources/Contrail/FlightViews.swift` |
| Plane drawing | `Sources/Contrail/AirlinerView.swift` |
| Planning, boarding, landing, logbook, settings | `Sources/Contrail/*View*.swift` |
| Sound mixer | `Sources/Contrail/SoundMixer.swift`, `SoundViews.swift` |
| Desktop mode, notifications, wallpaper sync | `Sources/Contrail/SystemServices.swift` |
| Place search and naming | `Sources/Contrail/PlaceService.swift` |

- **Scenery**: Apple MapKit satellite imagery. The camera follows the great-circle
  route, heading-up, and climbs and descends at the ends.
- **Desktop mode**: borderless windows at the macOS desktop window level, one per
  display, so the flight runs behind icons and windows.
- **Motion**: with Smooth motion, MapKit glides the camera between updates; Energy
  saver steps it 5 to 10 times a second. Either way the scene drops to once a
  second when no window shows it.
- **Data**: JSON files in `~/Library/Application Support/Contrail`.

## Data sources

- Satellite imagery and place search: Apple Maps (free in native apps; the Apple Maps
  logo and Legal link stay visible).
- Airports: [OurAirports](https://ourairports.com/data/), public domain, trimmed by
  `tools/airports/build_airports.py`.
- Sounds: synthesised by `tools/soundgen/generate.py`. Replace any file in
  `Resources/Sounds` with a CC0 recording of the same name to swap it.
- Icon: drawn by `tools/icon/make_icon.swift`.

## Developer flags

For testing only; none are needed in normal use.

| Flag | Effect |
|---|---|
| `--data-dir PATH` | Use a separate data folder |
| `--demo-route LHR,FCO --demo-stage plan\|boarding\|flight\|landed` | Jump to a stage |
| `--time-scale 60` | Fly 60 times faster |
| `--seed-logbook` | Fill an empty test logbook (only with `--data-dir`) |
| `--debug-bridge DIR` | Accept test commands, write window snapshots and offscreen previews to DIR |
| `--force-visible` | Treat the scene as visible (for timing tests) |
