# Release validation — v1.0.0

Tested in the live game on 7 October 2026 with UEVR build 100726swgrp2+0-e2bfe2f4 and OpenXR Simulator.

The tests force-loaded the game's own Arcade events to create fully configured vehicles. Vehicle classes covered Car (landspeeder), Bike, Skimmer, and Plane (podracer). One root model was exercised in each class.

| Test phase | Recorded eye views | Speed range (mph) |
| --- | ---: | ---: |
| car-right-final | 220 | 76.1–123.7 |
| car-left-final | 220 | 0.0–46.6 |
| car-left-highspeed | 180 | 124.7–148.0 |
| car-neutral-final | 100 | 154.3–154.3 |
| car-headshift-final | 100 | 154.3–154.3 |
| car-camera-cycle-final | 160 | 129.3–147.0 |
| bike-right-final | 200 | 182.9–217.9 |
| bike-left-final | 200 | 197.0–227.9 |
| skimmer-right-final | 200 | 152.5–168.8 |
| skimmer-left-final | 200 | 159.4–188.5 |
| plane-right-final | 200 | 141.4–310.6 |
| plane-left-final | 200 | 152.1–201.5 |

All 61 numerical checks passed across 2,180 eye views (1,090 stereo frames):

- Final base camera equals the rendered PilotSeat socket plus the fixed seat-local eye offset, within 0.001 cm.
- With a neutral headset, the stereo midpoint stays at that eye point during acceleration and both steering directions.
- A 20 cm lateral / 10 cm longitudinal headset shift produces the expected displacement; 30-degree yaw and 10-degree pitch remain active.
- Eye separation remains 6.4 cm in the simulator; no extra headset-height or acceleration offset is added.
- Captures contain complete left/right eye pairs, and the cockpit script reports zero errors.

Pilot visibility was checked live: head-only leaves the body and hand bones visible while hiding the separate head mesh; full-pilot mode hides both local pilot meshes; visible mode restores them. The saved head-only setting survived a fresh game launch and vehicle replacements. Rendered cockpit views were inspected for all four vehicle classes.

The initial acceleration separation was traced to simulator WASD moving its reported headset over six metres from the centered seat. The test runtime was corrected so game-window WASD does not move the simulated headset. A separate OpenXR reference-space correction removed an erroneous 1.7 m eye offset. These simulator fixes are installed locally and are not required by a compliant physical-headset runtime or bundled in this release.

These are observed live-test results, not a guarantee for every future game/backend version or every cosmetic variation.
