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
-- the game's takedown and finish line cameras: the cockpit steps aside while they show (each can be off)
local function placedWith(cls, n)
    MOCK.viewTargetClass = cls
    local a0 = S.applied; frames(n); local placed = S.applied - a0
    MOCK.viewTargetClass = 'VBP_Bike_C'; frames(10)
    return placed
end
local tdOn = placedWith('BP_TakedownCameraActor_C', 36)
local fcOn = placedWith('BP_PlayerFinishedCam_C', 36)
local sqOn = placedWith('FuseSequenceCameraActor', 36)
S.showTakedownCamera, S.showFinishCamera = false, false
local tdOff = placedWith('BP_TakedownCameraActor_C', 36)
local fcOff = placedWith('BP_PlayerFinishedCam_C', 36)
S.showTakedownCamera, S.showFinishCamera = true, true
-- the game's own look back (End): the cockpit steps aside while it shows (can be off)
local function lookBack()
    v.LookBackRequested = true
    local a0 = S.applied; frames(20); local placed = S.applied - a0
    v.LookBackRequested = false; frames(10)
    return placed
end
local lbOn = lookBack()
S.showLookBack = false
local lbOff = lookBack()
S.showLookBack = true
-- the VR picture test: written into the camera's post-process only when touched
local pps = MOCK.cm.CameraCachePrivate.POV.PostProcessSettings
pps.bOverride_AutoExposureBias, pps.AutoExposureBias = nil, 0
frames(5)
local untouched = tostring(pps.bOverride_AutoExposureBias)
local picMap = SWGR_VR.picMapName()
for k, val in pairs({ picExp = -1, picHi = 60, picBloom = 50, picSat = 120, picLow = 97, picMinEV = 8 }) do SWGR_VR.setPicVal(picMap, k, val) end
frames(5)
note(string.format('VR picture adaptation: dark part ignored %.0f (high %.1f), least light %.3f', pps.AutoExposureLowPercent, pps.AutoExposureHighPercent, pps.AutoExposureMinBrightness))
note(string.format('picture per map (%s = %s): untouched writes exposure %s; set: exposure %.2f (override %s), bright parts %.2f, bloom %.3f, saturation %.2f',
    tostring(picMap), SWGR_VR.mapLabel(picMap), untouched, pps.AutoExposureBias, tostring(pps.bOverride_AutoExposureBias), pps.ColorGainHighlights.W, pps.BloomIntensity, pps.ColorSaturation.W))
-- another map: nothing of it
MOCK.world = 'L_Other_LOOP_B'; frames(72 * 5)
pps.bOverride_AutoExposureBias = nil; frames(3)
note('picture per map: on another map exposure override '..tostring(pps.bOverride_AutoExposureBias)..' (nil = untouched)')
MOCK.world = nil; frames(72 * 5)
SWGR_VR.clearPicMap(picMap)
frames(2)
-- the game's camera change button is kept from the game while racing in the cockpit: RB with the
-- default controls, the right stick click with the alternative ones
local function pad(b) local st = { Gamepad = { wButtons = b } }; MOCK.fire('xinput', 0, 0, st); return st.Gamepad.wButtons end
frames(2)
local rbOut, r3Out = pad(0x0200), pad(0x0080); pad(0)
MOCK.controlScheme = 1; S.schemeNext = 0; frames(2)
local rbAlt, r3Alt = pad(0x0200), pad(0x0080); pad(0)
MOCK.controlScheme = nil; S.schemeNext = 0; frames(2)
note(string.format('camera change button while racing (racing %s): default controls RB %d, right stick click %d; alternative controls RB %d, right stick click %d (0 = kept from the game)',
    tostring(S.racing), rbOut, r3Out, rbAlt, r3Alt))
note(string.format('look back (End): cockpit placed the view %d times in 20 frames (0 = the game camera shows), with the switch off %d', lbOn, lbOff))
-- look back from the cockpit seat: the right stick pushed up (the default)
local function stick(y) local st = { Gamepad = { wButtons = 0, sThumbRX = 0, sThumbRY = y } }; MOCK.fire('xinput', 0, 0, st) end
frames(5); local yawL0 = MOCK.lastRot.y
stick(30000); frames(3); local yawL1 = MOCK.lastRot.y
stick(0); frames(3); local yawL2 = MOCK.lastRot.y
note(string.format('look back in the seat (right stick up): turned %.0f deg, after letting go %.0f deg',
    ((yawL1 - yawL0 + 180) % 360) - 180, ((yawL2 - yawL0 + 180) % 360) - 180))
note(string.format('game cameras: cockpit placed the view %d / %d / %d times in 36 frames of takedown / finish line / sequence camera; with their switches off %d / %d',
    tdOn, fcOn, sqOn, tdOff, fcOff))
-- launch, drive, afterburner, ramjet, landing, drift, drafting, impact
-- the start without the throttle: no launch; with it: the launch
local launches = 0
for _, l in ipairs(MOCK.logs) do if l:find('launch at', 1, true) then launches = launches + 1 end end
local thr0 = v.Throttle
v.Throttle = 0; v.IgnitionPhase = 2; frames(5); v.IgnitionPhase = 3; frames(60)
local afterIdle = 0
for _, l in ipairs(MOCK.logs) do if l:find('launch at', 1, true) then afterIdle = afterIdle + 1 end end
v.IgnitionPhase = 2; frames(5); v.Throttle = 1; v.IgnitionPhase = 3; frames(30)
local afterGas = 0
for _, l in ipairs(MOCK.logs) do if l:find('launch at', 1, true) then afterGas = afterGas + 1 end end
note(string.format('race start launch: without the throttle %d, with it %d', afterIdle - launches, afterGas - afterIdle))
v.Throttle = thr0
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
-- overall shake strength per vehicle type: saved amounts and default amounts apart (another type's don't count)
SWGR_VR.cfg.shakeDefault_Plane, SWGR_VR.cfg.shakeSaved_Plane, SWGR_VR.cfg.shakeDefault_Bike = 50, 200, 10
SWGR_VR.setOwnVal('feel', SWGR_VR.model, 'engine', 80)
note(string.format('overall shake (%s): engine (saved 80) -> %.0f, road (default) -> %.0f', tostring(SWGR_VR.vtype), SWGR_VR.feelPct('engine'), SWGR_VR.feelPct('road')))
SWGR_VR.clearOwnVal('feel', SWGR_VR.model, 'engine')
SWGR_VR.cfg.shakeDefault_Plane, SWGR_VR.cfg.shakeSaved_Plane, SWGR_VR.cfg.shakeDefault_Bike = 100, 100, 100
SWGR_VR.cfg.rideDefault_Plane, SWGR_VR.cfg.rideSaved_Plane = 50, 150
SWGR_VR.setOwnVal('detail', SWGR_VR.model, 'shakeAlongMove', 40)
note(string.format('ride shake master (%s): trembling share (default %s) -> %.0f, sways share (saved 40) -> %.0f',
    tostring(SWGR_VR.vtype), tostring(SWGR_VR.val('shakeAlong')), SWGR_VR.rideVal('shakeAlong'), SWGR_VR.rideVal('shakeAlongMove')))
SWGR_VR.clearOwnVal('detail', SWGR_VR.model, 'shakeAlongMove')
SWGR_VR.cfg.rideDefault_Plane, SWGR_VR.cfg.rideSaved_Plane = 100, 100
-- (test) shake along with the vehicle: the body takes the trembling, the view keeps the rest
local vs = MOCK.lastVehicle
vs.SpeedMPH, vs.Throttle, vs.IgnitionStatus = 120, 1, 3; vs.Velocity.X = 5000; frames(36)   -- (moving: not the pause screen)
-- afterburner rumble: the view shakes more while it burns than just after
do
    local function zSwing(n, burning)
        local lo, hi = 1e9, -1e9
        for i = 1, n do
            if burning then vs.AfterburnerState, vs.AfterburningTime = 0, 1 + i / 72 else vs.AfterburnerState = 1 end
            MOCK.frame(1 / 72); lo, hi = math.min(lo, MOCK.lastPos.z), math.max(hi, MOCK.lastPos.z)
        end
        return hi - lo
    end
    local burnSwing = zSwing(72, true)
    frames(72)
    local afterSwing = zSwing(72, false)
    note(string.format('afterburner rumble: view up / down swing %.2f cm while burning, %.2f cm after', burnSwing, afterSwing))
    vs.AfterburnerState = 1
end
-- the amounts are values per vehicle
SWGR_VR.setOwnVal('detail', SWGR_VR.model, 'shakeAlong', 40)
note(string.format('shake along amount: own %s for %s, shared %s', tostring(SWGR_VR.val('shakeAlong')), tostring(SWGR_VR.model), tostring(SWGR_VR.sharedVal('shakeAlong'))))
SWGR_VR.clearOwnVal('detail', SWGR_VR.model, 'shakeAlong')
local n0 = MOCK.alongCalls or 0
SWGR_VR.cfg.shakeAlongOn, SWGR_VR.cfg.detail.shakeAlong, SWGR_VR.cfg.detail.shakeAlongLand = true, 100, 150
local moveMax, tiltMax = 0, 0
for _ = 1, 72 do
    MOCK.frame(1 / 72)
    local l, r = MOCK.bodyRoot.RelativeLocation, MOCK.bodyRoot.RelativeRotation
    moveMax = math.max(moveMax, math.abs(l.X), math.abs(l.Y), math.abs(l.Z))
    tiltMax = math.max(tiltMax, math.abs(r.Pitch), math.abs(r.Roll))
end
note(string.format('shake along: body moved %d times, up to %.2f cm and %.2f deg, possible %s', (MOCK.alongCalls or 0) - n0, moveMax, tiltMax,
    tostring(not SWGR_VR.shakeAlongInfo.failed)))
-- smooth (driving): the body's trembling jumps less from frame to frame; boosts stay sharp
local function jerk(n)
    local prev, worst = nil, 0
    for _ = 1, n do
        MOCK.frame(1 / 72)
        local z = MOCK.bodyRoot.RelativeLocation.Z
        if prev then worst = math.max(worst, math.abs(z - prev)) end
        prev = z
    end
    return worst
end
SWGR_VR.cfg.detail.shakeAlongSmooth = 0; local sharp = jerk(72)
SWGR_VR.cfg.detail.shakeAlongSmooth = 300; local soft3 = jerk(72)
SWGR_VR.cfg.detail.shakeAlongSmooth = 100; local soft = jerk(72)
vs.RamjetState, vs.RamjetHeat = 3, 0; frames(20); local rjSoft = jerk(72)
SWGR_VR.cfg.detail.shakeAlongSmooth = 0; local rjSharp = jerk(72)
vs.RamjetState = 0; frames(30)
note(string.format('shake along smooth: biggest body step %.3f cm at 0 %%, %.3f cm at 100 %%, %.3f cm at 300 %%; with the ramjet %.3f at 100 %%, %.3f at 0 %%', sharp, soft, soft3, rjSoft, rjSharp))
-- second smooth: boosts and hits get soft too (the ramjet's rumble jumps less)
SWGR_VR.cfg.detail.shakeAlongSmooth2 = 300
vs.RamjetState, vs.RamjetHeat = 3, 0.5; frames(20); local rj2Soft = jerk(72)
SWGR_VR.cfg.detail.shakeAlongSmooth2 = 0; local rj2Sharp = jerk(72)
vs.RamjetState, vs.RamjetHeat = 0, 0; frames(30)
note(string.format('shake along smooth 2 (boosts, hits): biggest body step with the ramjet %.3f cm at 300 %%, %.3f cm at 0 %%', rj2Soft, rj2Sharp))
-- boosting: the body keeps rumbling through the ramjet (cold) and a long afterburner
local function zRange(n)
    local lo, hi = 1e9, -1e9
    for _ = 1, n do MOCK.frame(1 / 72); local z = MOCK.bodyRoot.RelativeLocation.Z; lo, hi = math.min(lo, z), math.max(hi, z) end
    return hi - lo
end
local plain = zRange(72)
vs.RamjetState, vs.RamjetHeat = 3, 0.1; frames(150); local rjMid = zRange(72); vs.RamjetState = 0; frames(60)
vs.AfterburnerState, vs.AfterburningTime = 0, 2; frames(150); local abLong = zRange(72); vs.AfterburnerState = 1; frames(60)
note(string.format('shake along while boosting: body up / down range %.2f cm driving, %.2f cm mid ramjet, %.2f cm long afterburner', plain, rjMid, abLong))
MOCK.menu('idle')
-- airborne: no trembling; the landing slams the body down
vs.TimeInAir, vs.OnGroundScale = 1.2, 0; frames(30)
local airMove, airFull = 0, 0
SWGR_VR.cfg.detail.shakeAlongAir = 0
for _ = 1, 20 do MOCK.frame(1 / 72); airMove = math.max(airMove, math.abs(MOCK.bodyRoot.RelativeLocation.Z)) end
SWGR_VR.cfg.detail.shakeAlongAir = 100
for _ = 1, 20 do MOCK.frame(1 / 72); airFull = math.max(airFull, math.abs(MOCK.bodyRoot.RelativeLocation.Z)) end
SWGR_VR.cfg.detail.shakeAlongAir = 50
note(string.format('shake along in the air: %.3f cm at 0 %%, %.3f cm at 100 %%', airMove, airFull))
local function fallTo(speed, n) local z0 = vs.Velocity.Z; for i = 1, n do vs.Velocity.Z = z0 + (-speed - z0) * i / n; MOCK.frame(1 / 72) end end
fallTo(1200, 30)
vs.Velocity.Z, vs.TimeInAir, vs.OnGroundScale, vs.LandingState = 0, 0, 1, 2
local landDrop, landTilt, landUp, landRoll, eyeMove = 0, 0, 0, 0, 0
for _ = 1, 72 do
    MOCK.frame(1 / 72)
    eyeMove = math.max(eyeMove, math.abs(SWGR_VR.feelDown or 0), math.abs(SWGR_VR.feelFwd or 0))
    local l, r = MOCK.bodyRoot.RelativeLocation, MOCK.bodyRoot.RelativeRotation
    landDrop, landTilt, landUp = math.min(landDrop, l.Z), math.min(landTilt, r.Pitch), math.max(landUp, l.Z)
    landRoll = math.max(landRoll, math.abs(r.Roll))
end
vs.LandingState = 0
note(string.format('shake along: in the air the body moves %.3f cm; landing: body down %.1f cm, bounce up %.1f cm, nose %.1f deg, roll %.1f deg; eye in the cockpit moved %.2f cm',
    airMove, landDrop, landUp, landTilt, landRoll, eyeMove))
local function landAfter(speed, airTime)
    vs.TimeInAir, vs.OnGroundScale, vs.LandingState = airTime or 0.6, 0, 1
    fallTo(speed, 30)
    vs.Velocity.Z, vs.TimeInAir, vs.OnGroundScale, vs.LandingState = 0, 0, 1, 2
    local drop, nose = 0, 0
    for _ = 1, 72 do
        MOCK.frame(1 / 72)
        local l, r = MOCK.bodyRoot.RelativeLocation, MOCK.bodyRoot.RelativeRotation
        drop, nose = math.min(drop, l.Z), math.min(nose, r.Pitch)
    end
    vs.LandingState = 0; frames(36)
    return drop, nose
end
SWGR_VR.cfg.detail.shakeAlongLand = 100
local hopD, hopN = landAfter(300)
local midD, midN = landAfter(1200)
local bigD, bigN = landAfter(3000)
-- the time in the air: the same fast fall after a short hop over a ledge and after a long flight
local ledgeD, ledgeN = landAfter(2000, 0.1)
local longD, longN = landAfter(2000, 2.0)
note(string.format('shake along landing slam at 100 %%, falling 2000 cm/s: after a short hop (0.5 s in the air) %.1f cm / %.1f deg, after a long flight (2.4 s) %.1f cm / %.1f deg',
    ledgeD, ledgeN, longD, longN))
SWGR_VR.cfg.detail.shakeAlongLand = 0
local hop0D, hop0N = landAfter(300)
local big0D, big0N = landAfter(3000)
note(string.format('shake along landing without the slam (0 %%, Pushes and sways %s): small hop %.1f cm / %.1f deg, high drop %.1f cm / %.1f deg',
    tostring(SWGR_VR.val('shakeAlongMove')), hop0D, hop0N, big0D, big0N))
SWGR_VR.cfg.detail.shakeAlongLand = 150
note(string.format('shake along landing slam at 100 %%: small hop (falling 300 cm/s) %.1f cm / %.1f deg, medium (1200) %.1f cm / %.1f deg, high drop (3000) %.1f cm / %.1f deg',
    hopD, hopN, midD, midN, bigD, bigN))
SWGR_VR.cfg.shakeAlongOn = false; frames(5)
local rl, rr = MOCK.bodyRoot.RelativeLocation, MOCK.bodyRoot.RelativeRotation
note(string.format('shake along off: body back at %.2f / %.2f / %.2f, tilt %.2f / %.2f', rl.X, rl.Y, rl.Z, rr.Pitch, rr.Roll))
-- a podracer: the pod's container hangs on nothing and is left alone; the pod's own mesh under it moves
-- (a little), the container never
MOCK.podLayout = true
local podPawn = MOCK.makeVehicle('Plane', 'Myth')
MOCK.podLayout = nil
MOCK.pawn = podPawn; frames(72 * 3)
local pod = MOCK.lastVehicle
pod.SpeedMPH, pod.Throttle, pod.IgnitionStatus = 150, 1, 3; pod.Velocity.X = 5000
SWGR_VR.cfg.shakeAlongOn = true
local podMoves, contMoves = MOCK.podCalls or 0, MOCK.alongCalls or 0
frames(72)
pod.TimeInAir, pod.OnGroundScale = 1.2, 0; frames(30)
pod.TimeInAir, pod.OnGroundScale, pod.LandingState = 0, 1, 2; frames(72); pod.LandingState = 0
SWGR_VR.cfg.detail.shakeAlongSmooth = 100
local podSm = MOCK.podCalls or 0
frames(36)
note(string.format('podracer shake along smooth 100: pod mesh moved %d times', (MOCK.podCalls or 0) - podSm))
SWGR_VR.cfg.detail.shakeAlongSmooth = 0
note(string.format('podracer shake along: pod mesh moved %d times (up to %.1f cm), container moved %d times, possible %s',
    (MOCK.podCalls or 0) - podMoves, MOCK.podMax or 0, (MOCK.alongCalls or 0) - contMoves, tostring(not SWGR_VR.shakeAlongInfo.failed)))
pod.SpeedMPH, pod.Throttle = 0, 0; pod.Velocity.X = 0
SWGR_VR.cfg.shakeAlongOn = false; frames(5)
local pl = MOCK.podMesh.RelativeLocation
note(string.format('podracer shake along off: pod mesh back at %.2f / %.2f / %.2f', pl.X, pl.Y, pl.Z))
vs.SpeedMPH, vs.Throttle = 0, 0; vs.Velocity.X = 0; frames(10)
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
local nearCmds = 0
for _, c in ipairs(MOCK.commands) do if c:find('r.SetNearClipPlane', 1, true) then nearCmds = nearCmds + 1 end end
note('near clip commands in the whole run: '..nearCmds)
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
for i = 1, #MOCK.logs do if MOCK.logs[i]:find("landing slam", 1, true) then note("  "..MOCK.logs[i]) end end
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
