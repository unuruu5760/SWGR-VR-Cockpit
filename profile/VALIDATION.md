# Release validation — v1.1.1

Checked on 8 October 2026.

## Projection correction

UEVR's source defines **Raw / default** as index 0 and **Symmetrical** as index 1
for both projection controls. Both axes in the v1.1.0 package and installed
profile were set to 1. The v1.1.1 package and installed profile now set both to 0.
The config files were compared with their originals; only these two values
changed. The release builder checks both values and rejects duplicate entries.

The running game's selected settings were also changed to 0 and read back as 0
through the UEVR API. This confirms the selected GUI values, not a live rendering
change: the runtime caches its eye projection matrices, so restart the game to
ensure they are rebuilt using the defaults.

The camera script, saved cockpit preferences and installed console commands
were preserved byte-for-byte. Projection overrides are not referenced by the
camera script. UEVR's [release notes](https://github.com/praydog/UEVR/releases/tag/1.04)
describe symmetrical projection as a shader compatibility option that can cost
performance. Visual correctness across all tracks/vehicles and the FPS change
with Raw / default have not been measured in this update.

## Lua execution checks inherited from v1.1.0

The unchanged distributed script was executed for v1.1.0 in Lua 5.4 through `lupa`, against a small
mock of the reflected UEVR/game API. All 14 behavior checks passed:

1. Legacy settings load defaults and acquire the authored cockpit seat.
2. Native mode restores modified pilot visibility and releases stereo and both
   game camera caches; it subsequently leaves native visibility changes alone.
3. Cycle requests run on the game thread and reach all three native positions.
4. Re-entering the cockpit retains the pilot preference and does not recenter again.
5. F6/F7 trigger once per press, without cycling repeatedly while held.
6. Cinematic yielding restores the pilot and stops cockpit overrides; disabling
   the option resumes the cockpit. The ignition camera does not trigger yielding.
7. Wrecked/tumbling states honor native versus first-person crash selection.
8. Seat edits clear stale render samples and save all options together.
9. Pilot lock produces matching stereo and spectator rotation.
10. Invalid camera/pilot modes do not change or save settings.
11. Script reset restores the pilot's original hidden flags.
12. Saved native mode does not hide/recenter the pilot at startup; all saved
    cockpit options remain available when returning to the cockpit.
13. Missing camera components and invalid pawns stop cleanly without retry loops.
14. Malformed camera/pilot/eye options fall back to valid defaults.

The release ZIP is checked for CRC errors, exact expected filenames, byte-for-byte
agreement with the staging files, default options, and required UEVR settings.
Its SHA-256 is supplied alongside the archive.

## Live native camera probe from v1.1.0

The running game's `VehicleCameraComponent.OnChangeCamera` was invoked three
times on the local skimmer. The active camera stack changed through three distinct
values and returned to its starting value. Its loaded native camera definitions
were `DA_BonnetCam_Skimmer`, `DA_VehicleOverTheShoulder_Skimmer`, and
`DA_ThirdPersonCam_Skimmer`. The release calls that same reflected engine function
rather than reproducing the native cameras with custom positional offsets.

This live probe verifies the engine's native cycle. The full updated script and
new UI/hotkeys were checked with the Lua fixture; they were not hot-reloaded into
the game session used for that probe. Restart the game to use the installed update.

## Historical cockpit coverage

`VALIDATION-v1.0.0.md` preserves the earlier live measurements: 2,180 eye views,
61 passing numerical checks, four vehicle archetypes, cockpit camera cycling,
headset movement and pilot visibility. These measurements were not rerun for
v1.1.0 or v1.1.1 and are not presented as validation of the new controls or the
projection defaults.

Physical headset comfort, all cosmetic variants and a complete live race test
of every new option remain outside the validation completed for this release.
