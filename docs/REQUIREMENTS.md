# Focus on Flight: Requirements

Name: **Focus on Flight** (originally Contrail). Updated 2026-10-29. Owner: Rahul.

## 1. Summary

Focus on Flight is a personal macOS focus app. Each session is a flight from one place
on Earth to another, at real speed. While you work, you look down on real
satellite scenery moving under a small white plane, with town names and
airports below, ambient sound, and the travel time left always in view.

## 2. Principles

- **Original work.** Our own name, icon, layout, text, sounds and code.
- **Local first.** No accounts, no analytics, no tracking.
- **Calm.** The map is the hero. Real speed only: the plane never speeds up or
  slows down to fit a timer.

## 3. Platform and technology

| Item | Choice |
|---|---|
| OS | macOS 26 or later, Apple silicon |
| UI | SwiftUI, Liquid Glass with a solid fallback |
| Maps | Apple MapKit hybrid satellite imagery (labels, roads, airports) and 3D globe |
| Storage | JSON files in Application Support |
| Audio | AVFoundation |
| Build | Swift Package Manager, packaged by `scripts/build-app.sh` |
| Places | Any point on Earth via Apple place search; bundled OurAirports list (public domain): name, code, city, coordinates |

## 4. Functional requirements

### FR-1 Session length is travel time

- **FR-1.1** A session lasts exactly the real flight time of the route:
  great-circle distance at 500 km/h plus 8 minutes for taxi, climb and descent.
  A 191 km hop takes about 31 minutes.
- **FR-1.2** The plane always flies at that one steady speed; it is never sped
  up to fit a session. There is no study-time setting, no Pomodoro timer and no
  breaks.

### FR-2 Plan by time (first tab)

- **FR-2.1** The user chooses a departure: search (city, address, airport name
  or code), "Near me", or a point on the globe.
- **FR-2.2** The user sets how long to fly with a slider (15 min to 4 h).
- **FR-2.3** The app lists up to 8 real airports whose flight time matches,
  spread around the compass, medium and large airports first. Made-up airfields
  at real towns appear only where fewer than three real airports fit.
- **FR-2.4** "Shuffle" shows a different set. The user picks one, or chooses
  their own arrival with search, "Near me" or the globe.

### FR-3 Plan by route

- **FR-3.1** The user chooses departure and arrival as in FR-2.1. The panel
  shows the flight time and distance.
- **FR-3.2** Places more than 30 km from any airport get a stable, made-up
  airfield name and code, marked with a small sparkle.
- **FR-3.3** The planning map shows airport code markers when zoomed in.
  Clicking a marker, or anywhere on the map, opens a card with "Depart from
  here" and "Fly here".

### FR-4 Boarding and takeoff

- **FR-4.1** A boarding pass shows route, codes, flight time, distance, a
  random window seat, category, goal, departure and landing times.
- **FR-4.2** Takeoff: the globe turns to the departure and the camera descends
  to it (at most 6 s, can be skipped; a crossfade with Reduce Motion).

### FR-5 In flight

- **FR-5.1** Straight-down satellite view, heading-up, with town names, roads
  and airports (can be turned off).
- **FR-5.2** A small white airliner silhouette at the centre with a soft
  shadow and no coloured lights. Two long, soft contrails trail from the engines
  once the plane is up and stay put over the ground, so they slide back exactly
  as fast as the map. A soft white line traces the whole route through the
  plane. The imagery is shown at near full brightness, with only a light
  vignette.
- **FR-5.3** Flying height setting (camera height): low (12 km, more detail),
  medium (20 km, default, about 11 km of ground top to bottom) or high (30 km,
  widest and calmest). Takeoff and landing start and end at 1.5 km, and the
  climb widens the view at an even pace. The plane reaches cruise speed within
  about 90 seconds, so it never crawls near the airport.
- **FR-5.3a** During a flight the map can be dragged, zoomed and rotated. The
  plane keeps flying and is drawn at its real position; "Re-center" (or R)
  follows it again.
- **FR-5.4** Motion setting: Smooth (the camera glides every frame) or Energy
  saver (small steps a few times a second).
- **FR-5.5** Travel time left is always visible at the top right of the flight
  view and in the macOS menu bar.
- **FR-5.6** An auto-hiding glass card shows route progress, travel time left,
  the region below, altitude and ground speed (altitude in feet; 30,000, 36,000
  or 41,000 ft at cruise depending on flying height; speed in km/h or mph), and
  the landing time. Controls: pause, globe view, sound,
  landing chime, desktop mode, end flight early.
- **FR-5.8** Ending a flight early (after confirming) plays a crash of about
  six seconds: the plane spirals down trailing smoke while the ground rushes
  up, then a flash, fireball, shock ring and smoke, and the scene dims. A click
  skips it. It is skipped when Reduce Motion is on, during takeoff, in the
  globe view, when the scene is not on screen, or when turned off in Settings.
  Afterwards the Logbook opens.
- **FR-5.7** Sleep, pause and hidden windows are handled: the plane is where it
  should be for the elapsed time, and the scene updates once a second when not
  visible.

### FR-6 Desktop mode

The flight scene can run as a live background on every display, behind icons
and windows, with a small control panel and the menu bar item. Optional
wallpaper sync (off by default) sets and later restores the real wallpaper.

### FR-7 Sound

A master switch; nine ambience layers that mix; one music track at a time
(three bundled, or the user's own files); per-layer volume with fades; the last
mix is remembered. Sounds are synthesised by `tools/soundgen` and can be
replaced by CC0 recordings with the same file names.

### FR-8 Landing, categories and logbook

- **FR-8.1** On landing: a chime (can be turned off), a silent notification,
  and a landed card with the goal to tick off.
- **FR-8.2** Categories can be added, renamed, recoloured and archived.
- **FR-8.3** The logbook shows time flown per category per day, week and month
  charts, totals, a map of routes flown, editable entries and CSV export.

## 5. Visual style

Tinted glass panels, dark theme, one accent colour, SF Pro and SF Mono. The
Apple Maps logo and Legal link always stay visible.

## 6. Non-functional

- **Energy.** 0% CPU when idle; about 11% at cruise in Energy saver mode; Smooth
  motion costs more while the scene is on screen; about 2% when hidden.
- **Privacy.** Network use is only Apple Maps. Location only on "Near me".

## 7. Data sources and licensing

| Source | Use | Terms |
|---|---|---|
| Apple MapKit | Imagery, labels, globe, place search | Free in native apps; logo and Legal link kept visible |
| OurAirports | Airport names, codes, coordinates | Public domain |
| `tools/soundgen` | Ambience, music, chime | Our own |
| User's audio files | Music | The user's own |
