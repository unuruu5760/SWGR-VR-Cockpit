"""Tests the one-file UEVR script outside the game with LuaJIT (lua51.dll copied from OBS) and a fake
game (mock.lua): syntax, loading, a scripted race (menu, engine start shot, boosts, landings, pause,
camera switch, vehicle change, script reset) and the menu with every widget clicked.
usage: python tools/luacheck/run_tests.py <script.lua> [data dir with json files | -] [next|push|none]
Exit code 1 if anything failed.
Note: LuaJIT is Lua 5.1 (UEVR uses 5.4): no integer/bit operators in the script, math.atan(y, x)
uses one argument here (wrong numbers, no error)."""
import ctypes, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
L = ctypes.CDLL(os.path.join(HERE, 'lua51.dll'))
L.luaL_newstate.restype = ctypes.c_void_p
L.luaL_openlibs.argtypes = [ctypes.c_void_p]
L.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
L.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
L.lua_tolstring.restype = ctypes.c_char_p
L.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
L.lua_settop.argtypes = [ctypes.c_void_p, ctypes.c_int]
L.lua_close.argtypes = [ctypes.c_void_p]

def lua_literal(v):
    if isinstance(v, bool): return 'true' if v else 'false'
    if v is None: return 'nil'
    if isinstance(v, (int, float)): return repr(float(v)) if isinstance(v, float) else str(v)
    if isinstance(v, str): return json.dumps(v)
    if isinstance(v, list): return '{' + ', '.join(lua_literal(x) for x in v) + '}'
    if isinstance(v, dict): return '{' + ', '.join('[' + json.dumps(str(k)) + '] = ' + lua_literal(x) for k, x in v.items()) + '}'
    raise TypeError(type(v))

def run(state, code, name):
    b = code.encode('utf-8')
    if L.luaL_loadbuffer(state, b, len(b), ('=' + name).encode()) != 0:
        msg = L.lua_tolstring(state, -1, None).decode('utf-8', 'replace'); L.lua_settop(state, 0)
        return False, 'SYNTAX: ' + msg
    if L.lua_pcall(state, 0, 1, 0) != 0:
        msg = L.lua_tolstring(state, -1, None).decode('utf-8', 'replace'); L.lua_settop(state, 0)
        return False, 'RUNTIME: ' + msg
    r = L.lua_tolstring(state, -1, None)
    L.lua_settop(state, 0)
    return True, (r.decode('utf-8', 'replace') if r else '')

SCENARIO = r'''
local out = {}
local function note(s) out[#out + 1] = s end
local function frames(n, dt) for i = 1, n do MOCK.frame(dt or 1 / 72) end end
local S = SWGR_VR_CAM
local function dump(t)
    if type(t) ~= 'table' then return type(t) == 'number' and string.format('%.3g', t) or tostring(t) end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do local x = t[k]; if x == nil then x = t[tonumber(k)] end; parts[#parts + 1] = k..'='..dump(x) end
    return '{'..table.concat(parts, ' ')..'}'
end
local function sharedSig()
    local c = SWGR_VR.cfg
    return dump(c.detail)..dump({ c.roll, c.engine, c.road, c.motion, c.boost, c.landing })
end
note('loaded per-vehicle %: '..dump(SWGR_VR.veh.feel))
note('loaded per-vehicle detail: '..dump(SWGR_VR.veh.detail))
note('loaded shared detail: '..dump(SWGR_VR.cfg.detail))
-- UEVR Decoupled Pitch on (a camera preset switched it on): the cockpit must turn it off while it
-- places the view and give it back afterwards
MOCK.mods.VR_DecoupledPitch = 'true'
-- main menu, no vehicle
MOCK.pawn = nil
MOCK.viewTargetClass = 'BP_GfnPlayerController_C'
frames(60)
local e0, sig0 = SWGR_VR.eyeFor(nil), sharedSig(); MOCK.menu('idle'); MOCK.menu('click')
note('no vehicle: shared values untouched by the menu = '..tostring(sharedSig() == sig0))
MOCK.menu('click')
note('no vehicle: default eye z '..tostring(SWGR_VR.eyeFor(nil)[3])..' (must stay '..tostring(e0[3])..')')
MOCK.menu('idle'); MOCK.menu('click'); MOCK.menu('click'); MOCK.menu('idle')
note('after menu clicks: camera '..tostring(S.cameraMode)..' (click mode picks the last option)')
S.setCameraMode('cockpit')
SWGR_VR.cfg.detail.rjHold, SWGR_VR.cfg.detail.abHold, SWGR_VR.cfg.detail.nodMax = 0.5, 0.5, 10   -- exercise the lunge hold
-- race: engine start shot
local pawn, v = MOCK.makeVehicle('Bike', 'Taipan')
MOCK.pawn = pawn
MOCK.viewTargetClass = 'FuseCinematicCameraActor'
v.IgnitionStatus = 0
frames(120)
note('in the engine start shot: cockpit enabled = '..tostring(S.enabled)..', model '..tostring(SWGR_VR.model))
v.IgnitionStatus = 3
frames(72 * 3)
note('3 s after the engine start: intro state '..tostring(SWGR_VR.introState)..', blend '..string.format('%.2f', SWGR_VR.introBlend))
frames(72 * 3)
MOCK.viewTargetClass = 'VBP_Bike_C'
frames(72)
note('racing: cockpit enabled = '..tostring(S.enabled)..', anchor '..tostring(S.anchor ~= nil)..', view placed '..S.applied..', decoupled pitch '..tostring(MOCK.mods.VR_DecoupledPitch)..'')
-- launch, drive, afterburner, ramjet, landing, drift, drafting, impact
v.IgnitionPhase = 2; frames(5); v.IgnitionPhase = 3; frames(30)
v.SpeedMPH, v.Throttle, v.RPMScale = 150, 1, 0.8
v.Velocity = { X = 6700, Y = 0, Z = 0 }
frames(72)
v.AfterburnerState = 0
for i = 1, 72 do v.AfterburningTime = i / 72; MOCK.frame(1 / 72) end
v.AfterburnerState = 1; v.AfterburningTime = 0; frames(36)
v.RamjetState = 2; frames(5); v.RamjetState = 3
for i = 1, 144 do v.RamjetHeat = i / 144; MOCK.frame(1 / 72) end
v.RamjetState = 4; frames(36); v.RamjetState = 6; v.RamjetHeat = 0; frames(36)
v.TimeInAir = 0.1; v.OnGroundScale = 0; MOCK.chestUp = 15
for i = 1, 72 do v.TimeInAir = i / 72; v.Velocity = { X = 6700, Y = 0, Z = -300 - i * 5 }; MOCK.frame(1 / 72) end
v.TimeInAir = 0; v.LandingState = 1; frames(10)
v.Velocity = { X = 6700, Y = 0, Z = 0 }; v.LandingState = 2; v.OnGroundScale = 1; MOCK.chestUp = 0; frames(72)
v.Drifting = true; v.DriftScale = 0.8; v.DraftingState = 2; frames(72); v.Drifting = false; v.DraftingState = 0
v.Velocity = { X = 2000, Y = 1500, Z = 0 }; frames(3)
note('after the race events: view ok, last x '..string.format('%.1f', MOCK.lastPos.x))
SWGR_VR.cfg.detail.rjHold, SWGR_VR.cfg.detail.abHold, SWGR_VR.cfg.detail.nodMax = nil, nil, nil
-- pause
MOCK.paused = true; frames(72); MOCK.paused = false; frames(10)
-- hotkey: game cameras (car body shake path), then back
MOCK.keyDown = 'Key_F3'; frames(2); MOCK.keyDown = nil; frames(5)
note('after F3: camera '..S.cameraMode..string.format(', nose lift on the model: %d calls, largest %.1f deg, now %.2f deg', MOCK.tiltCalls or 0, MOCK.maxTilt or 0, pawn.RootComponent.RelativeRotation.Pitch))
v.SpeedMPH, v.Throttle = 0, 0.5; frames(72)
note('car body shake calls (game camera): '..tostring(MOCK.carShakeCalls))
MOCK.keyDown = 'Key_F3'; frames(2); MOCK.keyDown = nil; frames(5)
note('after F3 again: camera '..S.cameraMode)
-- add-on effects off / on with a hotkey (compare with the original)
SWGR_VR.cfg.keyExtras = 'F5'
MOCK.keyDown = 'Key_F5'; frames(2); MOCK.keyDown = nil
v.AfterburnerState = 0; for i = 1, 36 do v.AfterburningTime = i / 72; MOCK.frame(1 / 72) end; v.AfterburnerState = 1
note('extras after F5: '..tostring(SWGR_VR.cfg.extras)..', feel down '..string.format('%.2f', SWGR_VR.feelDown)..', last near clip cmd '..tostring(MOCK.commands[#MOCK.commands]))
MOCK.menu('idle')
MOCK.keyDown = 'Key_F5'; frames(2); MOCK.keyDown = nil; frames(10)
note('extras after F5 again: '..tostring(SWGR_VR.cfg.extras))
-- keyboard hotkey: click, then press a key (no action may fire while setting it)
local rc0 = MOCK.recenters or 0
SWGR_VR.cfg.keyToggle = 'K'
SWGR_VR.keyCaptureStart('Recenter'); frames(2)
MOCK.keyDown = 'Key_K'; frames(3); MOCK.keyDown = nil; frames(2)
note('captured key: recenter '..tostring(SWGR_VR.cfg.keyRecenter)..', toggle '..tostring(SWGR_VR.cfg.keyToggle)..', camera '..S.cameraMode..', recenters during capture '..((MOCK.recenters or 0) - rc0))
MOCK.keyDown = 'Key_K'; frames(2); MOCK.keyDown = nil; frames(2)
note('K pressed again: recenters '..((MOCK.recenters or 0) - rc0))
SWGR_VR.keyCaptureStart('Cycle'); frames(2); MOCK.keyDown = 'Key_Escape'; frames(2); MOCK.keyDown = nil
note('escape: capture '..tostring(SWGR_VR.keyCapture)..', cycle key '..tostring(SWGR_VR.cfg.keyCycle))
SWGR_VR.keyCaptureStart('Cycle'); frames(72); MOCK.keyDown = 'Key_W'; frames(2); MOCK.keyDown = nil
note('menu closed: capture '..tostring(SWGR_VR.keyCapture)..', cycle key '..tostring(SWGR_VR.cfg.keyCycle))
SWGR_VR.cfg.keyToggle, SWGR_VR.cfg.keyRecenter = 'F3', 'None'
-- the menu with a vehicle
MOCK.menu('idle'); MOCK.menu('click'); MOCK.menu('idle')
S.setCameraMode('cockpit'); frames(30)
-- another vehicle
local pawn2, v2 = MOCK.makeVehicle('Plane', 'Myth')
MOCK.pawn = pawn2; frames(72 * 4)
note('new vehicle: '..tostring(SWGR_VR.model)..' type '..tostring(SWGR_VR.vtype)..', character '..tostring(SWGR_VR.pilot))
local m2 = SWGR_VR.model
SWGR_VR.setOwnVal('feel', m2, 'roll', 50); SWGR_VR.setOwnVal('detail', m2, 'rollMax', 30)
note(string.format('own banking: %d (shared %d), own max %.1f (shared %.1f)', SWGR_VR.pctFor(m2, 'roll'), SWGR_VR.sharedPct('roll'), SWGR_VR.val('rollMax'), SWGR_VR.sharedVal('rollMax')))
frames(5)
SWGR_VR.clearOwnVal('feel', m2, 'roll'); SWGR_VR.clearOwnVal('detail', m2, 'rollMax')
note(string.format('after clearing: banking %d, max %.1f, entries left: feel %s detail %s', SWGR_VR.pctFor(m2, 'roll'), SWGR_VR.val('rollMax'),
    tostring(SWGR_VR.veh.feel[m2] ~= nil), tostring(SWGR_VR.veh.detail[m2] ~= nil)))
local before = SWGR_VR.followFor()[1]
SWGR_VR.setFollow(0.5, 0.2); frames(5)
note('body follow saved for the character: '..tostring(SWGR_VR.followOwn(SWGR_VR.model, SWGR_VR.pilot, 'followUp'))..', vehicle value '..tostring(SWGR_VR.ownVal('detail', SWGR_VR.model, 'followUp')))
note(string.format('body follow: shared %.2f -> own %.2f / %.2f', before, SWGR_VR.followFor()[1], SWGR_VR.followFor()[2]))
SWGR_VR.cfg.bodyFollow = true; MOCK.menu('idle'); MOCK.menu('click'); MOCK.menu('idle')
SWGR_VR.resetFollow(); note(string.format('body follow after reset: %.2f', SWGR_VR.followFor()[1]))
MOCK.menu('click'); MOCK.menu('idle')
frames(72)
-- crash camera / tumbling
v2.IsTumbling = function() return true end; frames(30); v2.IsTumbling = function() return false end; frames(30)
-- the campaign's memory races use another podracer class (VBP_Plane_Memory_C): still a Plane
local pawn3 = MOCK.makeVehicle('Plane', 'Tarchia', 'VBP_Plane_Memory_C')
MOCK.pawn = pawn3; frames(72 * 4)
note('memory-race podracer: '..tostring(SWGR_VR.model)..' type '..tostring(SWGR_VR.vtype)..', ramjet '..tostring(SWGR_VR.val('ramjet')))
MOCK.menu('idle')
-- vehicle gone (back to menu), script reset
MOCK.pawn = nil; frames(72)
MOCK.fire('reset')
frames(10)
local saved = {}
for k in pairs(MOCK.files) do saved[#saved + 1] = k end
table.sort(saved)
note('files written: '..table.concat(saved, ', '))
note('console commands: '..#MOCK.commands..' (last: '..tostring(MOCK.commands[#MOCK.commands])..')')
note('dilation now: '..tostring(MOCK.dilation)..', world scale: '..tostring(MOCK.mods.VR_WorldScale)..', decoupled pitch after: '..tostring(MOCK.mods.VR_DecoupledPitch))
note('menu labels drawn: '..#MOCK.ui.labels)
local bad = {}
for _, l in ipairs(MOCK.logs) do
    local low = l:lower()
    if low:find('error') or low:find('failed') or low:find('warning') then bad[#bad + 1] = l end
end
for _, e in ipairs(MOCK.errors) do bad[#bad + 1] = 'CALLBACK ERROR '..e end
note('PROBLEMS '..#bad)
for i = 1, math.min(#bad, 40) do note('  '..bad[i]) end
note('--- log (first 60 lines)')
for i = 1, math.min(#MOCK.logs, 60) do note('  '..MOCK.logs[i]) end
return table.concat(out, '\n')
'''

def main():
    script_path = sys.argv[1]
    data_dir = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != '-' else None
    width_api = sys.argv[3] if len(sys.argv) > 3 else 'next'
    src = open(script_path, encoding='utf-8').read()
    mock = open(os.path.join(HERE, 'mock.lua'), encoding='utf-8').read()
    files = {}
    if data_dir:
        for f in os.listdir(data_dir):
            if f.endswith('.json'):
                try: files[f] = json.load(open(os.path.join(data_dir, f), encoding='utf-8'))
                except Exception as e: print('skip', f, e)
    st = L.luaL_newstate(); L.luaL_openlibs(st)
    failed = False
    for code, name in ((mock, 'mock'), ('MOCK.files = ' + lua_literal(files) + '\nMOCK.setWidthApi(' + json.dumps(width_api) + ')\nreturn ""', 'files'),
                       (src, os.path.basename(script_path)), (SCENARIO, 'scenario')):
        ok, res = run(st, code, name)
        if not ok:
            print('FAILED in', name, ':', res); failed = True; break
        if res: print(res)
        if name == 'scenario' and 'PROBLEMS 0' not in res: failed = True
    L.lua_close(st)
    print('RESULT:', 'FAIL' if failed else 'OK')
    sys.exit(1 if failed else 0)

main()
