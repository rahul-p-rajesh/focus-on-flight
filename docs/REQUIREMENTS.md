# Contrail: Requirements v1

Name: **Contrail**.
Date: 2026-10-29. Owner: Rahul.

## 1. Summary

Contrail is a personal macOS focus timer. Each focus session is a flight from
any place on Earth to another. While the timer runs, the user looks down on real
satellite scenery that moves under a small plane, like the reference images:
dark-tinted top-down imagery, a white plane, and two fading contrails.

## 2. Principles

- **Original work.** Our own name, icon, layout, text, sounds and code. No
  assets, strings, or designs from any other focus app.
- **Local first.** No accounts, no analytics, no tracking.
- **Calm.** The map is the hero. Few controls show during a flight. Panels use
  tinted glass.

## 3. Platform and technology

| Item | Choice |
|---|---|
| OS | macOS 26 or later, Apple silicon |
| UI | SwiftUI, Liquid Glass (`glassEffect`) with material fallback |
| Maps | Apple MapKit satellite imagery and MapKit 3D globe |
| Storage | JSON files in Application Support, local only (SwiftData's macros need full Xcode) |
| Audio | AVFoundation (user files, generated cabin noise) |
| Alerts | UserNotifications |
| Charts | Swift Charts |
| Build | Swift Package Manager (Xcode or Command Line Tools), packaged as .app by `scripts/build-app.sh` |
| Places | Any point on Earth. Apple place search finds cities, towns and addresses. A bundled airport list from OurAirports (public domain), all sizes, keeps only name, code and coordinates. Places with no airport nearby get a made-up airfield name. |

## 4. Functional requirements

### FR-1 Plan a flight by route (Mode A)

The journey is the point, not the airport. A flight can start and end at any
place on Earth.

- **FR-1.1** The user chooses the departure in one of three ways:
  - search by city, town, address, airport name or airport code;
  - "Near me", which uses the current location (the app asks for location
    permission only when the user taps it);
  - click a point on the globe.
- **FR-1.2** The user chooses the arrival the same way.
- **FR-1.3** The app shows the flight time, the distance and the route on a
  globe preview. Flight time = great-circle distance / 850 km/h + 8 min for
  taxi, climb and descent.
- **FR-1.4** The app does not allow a departure and arrival less than 50 km
  apart. It shows a warning when the flight time is more than 4 h.
- **FR-1.5** The user selects a category (required) and types a goal
  (required, at most 140 characters).

### FR-1A Naming places

- **FR-1A.1** If a real airport is within 30 km of the chosen point, the
  flight uses that airport's name and code.
- **FR-1A.2** Otherwise the app makes up an airfield name from the nearest
  place name, for example "Millbrook Field" or "Kestrel Valley Airstrip", and
  a three-letter code. Generated codes never match a real airport code in
  the bundled list.
- **FR-1A.3** A generated name stays the same for the same point, so a
  repeated flight shows the same name in the logbook.
- **FR-1A.4** The boarding pass and logbook show real and made-up airfields
  the same way. A small marker shows which names are made up.

### FR-2 Plan a flight by duration (Mode B)

- **FR-2.1** The user chooses the departure as in FR-1.1.
- **FR-2.2** The user sets the flight time with a slider: 15 min to 4 h, in
  5 min steps.
- **FR-2.3** The app draws the reachable ring on the globe. It checks points
  around the ring in every direction, and moves each one to the nearest land
  place (a town, city or airport). Points in open ocean are skipped.
- **FR-2.4** The app suggests up to 6 destinations within ±10 % (at least
  ±5 min) of the slider value, spread across directions. Each is named as in
  FR-1A. A "Shuffle" button suggests a new set.
- **FR-2.5** If no destination is in range, the app widens the tolerance and
  tells the user.
- **FR-2.6** The user selects one destination, then a category and a goal as
  in FR-1.5.

### FR-3 Boarding and takeoff (both modes)

- **FR-3.1** There is no seat picker. The app assigns a random window seat,
  which is shown on the boarding pass.
- **FR-3.2** A boarding pass card shows route, codes, seat, category, goal,
  flight time and planned landing time. The design is our own.
- **FR-3.3** On **Start**, a subtle sequence plays (at most 6 s, can be
  skipped): the boarding pass slides away, the globe turns to the departure
  airfield, the camera moves down to it, then rises as the plane
  climbs into the cruise view.
- **FR-3.4** When macOS "Reduce Motion" is on, a short crossfade replaces the
  sequence.

### FR-4 In flight

- **FR-4.1** The view shows satellite imagery from straight above. The camera
  turns with the plane's heading, so the plane always points up the screen.
- **FR-4.2** The plane's position follows the great-circle route, in step
  with elapsed focus time. The motion is smooth and uses little energy.
- **FR-4.3** Climb: during the first part of the flight the camera rises from
  low altitude to cruise altitude. Descent: during the last part it lowers
  towards the arrival airfield.
- **FR-4.4** A white plane glyph with two fading contrails sits at the centre.
  A dark tint and a soft vignette sit over the imagery.
- **FR-4.5** A minimal glass HUD shows: time remaining, a progress bar, the
  region the plane is over (updated every 2 min), and the goal. The HUD
  hides after 5 s without mouse movement and comes back when the mouse moves.
- **FR-4.6** A toggle switches to a globe overview that shows the whole route
  and the plane's position.
- **FR-4.7** Controls: pause and resume, and end the flight early (with a
  confirmation). Pause stops the plane and the timer.
- **FR-4.8** If the Mac sleeps during a flight, the plane is at the correct
  position for the elapsed time when it wakes.
- **FR-4.9** The flight view supports full screen. A setting keeps the display
  awake during a flight (on by default).
- **FR-4.10** If imagery cannot load (offline), the view shows a tinted
  fallback and the timer keeps running.

### FR-5 Pomodoro cycles

- **FR-5.1** On by default. A flight is split into focus and break periods
  (default 25 min focus, 5 min break, both configurable). Breaks happen inside
  the flight time; setup shows the focus time and the number of breaks.
- **FR-5.2** The user can turn cycles off in setup or in Settings. Then one
  flight is one continuous focus block.
- **FR-5.3** During a break, a "seatbelt sign off" banner shows and music
  volume drops. The plane keeps flying.

### FR-6 Sound

- **FR-6.1** A master **Sound** switch turns all flight audio on or off. It is
  on the setup screen and in the flight HUD, so the user can silence or
  restore sound at any time during a flight.
- **FR-6.2** A sound panel (tinted glass, our own layout) has two groups:
  - **Ambience** layers: Cabin, Rain on Roof, Downpour, Dripping Eaves,
    Distant Storm, Waterfall, Forest, Ocean, Snow Wind.
  - **Focus music**: a few calm instrumental tracks, plus the user's own
    files.
- **FR-6.3** Each tile turns its sound on or off with one click. Several
  ambience layers can play together. Only one music track plays at a time.
- **FR-6.4** Each active layer has its own volume. Changes fade over about
  1 s, never cut.
- **FR-6.5** The user can add their own audio files or a folder (MP3, M4A,
  AAC, WAV, AIFF). The app remembers them between launches.
- **FR-6.6** Audio fades in at takeoff and fades out at landing. During a
  Pomodoro break, music drops in volume.
- **FR-6.7** The last mix is remembered and used for the next flight. Cabin
  alone, at a medium level, is the first-run default.
- **FR-6.8** Every bundled sound is a seamless loop at matched loudness, so
  switching layers never jumps in volume.

**What makes the sounds work for focus.** Steady, broadband sound with more
low frequencies than high (like cabin noise or rain) masks nearby speech and
small noises. Sounds must have no lyrics, no sudden loud events and no
audible loop point. Storm thunder stays soft and distant.

**Where the sounds come from.** Open-licensed recordings, CC0 (public domain)
first, then CC BY with credit. Each file is trimmed, loudness-matched and
made into a seamless loop by our own script. Sources and licences are listed
in `CREDITS.md`. If a good recording cannot be found, the app uses our own
synthesised version (`tools/soundgen`).

### FR-7 Landing alert

- **FR-7.1** On landing, the app shows a landed screen and sends a macOS
  notification.
- **FR-7.2** A "Landing chime" toggle is available before takeoff and during
  the flight. The last choice becomes the default.
- **FR-7.3** With the chime off, the notification still appears, without
  sound.

### FR-8 Categories

- **FR-8.1** Default categories: Work, Study, Reading, Writing, Coding.
- **FR-8.2** The user can add, rename, recolour and archive categories.
  Archived categories keep their history.

### FR-9 Logbook

- **FR-9.1** Each flight is saved with: date, start and end time, route,
  distance, planned and actual focus minutes, category, goal, seat, outcome
  (landed or ended early) and Pomodoro cycles.
- **FR-9.2** Day view: for each category, the number of sessions and the focus
  minutes on that day.
- **FR-9.3** Week and month view: stacked bars per day, coloured by category.
- **FR-9.4** Totals: focus hours, flights, distance flown, places visited,
  and a map of all routes flown.
- **FR-9.5** The user can edit a goal after the flight, mark it done, and
  delete an entry (with a confirmation).
- **FR-9.6** Export to CSV.
- **FR-9.7** Days use the local time zone. A flight that crosses midnight
  counts on its start day.

### FR-10 Desktop mode

- **FR-10.1** During a flight, the user can switch to desktop mode. The flight
  scene then fills each display as a live background, behind desktop icons
  and all app windows.
- **FR-10.2** The scene is a borderless window at the macOS desktop window
  level, one per display. It ignores clicks, appears on every desktop, and
  follows display changes (connect, disconnect, resolution).
- **FR-10.3** In desktop mode the main window becomes a small tinted-glass
  control panel with time remaining, Sound, pause and "Back to window". The
  panel can be hidden. A menu bar item keeps the time remaining and the same
  controls.
- **FR-10.4** The scene updates only as often as smooth motion needs, so
  desktop mode stays light on energy for long flights.
- **FR-10.5** On landing, early end or quit, the scene windows close and the
  normal desktop returns.
- **FR-10.6** Optional wallpaper sync, off by default: at takeoff the app sets
  the system wallpaper to a still satellite image of the route, and restores
  the user's own wallpaper afterwards. The call runs off the main thread, has
  a time limit, and turns itself off if it hangs.

### FR-11 Settings

Pomodoro on or off and lengths, default landing chime, keep display awake,
desktop mode by default, wallpaper sync,
distance units (km or mi), HUD auto-hide delay, manage categories, manage
music library.

## 5. Visual style

- **Tinted glass.** Floating panels use Liquid Glass with a dark tint. When
  "Reduce Transparency" is on, panels become solid.
- **Map first.** The map fills the window. Panels float over it.
- **One accent colour.** Category colours appear only in the logbook and
  small badges.
- **Type.** SF Pro for text, SF Mono for codes and times.
- **Screens.** Plan (tabs: By route, By time), Boarding pass, Flight,
  Desktop control panel, Landed, Logbook, Settings.
- **Keyboard.** Space pauses or resumes. Cmd+L opens the logbook. Esc shows the
  HUD.
- **Accessibility.** VoiceOver labels on all controls. Reduce Motion and Reduce
  Transparency are respected.

## 6. Non-functional requirements

- **Privacy.** Network use is only Apple Maps imagery and place lookup.
  Location is used only on "Near me".
- **Data.** One local SwiftData store in Application Support.
- **Accuracy.** The plane's position matches elapsed time within 1 s.
- **Energy.** Low CPU and GPU use during cruise. No busy loops.
- **Start-up.** The app opens in under 2 s.

## 7. Data sources and licensing

| Source | Use | Terms |
|---|---|---|
| Apple MapKit | Satellite imagery, globe, place lookup | Free in native apps. The Apple Maps logo and Legal link must stay visible and must not be covered by the tint. |
| OurAirports | Airport name, code, coordinates | Public domain |
| Apple place search and reverse geocoding | Any place on Earth, nearby place names | Part of MapKit, rate-limited, used only while planning |
| Freesound, CC0 filter | Ambience recordings | CC0, no credit needed (credit kept in `CREDITS.md` anyway) |
| OpenGameArt or itch.io, CC0 packs | Focus music | CC0; check each file's licence line |
| BBC Sound Effects | Backup ambience | RemArc: personal use only, credit the BBC. Replace before sharing the app. |
| `tools/soundgen` | Fallback ambience | Our own |
| User's audio files | Music | The user's own files |
| Icon, text, sounds, UI | Everything else | Our own |

## 8. Out of scope for v1

iPhone and iPad, widgets, iCloud sync, accounts, social features, live flight
data, a 3D aircraft model, payments.

## 9. Open questions (defaults are used until answered)

1. **Real or compressed flight time?** Default: real (one real flight minute is
   one focus minute).
2. **Maximum flight length?** Default: slider up to 4 h, warning above 4 h in
   Mode A.
3. **Pause allowed?** Default: yes.

Answered: Pomodoro cycles on by default. No seat picker, a window seat is
assigned. Name is Contrail.

## 10. Milestones

1. Flight view: fixed route, timer, scenery, plane and contrails.
2. Desktop mode: scene behind all windows, glass control panel, menu bar item.
3. Planning: any place, airport list, made-up names, Mode A and Mode B, globe
   preview.
4. Boarding pass and takeoff sequence.
5. Sound mixer, sound files and landing alert.
6. Categories and logbook.
7. Polish: accessibility, settings, energy checks.
