# STAR WARS Galactic Racer — VR Cockpit for UEVR (v2.1.1)

A UEVR profile and a single Lua script for **STAR WARS Galactic Racer**: you sit in the pilot
seat of every vehicle, and the cockpit finally moves — engine and road rumble, boost lunges,
nose lift, landings that hit, banking you can tame, a body that follows the pilot on jumps.
Everything is adjustable in game, and what you change is saved for the vehicle you drive.

> 한국어 설명서: [README_KO.md](README_KO.md)

## Why

In the VR cockpit the vehicle sat perfectly still. No engine, no road, no kick when the boost
fires — even at full speed it felt like sitting in a parked car, and you could hardly feel the speed.
v2.0.0 adds the effects and features that make the seat come alive and let the speed land.

The optional **pak mod** is for something else: the black letterbox bars, black transition
screens and dark / white translucent panels of the game's UI look fine on a monitor but float
in front of your face as big slabs in VR. It removes them.

## Credits

This is built on the UEVR profile and the VR cockpit script made by **Nero**, **madscy** and
**elliotttate** — each building on the others' work — and it runs on **joeyhodge**'s UEVR
backend DLL for this game. v2.0.0 and later (the new effects and features, and putting it all
into one script) are by **ody**.

Huge thanks to joeyhodge, elliotttate, madscy and Nero. Thanks also to
[Random-kaizoku/PracticeMode-SWGR](https://github.com/Random-kaizoku/PracticeMode-SWGR) for the
hint that helped map the characters' codenames to their names. The Korean menu uses
Nanum Gothic by Naver (SIL Open Font License 1.1).

## Contents

- [What's new in v2.1.1](#whats-new-in-v211)
- [What's new in v2.1.0](#whats-new-in-v210)
- [What's new in v2.0.0](#whats-new-in-v200)
- [Install](#install)
- [Pak mod](#pak-mod)
- [Controls](#controls)
- [The menu](#the-menu)
- [Per-vehicle settings and auto-save](#per-vehicle-settings-and-auto-save)
- [Features in detail](#features-in-detail)
- [Known issues and notes](#known-issues-and-notes)
- [Character codenames](#character-codenames)
- [Files](#files)
- [Building from source](#building-from-source)

---

## What's new in v2.1.1

- **Saved values no longer seem to reset on vehicles with mixed parts.** A vehicle is now known by
  the part its seat is in: the rear on landspeeders and skim speeders, the controls on speeder
  bikes, the pod on podracers. Swap any other part in Edit Vehicle (or drive the game's event
  vehicles, which mix models) and it stays the same vehicle, with its values.
- **Brightness per track and weather** (was per map). A sunny race and a night race on the same
  track keep their own values. **VR picture for every track** sets values for all of them at once,
  and **Saved tracks** lists them by the game's names, e.g. "Fallen Empire (Jakku) / Day".
- **Your values come along**: values saved under older vehicle names, v2.1.0's brightness per map
  and older settings are carried over (details in [CHANGELOG.md](CHANGELOG.md)).

## What's new in v2.1.0

- **Ride shake** *(off by default, for players who don't get motion sick)* — the cockpit itself
  shakes with the vehicle and the VR world shakes along, for much more sense of speed. Its own
  amounts, saved per vehicle, and a **landing slam** that grows with how fast you fell and how
  long you flew.
- **Afterburner rumble** — a boost now feels different from just driving fast.
- **Shake masters per vehicle type** — scale all the shake of bikes, landspeeders, skimmers or
  podracers at once.
- **Brightness per map** — for maps that look too bright or washed out in VR, saved for that map
  only.
- **Takedowns and the finish line camera** — the cockpit steps aside for the game's takedown and
  finish shots, then puts you back.
- **Look back** — the game's own look back works in the cockpit view, and a new hotkey (right
  stick up) turns you round in the cockpit seat while you hold it.
- **Change Camera no longer nudges the HUD** in the cockpit (follows the game's control scheme).
- A tidier menu: a reset arrow on every value, no more cut-off labels, colours, numbered follow
  modes, real vehicle and character names.

Needs joeyhodge's latest backend (see [Requirements](#requirements)). Details:
[CHANGELOG.md](CHANGELOG.md).

## What's new in v2.0.0

The original cockpit put you in the seat. v2.0.0 keeps that cockpit (seat anchoring, camera
locks, game cameras) and adds, in **one script** (`swgr_vr_cockpit.lua`, English or Korean build):

- **Cockpit shake** — the view moves like a head on a spring: engine idle and revving, engine
  while driving, road rumble and bumps, corner push, drift rattle, slipstream buffeting,
  impacts. Five simple amounts plus every single value in Fine tuning.
- **Boost punch** — afterburner, ramjet and race-start lunges with a real punch shape, nose
  lift, a low hum while boosting, and a shudder that grows as the ramjet overheats.
- **Boost effects** — stronger colours, darker edges and a flash while boosting; a split-second
  **hit-stop** (time dilation) and a **warp pulse** (VR world scale) at ramjet ignition and the
  race start.
- **Landings** — the view is pressed down and comes back, a short **thud** at touchdown, and a
  **head hit** that snaps the view angle so it feels like your head takes the landing.
- **Banking limit** — bikes and plane-like vehicles bank up to 90° when drifting; set how much
  of that reaches your eyes (per vehicle).
- **Body follow on jumps** — riders stand up in the air; your eyes follow the pilot's chest
  instead of ending up inside it. Saved per vehicle **and per character** (builds differ).
- **Near clip** — the inside of the pilot body is not drawn right at your eyes; more is cut
  while a landing presses you down.
- **Race start** — watch the engine-start shot, then the view flies smoothly into your seat.
  The vehicle body hums and shakes with the engine in the game cameras.
- **Menu screen positions** — menus and result screens that put the VR camera under the map or
  inside a wall get a fixed position (the common ones are built in; save your own).
- **Per-vehicle auto-save** — whatever you change while driving is saved for that vehicle only;
  everything else keeps its default. Built-in defaults per vehicle type, eye positions for 11
  vehicles, and per-character body follow.
- **Hotkeys** — keyboard keys set by pressing them (like UEVR's own key binding) and controller
  combos (Back + a button).
- **One switch to compare** — "Add-on effects on" turns every addition off, so the cockpit
  behaves exactly like the original v1.2.0 script.
- **Korean or English menu**, an explanation on every item, fine tuning grouped by topic.
- **Optional pak mod** (separate download) — removes the black bars and dark / white
  translucent panels that look broken in VR.

Full list: [CHANGELOG.md](CHANGELOG.md).

---

## Install

### Requirements

- STAR WARS Galactic Racer (PC).
- UEVR with **joeyhodge's latest backend**:
  [`101726-gow-e-day-poc-p1`](https://github.com/joeyhodge/UEVR/releases/tag/101726-gow-e-day-poc-p1)
  (all of joeyhodge's builds: [joeyhodge/UEVR releases](https://github.com/joeyhodge/UEVR/releases)).
  Replace `UEVRBackend.dll` in your UEVR folder with the one from that release. UEVR and the game
  are not included here.

### 1. The profile (recommended)

Each language has its own release with a file named **`SWGR-Win64-Shipping.zip`** — the name
UEVR needs, so there is nothing to rename:

- English menu: [**v2.1.1**](https://github.com/unuruu5760/SWGR-VR-Cockpit/releases/tag/v2.1.1)
- Korean menu: [**v2.1.1-ko**](https://github.com/unuruu5760/SWGR-VR-Cockpit/releases/tag/v2.1.1-ko)

1. Close the game, **back up** your current profile folder
   `%APPDATA%\UnrealVRMod\SWGR-Win64-Shipping\` (copy it somewhere else) and then **delete it**.
   Importing on top of an old profile keeps its old scripts (`swgr_cockpit_camera.lua`,
   `swgr_stable_camera.lua`, other `swgr_cockpit_*.lua`), and they fight with this one.
2. Import **`SWGR-Win64-Shipping.zip`** with UEVR's **Import Config** as it is, or extract its
   contents into a new `%APPDATA%\UnrealVRMod\SWGR-Win64-Shipping\`. Folders such as `data` are
   created by UEVR and the script when needed.
3. Start the game and inject UEVR. The script runs by itself; its menu is in
   **UEVR menu (Insert) → Script UI → STAR WARS Galactic Racer VR**.

The profile contains the UEVR settings, `user_script.txt` and the cvars of the v1.2.0 profile
with Nero's stereo-mismatch fixes, plus the script.

### 2. Script only

Already have a working profile? Download **`swgr_vr_cockpit.lua`** from the release of your
language, put it in the profile's `scripts` folder and remove the older cockpit scripts there
(`swgr_cockpit_*.lua`, `swgr_stable_camera.lua`) — they fight with this one. For the Korean
menu also copy the `fonts` folder from the Korean `SWGR-Win64-Shipping.zip` into the profile
(UEVR loads menu fonts only from there; without it the Korean text shows as `?`).
For Nero's stereo-mismatch fixes, see [Known issues and notes](#known-issues-and-notes).

### 3. Pak mod (optional)

**`SWGR-NoBlackBars-pak-v2.1.1.zip`** (in both releases) removes the black bars and panels that
look bad in VR. See [Pak mod](#pak-mod) right below. It is the same as in v2.0.x.

### Updating from v2.0.x or v2.1.0

Replace `scripts/swgr_vr_cockpit.lua` in your profile with the one from the release of your
language. The other profile files did not change, and your settings in `data` stay (they are
carried over to the new vehicle names and to brightness per track; see the
[CHANGELOG](CHANGELOG.md)).

### Updating from v1.2.0

v2.0.0 replaces `swgr_cockpit_camera.lua`. It has its own settings and does not read
`data/swgr-cockpit-options.json`; it starts from its built-in defaults. The default hotkeys
changed (F3 / F4 / F5, see below).

---

## Pak mod

**Why:** the game's UI uses black letterbox bars, black screens between scenes and dark or white
translucent panels behind menus. On a monitor they look normal; in VR they hang in front of you
as big black or white slabs. This mod makes them transparent, so you only see the parts that
matter.

**What it changes** (a few UI widgets, nothing else):

- start / finish black bars, black screens between scenes, the two dark panels before the start
  and the ESC pause panel → transparent
- the white translucent background of the race results and of the results' pause menu →
  transparent
- the dark background of the race-failed ("league token lost") screen → 40 %
- the translucent panel of the main menu's sign-in check → transparent

**Good to know**

- It is separate from the script and the profile: use it with them, without them, or not at all.
  The cockpit works fine without it.
- Install: extract `SWGR-NoBlackBars-pak-v2.1.1.zip` into the game folder so
  `zzz_SWGR_NoBlackBars_P.pak`, `.ucas` and `.utoc` end up in
  `STAR WARS Galactic Racer\Griffin\Content\Paks\~mods\`. The game's own pak files are not touched.
- Remove: delete those three files.
- Made for the October 2026 version of the game. If a game update changes those screens and
  something looks wrong, remove it.

---

## Controls

| Key (default) | Action |
| --- | --- |
| **F3** | VR cockpit ↔ game cameras (third person / bonnet). |
| **F4** | Next game camera (switches to the game cameras first). |
| **F5** | Add-on effects on / off — compare with the original cockpit. |
| *(none)* | Recenter head at the seat — assign a key if you want one. |
| **Right stick up** (controller, hold) | Look back from the cockpit seat while held. |

Change them in **Hotkeys**: click a keyboard button, then press the key you want (Esc
cancels; Insert is UEVR's menu key and can't be used). Each action can also have a controller
combo: hold **Back (View)** and press A / B / X / Y / D-pad / RB. The look-back action is held, so
it can also be a single button or a right-stick direction. While a key is being set no action
fires, and a key already used by another action moves over.

While you race in the cockpit, the game's **Change Camera** button is not passed to the game (it
did nothing there but nudge the HUD). Which button that is follows the game's control scheme:
RB with Default, right stick click with Alternative. In the game cameras and in menus it works
as usual.

---

## The menu

**UEVR menu → Script UI → STAR WARS Galactic Racer VR**. Hover over anything for an
explanation. From top to bottom:

| Section | What's in it |
| --- | --- |
| *(top)* | **Add-on effects on**, View (VR cockpit / game cameras), hotkeys, **Recenter head at the seat**, the vehicle and character you are driving. |
| **View and eye position** | Eye position (sideways / forward / up), Follow the vehicle (follow modes 1–5), **Banking %** with the live lean, Pilot visibility, **Follow the pilot on jumps** (up / forward), **Cut what is right at the eye** (cut distance), and the group **Game scenes and cameras**: race intro flyover, outside view when crashing, takedowns, finish line camera, **Look back**. |
| **Cockpit shake** | On / off, five amounts in % (Engine, Road, Corners / drifts, Boost punch, Landings and hits), the **masters per vehicle type**, **Landing hits your head**, and **Ride shake** (in red: its six amounts and its own masters). |
| **Boost effects** | Screen colours and flash %, hit-stop, warp pulse. |
| **VR picture for every track** | Picture values for every track and weather at once (in yellow). |
| **Brightness per track and weather** | Picture values for the track and weather you race (in yellow): Brightness, Bloom, Colour strength, Contrast, and three older ones under More. |
| **Race start** | Engine start shot then into the cockpit, car body engine hum %. |
| **Fine tuning (advanced)** | Every single value, grouped by topic: Engine · Road and corners · Boost lunge and nose lift · Boost screen, hit-stop, warp · **Landings and hits** · View (banking) · All shaking (head spring) · Race start. |
| **Saved vehicles** | Every vehicle with values, editable without driving it. |
| **Saved tracks** | Every track and weather with picture values, editable from anywhere. |
| **Hotkeys** | Keyboard keys and controller buttons, one block per action. |
| **Menu screen positions** | Fix menus where the VR view ends up in a strange place. |
| **Reset all settings** | Shared settings back to the defaults (press twice). Saved vehicles stay. |

Percent amounts: **100 = recommended, 0 = off, 200 = double.** The small arrow in front of a
value brings back its default. Light blue text is about what you drive now (vehicle, character,
track); red marks Ride shake and the follow mode that can make you sick.

---

## Per-vehicle settings and auto-save

Vehicles feel different and seats sit in different places, so almost everything about the
cockpit is kept **per vehicle**, and you never have to press "save".

**How it works**

- **Which vehicle it is**: the model of the part its seat is in — the rear on landspeeders and
  skim speeders, the controls on speeder bikes, the pod on podracers. Swapping that part in Edit
  Vehicle changes the seat and the cockpit, so it is another vehicle with its own values;
  swapping any other part keeps the vehicle. The menu shows the model names the game shows.
- **While you drive a vehicle**, any vehicle-related value you change — eye position, banking,
  body follow, cut distance, the shake amounts, any fine-tuning value — is **saved at once for
  that vehicle only**. It is marked **`[vehicle]`** in the menu.
- **Values you don't touch are not stored.** The vehicle keeps following its default, so a
  later change of the default still reaches it.
- Where a vehicle's value comes from, first match wins:
  1. what **you** set for this vehicle,
  2. this vehicle's **built-in** value (eye positions),
  3. its **vehicle type's** built-in value (Bike / Car / Skimmer / Plane),
  4. the shared value,
  5. the recommended value.
- **Body follow on jumps** goes one step further: it is saved per **vehicle + character**
  (marked `[vehicle+character]`), because characters differ in build and posture. A character
  without its own values uses the vehicle's.
- The **reset arrow** in front of a `[vehicle]` value forgets just that value.
- The **shake masters** are per vehicle type: "Master: default amounts" scales the amounts you
  did not set for a vehicle, "Master: saved amounts" the ones you did, on every vehicle of the
  type picked above them.
- **Without a vehicle** (in menus), the vehicle-related sliders are greyed out and only show the
  defaults; get into a vehicle to change them. Shared switches (camera lock, pilot visibility,
  on / off boxes, hotkeys…) work anywhere.
- **Saved vehicles** lists every vehicle that has values. Open one to change them without
  driving it: eye position, banking, body follow, cut distance, the five shake amounts, the
  Ride shake amounts, **Advanced options** (all fine tuning, folded) and **Body follow per character** (folded,
  one entry per character, each with "Forget this character's values").
  - **Everything back to default (eye position and body follow stay)** forgets the rest.
  - **Forget everything I set for this vehicle** forgets all of it, eye position too.

**Built-in defaults**

The author tuned one vehicle of each type and made those values the defaults for the whole type
(eye positions stay per vehicle, since seats differ):

| Type | Tuned on | Notable defaults |
| --- | --- | --- |
| Bike | Taipan | road 75 %, landing (floor 5.22, thud 3.39 / 4.23 Hz, lean 0.14), air lift 7.17 cm, cut distance 12.55 cm, more on landings 8.82; body follow up 0.85 / forward 1.21 |
| Car | Beluga | ramjet 2.66, hit-stop 0.53 (ramjet / start) and 0.33 (afterburner), 0.16 s, warp 5, landing (floor 5.11, thud 3.05, press 0.45) |
| Skimmer | Saker, Merlin | road 73 %, cut distance 3 cm |
| Plane | Myth | ramjet 3, bumps 1.779, engine while driving 2.527 |

Body follow per character on bikes: **Shade** (your own character, `Tomato`) uses the bike
default above; **Nik Skandaro** (`Spinach`) has up 1.66 / forward 2.17.

Built-in eye positions: Boomslang, Sidewinder, Taipan, Beluga, Hammerhead, Orca, Myth,
Northropi, Merlin, Rook, Saker. Other vehicles start from the original cockpit eye
`{0, -11.2, 77.7}`.

> **Not every vehicle has been driven yet.** The eye positions and other fine values may not
> fit some vehicles or characters. Adjust them to your taste while driving — your change is
> saved for that vehicle automatically, and the reset arrow brings the built-in value back.

---

## Features in detail

### Cockpit (from v1.2.0)

The eye sits on the vehicle's authored `PilotSeat` socket, re-read from the rendered mesh every
frame, so it never drifts from the visible seat. **Follow the vehicle** picks how the view
rotates with the vehicle:

| Option | |
| --- | --- |
| 1. Level horizon | Only the heading is followed. |
| 2. Follow hills *(default, most comfortable)* | Pitch follows slopes and jumps, smoothed and clamped to ±45°; roll stays level. |
| 3. Follow the vehicle, smoothed | Pitch, yaw and roll through a 0.15 s quaternion filter. |
| 4. Follow the vehicle, lightly smoothed | The same at 0.07 s. |
| 5. Exactly like the vehicle | Raw orientation. May cause motion sickness. |

The game's own third-person / over-the-shoulder / bonnet cameras are one key away.

### Game scenes and look back

When the game shows one of its own shots, the cockpit can stand down (and restore the pilot)
and take over again afterwards. Each has its own switch under **Game scenes and cameras**:

| Shot | |
| --- | --- |
| Race intro flyover | Before the race, and the scenes after it. |
| Outside view when crashing | The crash camera while you wreck or tumble. |
| Takedowns | The game's takedown camera, about 2 s. |
| Finish line camera | Your vehicle from outside, about 5 s before the results. |

**Look back** does two things. The game's own look back now works in the cockpit view: the game
shows its rear camera while you hold it, then you are back in the seat. And the look-back
hotkey (right stick up unless you change it) turns you round in the cockpit seat while you hold
it, so you see what is behind you from your own seat. Off: neither.

### Banking

The view's roll is `Banking% × MAX × tanh(roll × amount / MAX)`: 100 % gives the tuned lean
(amount 0.65, soft maximum 50.92°), 50 % half of it everywhere, 0 a level horizon.

Choosing **5. Exactly like the vehicle** sets the banking the game was designed with (Banking
200, maximum 90, amount 0.55 — like the original cockpit script); the other modes keep theirs.
Values you set for a vehicle win in every mode. The live lean of the vehicle and of your view
is shown under Banking.

### Cockpit shake

All motion is position (and pitch) on a damped spring — "a head on a spring" — so it starts and
settles naturally. It fades out while the game is paused and when the AI drives after the
finish. Groups: engine (idle, revving with W, driving), road (rumble growing with speed, bumps),
motion (acceleration, corners, drift, slipstream), boost (afterburner, ramjet, launch, energy
brake, nose lift, low hum, overheat shudder), landings and impacts.

**Boost lunges** shoot out, bounce back a little and ease back. "Lunges: farthest forward"
limits how far (12.5 cm by default); raise it for bigger lunges, lower it if a dashboard comes
too close.

### Landings

In the air the view rises a little (air lift) and comes down with the landing; the landing
presses the view down (deeper after longer jumps, never below "Lowest point below normal") and
leans it forward out of the pilot body; a separate stiff spring gives the **thud** at touchdown.
**Landing hits your head** adds a quick snap of the view angle (down and back, a small sideways
wobble) — moving the view's *position* reads in VR as the vehicle moving, turning its *angle*
reads as your head moving.

### Ride shake

*Off by default. For players who don't get motion sick, or who want even more sense of speed.
Works best with the follow modes 3 to 5.*

The normal cockpit shake moves only your view, so the world stays still and the cockpit seems
to shake. Ride shake moves part of the shake to the world: the vehicle body itself shakes
(`CustomisationRoot`; on podracers the pod mesh, at most 6 cm / 4°) and you move with it, so
the cockpit and the VR world both shake. Its amounts are saved per vehicle and have no
recommended value — what is fine differs from person to person:

| Value | |
| --- | --- |
| Trembling: world share | How much of the engine, road, afterburner and ramjet trembling goes to the world. 0 = only the vehicle, 100 = only the world. |
| Sways: world share | The same for road and hill sways, corner push and the landing press. Boost lunges always stay with the vehicle. |
| Smooth: driving | Softens the trembling and sways while just driving. Boosts and landings stay sharp. 0 = off, 300 = most. |
| Smooth: boosts and hits | Softens the afterburner and ramjet rumble, the corner push and the landing slam. |
| Trembling in the air | How much trembling is left while airborne. 0 = a quiet flight, 100 = as on the ground. |
| Landing slam | The vehicle slams down at touchdown and springs back. It grows with how fast you fell and how long you flew: a short hop barely bumps, a long flight hits hard. |

While the ramjet or afterburner is on, the cockpit keeps rumbling. "Ride shake: tilt" (Fine
tuning → All shaking: head spring) sets how much the body also tilts. Ride shake has its own masters per
vehicle type, apart from the cockpit shake masters.

### Body follow on jumps

Riders stand up in the air. While airborne the eye follows the pilot's chest bone (`spine_05`)
measured in the seat frame, scaled by "up" and "forward" (0 = not at all, 1 = as much as the
chest, up to 3), and settles back after landing.

### Near clip

The pilot body is one mesh with the hands, so it can't be hidden while keeping them. Instead the
near clip plane (`r.SetNearClipPlane`) is pushed out to the cut distance while the cockpit is
active (restored otherwise), pulled back during forward lunges so the dashboard isn't cut, and
pushed further while a landing presses the view down.

### Boost effects

Written into the game camera's post-process each frame: saturation, vignette and a short flash
per boost type, easing back after. The renderer settings they need (`r.Tonemapper.Quality`,
scene-colour fringe) are switched on only while an effect is visible and restored after.
Hit-stop uses global time dilation (always restored); the warp pulse scales UEVR's world scale
(+ = the world briefly shrinks away, − = it rushes at you).

### Brightness per track and weather

Some tracks and bright weather look blinding and washed out in VR while the monitor looks fine.
A map has several tracks (forward, reverse, variants) and each race has its own weather and time
of day, so values here are saved for the track **and** weather you race only (shown in light blue,
e.g. "Fallen Empire (Jakku) / Day"); every other one stays as the game shows it. They are written
into the game camera's post-process.

| Value | |
| --- | --- |
| Brightness | The whole picture, in camera stops (−1 = half as bright). |
| Bloom | The glow around bright things; in VR it can fog the whole view. |
| Colour strength (saturation) | How strong the colours are. |
| Contrast | Difference between dark and bright. |
| *More:* Tunnels (older): leave out the dark part | When the game measures how bright the picture is, it leaves out this share of the darkest pixels. It only starts to work above about 92. |
| *More:* Tunnels: brighten no further than | Dark places are not brightened beyond this. Raise it slowly if the outside looks blown out while you are in a tunnel. |
| *More:* Bright parts (colour gain) | Only the bright parts (sky, sunlit sand, glare); far down they turn grey. |

**VR picture for every track** holds values for every track and weather at once, against the
headset's paler, brighter look; where a track has its own value, that one is used. The outside
looking far too bright from inside a tunnel, and fine again once you are out, is the game's eye
adaptation brightening for the dark inside. **Saved tracks** lists every track and weather with
values; "This track and weather: back to the game's picture" forgets them, and "Compare: show the
game's picture" shows the difference while it is ticked.

### Race start

During the engine-start shot the cockpit waits; shortly after the engine starts the view flies
from the game camera into your seat, and the pilot's head is hidden only when you arrive. In the
game cameras the vehicle body (`CustomisationRoot`) hums with the engine, more while you rev.

### Menu screen positions

Some menu and result screens put the game camera far from where they are drawn. For those, a
saved UEVR camera offset is applied automatically (main menu, multiplayer menu, tour start /
logbook, result screens on every map, the engine-start shot). For any other screen: set
**UEVR → Camera → Camera Offset** until it looks right, then press **Save** in this section.
Never used in races.

---

## Known issues and notes

- **UEVR "Decoupled Pitch" must be off** (the profile has it off). With it on, UEVR levels the
  view after the script, so banking, "Follow hills" and the nose lift do nothing and the HUD
  moves instead. UEVR camera presets (Load Camera 0/1/2) can switch it back on — check this
  first if the view stops tilting.
- **HDR monitor: parts of the picture completely black?** HDR does not work through UEVR. The
  profile's `user_script.txt` turns it off at startup; keep both lines at 0 (if you changed them
  to 1, set them back):

  ```
  r.AllowHDR 0
  r.HDR.EnableHDROutput 0
  ```

  Still black? Turn Windows HDR off (Settings → System → Display → Use HDR) while playing in VR.
  (The first v2.1.0 notes said to set these to 1 — that was wrong.)
- **Stereo-mismatch settings.** Nero's `user_script.txt` also sets `r.SSR.Quality 0`,
  `r.AmbientOcclusionLevels 0`, `r.LensFlareQuality 0` and `r.SSGI.LeakFreeReprojection 0` at
  startup, and the `Renderer_r.DefaultFeature.AmbientOcclusion=1` and
  `Engine_r.AmbientOcclusionLevels=1` lines are removed from `cvars_standard.txt` /
  `cvars_data.txt`.
- **Command-list settings.** `user_script.txt` also sets
  `r.RHICmd.ParallelTranslate.MaxCommandsPerTranslate 0` and
  `r.RHICmd.ParallelTranslate.CombineSingleAndParallel 1` (engine defaults 256 / 0). They change
  how the CPU hands draw commands to the GPU (fewer, larger batches), not what you see. It can
  steady the frame rate a little when the CPU is the bottleneck; on a fast CPU there may be no
  difference at all. If anything seems off, delete those two lines.
- **Not every vehicle and character has been tested.** See the note in
  [Per-vehicle settings](#per-vehicle-settings-and-auto-save).
- Values in the Korean and English builds are the same; only the menu language differs.

---

## Character codenames

The pilot's outfit meshes use vegetable codenames; the menu shows both, e.g.
"Nik Skandaro (Spinach)". Mapped from each `RacerDef`'s `DefaultRecipe` and the `CharacterText`
string table (English names from the game files):

| Codename | Character | | Codename | Character |
| --- | --- | --- | --- | --- |
| Tomato01 / Tomato02 | Shade (your own character) | | Okra | Fola Kanjen |
| Spinach | Nik Skandaro | | Broccoli | Sen Fira |
| Asparagus | Katja Mox | | Carrot | Biddy Blas |
| Celeriac | Griff Halloran | | Radish | Malis Vazosk |
| Pumpkin | Ary Quill | | Potato | Lyren Shok |
| Pea | Soren Zaks | | Turnip | Kestar Bool |
| Cucumber | Goli & 02-R0 | | Swede | Sebulba (AI) |

Plane-type AI racers: Cabbage — Dud Bolt, Celery — Gasgano, Garlic — Teemto Pagalies,
Onion — Ben Quadinaros, Pepper — Ody Mandrell.

---

## Files

In the UEVR profile (`%APPDATA%\UnrealVRMod\SWGR-Win64-Shipping\`):

| File | |
| --- | --- |
| `scripts/swgr_vr_cockpit.lua` | The script. |
| `data/swgr_vr_settings.json` | Shared settings, hotkeys, shared fine-tuning values you changed. |
| `data/swgr_vr_vehicles.json` | Per-vehicle values: `eyes`, `feel` (% amounts), `detail` (fine tuning and Ride shake), `pilotFollow` (per character); `maps` (brightness per track and weather); `legacy` / `moved` (values of older vehicle names, while they are carried over). Only what you changed. |
| `data/swgr_vr_settings_backup_format1.json` | Your settings file as an older version left it, kept once when v2.1.1 first tidied it. |
| `data/swgr_vr_views.json` | Menu screen positions you saved. |
| `fonts/NanumGothic-Regular.ttf` | Korean menu font (Korean profile only; Nanum Gothic, SIL Open Font License, `fonts/OFL.txt`). |

Delete a `data` file to start over from the defaults. The log goes to UEVR's `log.txt`, lines
start with `[SWGR VR]`.

---

## Building from source

```
src/            the script, in sections (_header, 00_core … 90_menu, _footer), all in English;
                lang_ko.lua = the Korean menu text, added only to the Korean build
profile/        the UEVR profile files (config, cameras, cvars, user_script, v1.x validation notes)
profile_ko/     extra files for the Korean profile only (the menu font and its license)
tests/          run_tests.py + mock.lua: the script against a fake game; upgrade, vehicle name and
                picture tests (see tests/README.md)
build.py        builds dist/EN|KO/swgr_vr_cockpit.lua; "release" builds the packages
```

- `python build.py` → `dist/EN/swgr_vr_cockpit.lua`, `dist/KO/swgr_vr_cockpit.lua`.
  Each `src/NN_*.lua` is wrapped in `do … end`. Picture options still being worked on are in
  `src/65_picture.lua` but off in this build (`PIC_LAB`, set by `build.py`). The English build contains no Korean at all; the
  Korean build is the same code plus `lang_ko.lua`.
- `python build.py release [PAK_DIR]` → `release/EN/` and `release/KO/`, each with
  `SWGR-Win64-Shipping.zip` (the profile) and `swgr_vr_cockpit.lua`, and (with `PAK_DIR`) the
  pak mod zip in `release/`.
- `python tests/run_tests.py dist/EN/swgr_vr_cockpit.lua - next` runs the script in a fake game:
  menu (every widget clicked; duplicate IDs, tree / width / disabled balance, no `%` in texts),
  the engine-start shot, a race with every boost, landings, drift, impacts, pause, camera
  switches, hotkeys, a vehicle change and a script reset. Arguments: the script, a data folder
  with json files (or `-`), and the ImGui width API to fake (`next` / `push` / `none`). It needs
  LuaJIT's `lua51.dll` next to it (not included; e.g. the one shipped with OBS Studio). LuaJIT is
  Lua 5.1, so the script avoids 5.3+ operators.

**Menu text** — write English in the code: `tr('Text')` for labels, `tip('Text')` for tooltips,
`help('Text')` for notes. In the Korean build `tr` looks the text up in `lang_ko.lua`
(`['Text'] = '…'`); text without an entry simply stays English, so a missing translation never
breaks anything.

**Adding a value** — register it where it is used: `V.tunable(section, key, recommended, min,
max, label, tooltip)`; read it with `V.val(key)` (the current vehicle's value, else its
defaults). Add the key to `TUNE_LAYOUT` in `90_menu.lua` so it shows under the right topic
(anything not listed shows under "Other"), and the label / tooltip to `lang_ko.lua` for Korean.
Write the explanation for someone who has never seen the menu: what it feels like, when to raise
or lower it, what 0 does.

**Design notes** from v1.2.0 still hold for the cockpit section (`10_cockpit.lua`): seat
anchoring on `PilotSeat`, one rotation function (`cameraRotation`) for headset and desktop view,
smoothing keyed to `os.clock()`, standing down for intro / crash cameras. The add-on sections hook
in after the cockpit has placed the view (`V.runHooks`: banking → feel → intro) and run their
per-tick work from one engine tick, each protected on its own.
