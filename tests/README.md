# Tests

`run_tests.py` loads the built script into LuaJIT together with `mock.lua` (a strict fake UEVR /
game: unknown fields are errors) and plays a scripted session: menus without a vehicle, the
engine-start shot, a race with every boost, landings, drift, impacts, pause, camera switches,
hotkeys (including setting a key), a vehicle change and a script reset. The menu is drawn idle
and with every widget clicked; duplicate widget IDs, unbalanced tree / width / disabled calls and
`%` in texts or tooltips are reported.

```
python tests/run_tests.py dist/EN/swgr_vr_cockpit.lua - next
python tests/run_tests.py dist/KO/swgr_vr_cockpit.lua "%APPDATA%\UnrealVRMod\SWGR-Win64-Shipping\data" push
```

Arguments: the script, a folder with the `data` json files (or `-` for a fresh start), and the
ImGui item-width API to fake (`next`, `push` or `none`). The result ends with
`PROBLEMS 0` / `RESULT: OK`.

Needs LuaJIT's `lua51.dll` in this folder (not included; for example the one shipped with OBS
Studio). LuaJIT is Lua 5.1 while UEVR runs Lua 5.4, so the script avoids 5.3+ operators, and
`math.atan(y, x)` gives wrong numbers here (no error).
