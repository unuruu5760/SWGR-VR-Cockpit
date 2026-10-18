# Tests

All of them load the built script into LuaJIT together with `mock.lua` (a strict fake UEVR /
game: unknown fields are errors). Each ends with `RESULT: OK` (exit code 1 if anything failed).

| Test | What it checks |
| --- | --- |
| `run_tests.py` | A scripted session: menus without a vehicle, the engine-start shot, a race with every boost, landings, drift, impacts, pause, camera switches, hotkeys (including setting a key), a vehicle change and a script reset. The menu is drawn idle and with every widget clicked; duplicate widget IDs, unbalanced tree / width / disabled calls and `%` in texts or tooltips are reported. |
| `upgrade_test.py` | Upgrading never loses what players saved: every released version (git tags `v*`) is built, saves settings and per-vehicle values for plain and mixed vehicles, then the new script loads those files and drives the same vehicles. Every value must be what it was. |
| `vehicle_names_test.py` | The name a vehicle gets (where its values are saved) for every model of every type, parts swapped between models, recipes of every kind or none, parts loading late or breaking off: right from the first moment, never changing during a race. |
| `public_build_test.py` | The public build: the picture options still being worked on are left out of the menu and not used (values a working build saved for them stay in the file), the game's areas are not read, the picture controls work per track and weather, and every menu text of the Korean build has its Korean (controller button names stay as they are). |
| `picture_weather_test.py` | Brightness per track and weather and the older whole-map values moving to a race; in a working build also the options still being worked on. |

```
python tests/run_tests.py dist/EN/swgr_vr_cockpit.lua - next
python tests/run_tests.py dist/KO/swgr_vr_cockpit.lua "%APPDATA%\UnrealVRMod\SWGR-Win64-Shipping\data" push
python tests/upgrade_test.py dist/EN/swgr_vr_cockpit.lua .
python tests/vehicle_names_test.py dist/EN/swgr_vr_cockpit.lua
python tests/public_build_test.py dist/KO/swgr_vr_cockpit.lua dist/EN/swgr_vr_cockpit.lua
python tests/picture_weather_test.py dist/KO/swgr_vr_cockpit.lua dist/EN/swgr_vr_cockpit.lua
```

`run_tests.py` arguments: the script, a folder with the `data` json files (or `-` for a fresh
start), and the ImGui item-width API to fake (`next`, `push` or `none`). `upgrade_test.py` needs
git and the repository folder (it builds the tagged versions).

Needs LuaJIT's `lua51.dll` in this folder (not included; for example the one shipped with OBS
Studio). LuaJIT is Lua 5.1 while UEVR runs Lua 5.4, so the script avoids 5.3+ operators, and
`math.atan(y, x)` gives wrong numbers here (no error).
