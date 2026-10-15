# v2.0.1 — 15 October 2026

- Podracers in the campaign's memory races (pawn class `VBP_Plane_Memory_C`) were not
  recognised as a vehicle: the vehicle menus stayed greyed out and the podracer defaults did not
  apply. The vehicle type is now read from the first word of the class name.

# v2.0.0 — 15 October 2026

By ody, built on the UEVR profile and VR cockpit by Nero, madscy and elliotttate, running on
joeyhodge's UEVR backend. In the cockpit the vehicle sat still and speed was hard to feel; this
release makes the seat move. One script, `scripts/swgr_vr_cockpit.lua` (English or Korean menu),
replaces `swgr_cockpit_camera.lua`.

**Cockpit (kept from v1.2.0)**
- Seat anchoring on `PilotSeat`, the five camera-lock modes, pilot visibility, intro / crash
  camera handling and the game-camera cycle are unchanged. Default camera lock: Follow hills.
- Default hotkeys are now F3 (cockpit / game cameras), F4 (next game camera), F5 (add-on effects
  on / off). Keyboard keys are set by pressing them; each action can also have a controller
  combo (Back + button).
- Its own settings files (`data/swgr_vr_*.json`); `swgr-cockpit-options.json` is not read.

**Added**
- Cockpit shake on a damped spring: engine idle / revving / driving, road rumble and bumps,
  corner and acceleration push, drift rattle, slipstream buffeting, impacts. Fades out while
  paused and when the AI drives.
- Boost punch: afterburner / ramjet / race-start lunges (shoot out, bounce back, ease back;
  "Lunges: farthest forward" limit), nose lift, low hum while boosting, overheat shudder.
- Boost effects: colour / vignette / flash in the camera post-process; hit-stop (time dilation)
  and warp pulse (VR world scale, + or −) at ramjet ignition and the race start. Renderer cvars
  are switched only while an effect is visible and always restored.
- Landings: air lift, press down with a floor, lean forward out of the pilot body, a separate
  thud spring at touchdown, and "Landing hits your head" (a quick snap of the view angle).
- Banking limit: view roll = % × max × tanh(roll × amount / max).
- Body follow on jumps: the eye follows the pilot's chest bone while airborne; saved per vehicle
  and per character.
- Near clip: `r.SetNearClipPlane` pushed out while the cockpit is active, pulled back on forward
  lunges, pushed further on landings; restored otherwise.
- Race start: watch the engine-start shot, then the view flies into the seat; car body engine
  hum in the game cameras.
- Menu screen positions: saved UEVR camera offsets for menus and result screens, common ones
  built in.
- Per-vehicle auto-save: changes made while driving are saved for that vehicle only; untouched
  values follow the defaults (own → vehicle built-in → vehicle-type built-in → shared →
  recommended). Built-in tuning per vehicle type (Bike: Taipan, Car: Beluga, Skimmer: Saker /
  Merlin, Plane: Myth), eye positions for 11 vehicles, per-character body follow on bikes.
  Not every vehicle has been tested; adjust to taste.
- "Add-on effects on" switch: off = behaves like the original v1.2.0 cockpit.
- Korean / English builds: the code is English only; the Korean build adds the menu text table
  `lang_ko.lua`; the Korean profile ships its menu font (Nanum Gothic, SIL OFL) in `fonts`,
  an explanation on every item, fine tuning grouped by topic, "Saved vehicles" editor.
- Character display names in the menu (codename → name from the game's RacerDefs).

**Profile**
- Nero's stereo-mismatch fixes in `user_script.txt`: `r.SSR.Quality 0`,
  `r.AmbientOcclusionLevels 0`, `r.LensFlareQuality 0`, `r.SSGI.LeakFreeReprojection 0`,
  `r.AllowHDR 0`, `r.HDR.EnableHDROutput 0`; `Renderer_r.DefaultFeature.AmbientOcclusion=1` and
  `Engine_r.AmbientOcclusionLevels=1` removed from `cvars_standard.txt` / `cvars_data.txt`.
  If the world turns black with only the UI visible, remove the two HDR lines and use the
  read-only `Engine.ini` method from v1.2.0 (see README).
- UEVR "Decoupled Pitch" must stay off (it levels the view and disables banking / hills / nose
  lift); the profile has it off.

**Optional pak mod** (separate download, `Paks\~mods`): transparent start / finish black bars,
transition and pause panels, results backgrounds and the sign-in check panel; the race-failed
background at 40 %.

# v1.2.0 — 10 October 2026

- Expanded **Camera lock** from two modes to five: track (level horizon,
  unchanged default), **Follow hills** (smoothed pitch clamped to ±45°, level
  roll), **Full motion smoothed** (0.15 s quaternion filter on pitch/yaw/roll),
  **Full motion lightly smoothed** (0.07 s), and raw pilot lock.
- Smoothing filters the vehicle quaternion (normalized lerp with double-cover
  handling) rather than individual Euler angles, so yaw wrap and tumbles do not
  snap. Filters are real-time based and snap after gaps over one second
  (cinematics, camera yields) instead of swooping.
- Options file: new `camera_lock` field; the older `lock_to_track` boolean is
  still read and written for compatibility.
- Documented the game's silent auto-HDR (washed-out colors in the headset) and
  the `Engine.ini` fix, including why the file must be read-only and why the
  cvar must not be toggled at runtime. See the README.

# v1.1.1 — 8 October 2026

- Restored Horizontal Projection and Vertical Projection to **Raw / default**.
  The previous profile forced Symmetrical on both axes. These compatibility
  overrides are not required by the cockpit script and may cost performance.
- Retained the v1.1.0 camera script and all cockpit/native camera controls.
- Restart after updating to rebuild UEVR's cached eye projections.

# v1.1.0 — 8 October 2026

- Added cockpit/game camera selection, saved between launches.
- F6 toggles cockpit/game cameras. F7 and **Cycle game camera** use the game's
  own camera cycle: both third-person views and the forward bonnet first-person
  view. The game's normal Change Camera control works in game mode.
- Added track/pilot camera lock, intro cinematic and first-person crash options,
  and adjustable seat eye position from the supplied camera script.
- Restore the local pilot when returning to game cameras or yielding to an
  intro/crash camera; preserve the selected cockpit pilot visibility preference.
- Keep desktop/spectator camera rotation consistent with the selected camera lock.
- Clear stale rendered eye offsets immediately after seat adjustments.
- Allow the game's cinematic crash camera in the profile so the new crash option
  can control whether the cockpit overrides it.
