"""Brightness per track and weather: the picture values are saved for the track raced (reverse apart)
in the light its weather gives, and nowhere else; places without a race (menus, paddock) keep the
map's name; values older versions saved for a whole map go to the first race there that is read
(track and weather), never lost and never spread; a race that can't be read falls back to the map.
Labels in English and Korean.
usage: python tools/luacheck/picture_weather_test.py <EN script.lua> <KO script.lua>
Exit code 1 if anything failed."""
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


def run(st, code, name):
    b = code.encode('utf-8')
    if L.luaL_loadbuffer(st, b, len(b), ('=' + name).encode()) != 0 or L.lua_pcall(st, 0, 1, 0) != 0:
        msg = L.lua_tolstring(st, -1, None).decode('utf-8', 'replace'); L.lua_settop(st, 0)
        raise SystemExit('FAILED in %s: %s' % (name, msg))
    r = L.lua_tolstring(st, -1, None); L.lua_settop(st, 0)
    return r.decode('utf-8') if r else ''


COMMON = r'''
local V = SWGR_VR
local out, fails = {}, {}
local function note(s) out[#out + 1] = s end
local function check(what, got, want)
    if got ~= want then fails[#fails + 1] = what..': '..tostring(got)..' (want '..tostring(want)..')' end
end
local function frames(sec) for i = 1, math.floor(sec * 10) do MOCK.frame(0.1) end end
-- a race: the menus between, then the map with that track and weather
local function race(world, trak, cond, wait)
    MOCK.world = 'L_FrontEnd'; frames(2)
    MOCK.world, MOCK.trackDef, MOCK.condition = world, trak, cond
    frames(wait or 3)
end
local function file() V.saveVehNow(); return (MOCK.files['swgr_vr_vehicles.json'] or {}).maps or {} end
local function keys(t) local k = {}; for x in pairs(t) do k[#k + 1] = x end; table.sort(k); return table.concat(k, ' ; ') end
'''

CASES = r'''
-- 1. a new player: values only where they were set
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_SHORT_02_HARD', 'TrackCondition.Sunset')
local fe = V.picPlace()
check('Fallen Empire at sunset', fe, 'L_Mastiff_LOOP_A|Fallen Empire|forward|Sunset')
note('label: '..V.mapLabel(fe))
V.setPicVal(fe, 'picExp', -1); frames(1)
MOCK.menu('idle')
-- the menu's compare box: the game's picture while ticked, off by itself once the menu is closed
V.picCompare = true; V.picCompareSeen = V.t; MOCK.frame(0.1)
check('compare: the game picture', V.pic.active, false)
frames(2)
check('compare: off once the menu is closed', V.picCompare, false)
check('  values back', V.pic.active, true)
-- tone down glaring / lift dark places: local exposure, switched on in the renderer once when used
MOCK.commands = {}
V.setPicVal(fe, 'picGlare', 60); V.setPicVal(fe, 'picShadow', 20); frames(1)
check('glare scale', V.pic.glare and string.format('%.2f', V.pic.glare), '0.55')
check('shadow scale', V.pic.shadow and string.format('%.2f', V.pic.shadow), '0.85')
local on = 0
for _, c in ipairs(MOCK.commands) do if c == 'r.LocalExposure 1' then on = on + 1 end end
check('local exposure switched on once', on, 1)
V.setPicVal(fe, 'picGlare', 100); frames(1)
check('glare 100 as before', V.pic.glare and string.format('%.2f', V.pic.glare), '0.25')
V.setPicVal(fe, 'picGlare', 150); frames(1)
check('glare 150', V.pic.glare and string.format('%.3f', V.pic.glare), '0.125')
V.setPicVal(fe, 'picGlare', 200); frames(1)
check('glare 200 = the most', V.pic.glare and string.format('%.2f', V.pic.glare), '0.00')
V.setPicVal(fe, 'picGlare', 0); V.setPicVal(fe, 'picShadow', 0); frames(1)
check('  back to nothing', V.pic.glare, nil)
-- tunnels: toning down glaring places only in the game's own tunnels (its sound area boxes), faded in / out
local VOL = 'Class /Script/SweejAmbience.SweejAmbienceVolume'
local boxNo = 0
local function box(name, interior, x, y, z, yaw, sx, sy, sz, world, shaped)
    world = world or 'L_Mastiff_LOOP_A'
    boxNo = boxNo + 1
    local id = 'box'..boxNo
    -- (the area type as the game stores it: the enum's name before it)
    local kind = 'AATE_Gfn_Ambience_AreaTypeEnum::'..(interior and 'NewEnumerator1' or 'NewEnumerator0')
    local def = { get_fname = function() return { to_string = function() return name end } end,
                  AreaType = { Name = { to_string = function() return kind end } } }
    local c, s = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
    local hx, hy, hz = 100 * sx, 100 * sy, 100 * sz
    local function inside(p)
        local dx, dy, dz = p.X - x, p.Y - y, p.Z - z
        return math.abs(dx * c + dy * s) <= hx and math.abs(-dx * s + dy * c) <= hy and math.abs(dz) <= hz
    end
    return { get_address = function() return id end,
        get_full_name = function() return 'SweejAmbienceVolume /Game/Griffin/Maps/Planets/MASTIFF/'..world..'/'..world..'.'..world..':PersistentLevel.Vol' end,
        AmbienceComponent = { bUseComponentAreaType = false, AmbienceDefinition = def },
        -- (shaped by hand: the scale stays 1, the shape is in the brush)
        RootComponent = { RelativeLocation = { X = x, Y = y, Z = z }, RelativeRotation = { Pitch = 0, Yaw = shaped and 0 or yaw, Roll = 0 },
                          RelativeScale3D = shaped and { X = 1, Y = 1, Z = 1 } or { X = sx, Y = sy, Z = sz } },
        GetActorBounds = function(self, only, o, e, child)
            o.X, o.Y, o.Z = x, y, z
            e.X, e.Y, e.Z = math.abs(hx * c) + math.abs(hy * s), math.abs(hx * s) + math.abs(hy * c), hz
        end,
        EncompassesPoint = function(self, p, r, out)
            assert(type(out) == 'table' and type(p.X) == 'number', 'EncompassesPoint arguments')
            MOCK.encompassCalls = (MOCK.encompassCalls or 0) + 1
            if MOCK.noEncompass then return false end
            return inside(p)
        end }
end
-- (the vehicle stands at 1000, 2000, 300: in the narrow box; far out = only the outdoor one. UEVR's object
-- list stays empty for these boxes, as in the game: the engine's own list must find them)
MOCK.noObjectList = true
MOCK.pawn = MOCK.makeVehicle('Bike', 'Taipan')
local tf = MOCK.pawn.VehicleState.VehicleTransform
local IN, FAR = { X = 1000, Y = 2000, Z = 300 }, { X = 100000, Y = 100000, Z = 300 }
MOCK.objectsOf = { [VOL] = {
    box('SAD_Mastiff_Tracks_Interior_Small', true, 1000, 2000, 300, 30, 50, 10, 10),     -- 100 x 20 m, turned 30 degrees
    box('SAD_Mastiff_Tracks_Interior_Large', true, 1000, 2000, 300, 0, 160, 220, 90),     -- 320 x 440 m
    box('SAD_Mastiff_Tracks_Exterior_Large', false, 0, 0, 0, 0, 1400, 1400, 400),
    box('SAD_Other_Interior', true, 1000, 2000, 300, 0, 5, 5, 5, 'L_Other_Map'),         -- another map's, not gone yet
} }
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_SHORT_02_HARD', 'TrackCondition.Sunset')     -- (the boxes are read with the race)
tf.Translation = FAR; frames(1.5)
check('no tunnels set: nothing', V.pic.glare, nil)
V.setPicVal(fe, 'picTunnel', 100); frames(1)
check('tunnels, out in the open: nothing', V.pic.glare, nil)
check('  out: not a tunnel', V.picRoof(), false)
tf.Translation = IN; frames(0.2)
check('in for a moment (a bridge): nothing yet', V.pic.glare, nil)
frames(1.2)
check('in the tunnel: toned down as glare 100', V.pic.glare and string.format('%.2f', V.pic.glare), '0.25')
MOCK.ui.texts = {}; MOCK.menu('idle')
local roofLine = false
for _, l in ipairs(MOCK.ui.texts) do if l:find('Now: in a tunnel', 1, true) or l:find('지금: 터널 안', 1, true) then roofLine = true end end
check('menu says in a tunnel', roofLine, true)
-- a bridge: in for a moment only, never toned down
tf.Translation = FAR; frames(2)
local most = 1
for i = 1, 3 do tf.Translation = (i == 2) and IN or FAR; MOCK.frame(0.1); most = math.min(most, V.pic.glare or 1) end
frames(1)
check('passing under a bridge: never toned down', most, 1)
tf.Translation = IN; frames(1.5)
tf.Translation = FAR; frames(0.5)
check('out: fading', V.pic.glare ~= nil and V.pic.glare > 0.25 and V.pic.glare < 1, true)
frames(1)
check('out: the game\'s picture', V.pic.glare, nil)
V.setPicVal(fe, 'picGlare', 40); tf.Translation = IN; frames(1.5)
check('everywhere 40 + tunnels 100 in a tunnel: the stronger', V.pic.glare and string.format('%.2f', V.pic.glare), '0.25')
tf.Translation = FAR; frames(1.5)
check('  out: everywhere 40', V.pic.glare and string.format('%.2f', V.pic.glare), '0.70')
V.setPicVal(fe, 'picGlare', 0)
-- the game's areas can't be read on a map (their class missing): no Tunnels there, and the menu says so
MOCK.noAreaClass = true
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_SHORT_02_HARD', 'TrackCondition.Sunset'); tf.Translation = IN; frames(1.5)
check('no game areas: nothing', V.pic.glare, nil)
check('  the menu knows', V.picRoof(), nil)
MOCK.ui.texts = {}; MOCK.menu('idle')
local noLine = false
for _, l in ipairs(MOCK.ui.texts) do if l:find('could not be read on this map', 1, true) or l:find('게임 구역을 못 읽어서', 1, true) then noLine = true end end
check('  and says so', noLine, true)
MOCK.noAreaClass = nil
-- UEVR's object list when the engine's own list gives none
MOCK.noActorList, MOCK.noObjectList = true, nil
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_SHORT_02_HARD', 'TrackCondition.Sunset'); tf.Translation = IN; frames(1.5)
check('found through UEVR\'s object list too', V.picRoof(), true)
MOCK.noActorList, MOCK.noObjectList = nil, true
-- the game's own areas: a narrow indoor box = a tunnel; a wide indoor one or an outdoor one = not
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_SHORT_02_HARD', 'TrackCondition.Sunset')
frames(1.5)
local inT, ar = V.picRoof()
check('narrow indoor area: a tunnel', inT, true)
check('  the narrow one', ar and ar.name, 'SAD_Mastiff_Tracks_Interior_Small')
check('  toned down', V.pic.glare and string.format('%.2f', V.pic.glare), '0.25')
MOCK.ui.texts = {}; MOCK.menu('idle')
local areaLine = nil
for _, l in ipairs(MOCK.ui.texts) do if l:find('Game area', 1, true) or l:find('게임 구역', 1, true) then areaLine = l end end
note('menu: '..tostring(areaLine))
check('menu shows the area', areaLine ~= nil and areaLine:find('30 m', 1, true) ~= nil and areaLine:find('Interior_Small', 1, true) ~= nil, true)
-- 15 m off the narrow box's middle line, across it (its own Y, turned 30 degrees): out of it, in the wide one
tf.Translation = { X = 1000 - 750, Y = 2000 + 1299, Z = 300 }; frames(1.5)
inT, ar = V.picRoof()
check('beside the narrow tunnel, in the giant indoor box: a tunnel too (the game calls it indoors)', inT, true)
check('  the giant one', ar and ar.name, 'SAD_Mastiff_Tracks_Interior_Large')
check('  its width told', ar and ar.narrow > 10000, true)
MOCK.ui.texts = {}; MOCK.menu('idle')
for _, l in ipairs(MOCK.ui.texts) do if l:find('Game area', 1, true) or l:find('게임 구역', 1, true) then areaLine = l end end
note('menu: '..tostring(areaLine))
-- 30 m along it (its own X): in the tunnel again (only right if the box's turn is used)
tf.Translation = { X = 1000 + 2598, Y = 2000 + 1500, Z = 300 }; frames(1.5)
inT, ar = V.picRoof()
check('along the turned tunnel: in it', ar and ar.name, 'SAD_Mastiff_Tracks_Interior_Small')
-- far out: only the outdoor box
tf.Translation = { X = 100000, Y = 100000, Z = 300 }; frames(1.5)
inT, ar = V.picRoof()
check('out in the desert: not a tunnel', inT, false)
check('  the outdoor one', ar and ar.name, 'SAD_Mastiff_Tracks_Exterior_Large')
tf.Translation = { X = 1000, Y = 2000, Z = 300 }
-- a wide tunnel inside a wreck: Interior_Large too, but 60 m across (the game, 2026-10-18)
table.insert(MOCK.objectsOf[VOL], box('SAD_Mastiff_Tracks_Interior_Large', true, 50000, 2000, 300, 0, 100, 30, 30))   -- 200 x 60 m
frames(2.5)
tf.Translation = { X = 50000, Y = 2000, Z = 300 }; frames(1.5)
inT, ar = V.picRoof()
check('wide tunnel (Interior_Large, 60 m across): a tunnel', inT, true)
check('  its width', ar and ar.narrow and ar.narrow >= 6000 and ar.narrow <= 7000, true)
MOCK.ui.texts = {}; MOCK.menu('idle')
for _, l in ipairs(MOCK.ui.texts) do if l:find('Game area', 1, true) or l:find('게임 구역', 1, true) then areaLine = l end end
note('menu: '..tostring(areaLine))
tf.Translation = { X = 1000, Y = 2000, Z = 300 }
-- the engine's check not working on a map: the turned cubes from their scale, the same answers
MOCK.noEncompass = true
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_SHORT_02_HARD', 'TrackCondition.Sunset'); frames(1.5)
check('no engine check: the narrow box still a tunnel', V.picRoof(), true)
tf.Translation = { X = 1000 - 750, Y = 2000 + 1299, Z = 300 }; frames(1.5)
inT, ar = V.picRoof()
check('  beside it: the giant box', ar and ar.name, 'SAD_Mastiff_Tracks_Interior_Large')
tf.Translation = { X = 1000, Y = 2000, Z = 300 }
MOCK.noEncompass = nil
-- boxes shaped by hand (scale 1: only the engine's check knows their shape), one streamed in later, one
-- named open by the game though typed Interior
MOCK.objectsOf = { [VOL] = {
    box('SAD_Corgi_Tracks_Interior_Tunnel', true, 1000, 2000, 300, 0, 60, 12, 10, 'L_Corgi_LOOP_A', true),     -- 120 m long, 24 m across
    box('SAD_Corgi_Tracks_Interior_Cave', true, 1000, -40000, 300, 0, 100, 100, 20, 'L_Corgi_LOOP_A', true),  -- 200 m across
} }
race('L_Corgi_LOOP_A', 'TRAK_COR_Loop_A_REV', 'TrackCondition.Overcast.Snow'); V.setPicVal(V.picPlace(), 'picTunnel', 100); frames(1.5)
inT, ar = V.picRoof()
check('shaped tunnel box: a tunnel', inT, true)
-- (without the engine's check, as in the game: their bounds)
MOCK.noEncompass = true
race('L_Corgi_LOOP_A', 'TRAK_COR_Loop_A_REV', 'TrackCondition.Overcast.Snow'); frames(1.5)
inT, ar = V.picRoof()
check('shaped tunnel box, no engine check: a tunnel by its bounds', inT, true)
check('  its width', ar and ar.narrow and ar.narrow >= 2400 and ar.narrow <= 3400, true)
tf.Translation = { X = 1000, Y = 2000 + 1500, Z = 300 }; frames(1.5)
check('  15 m beside it: not', V.picRoof(), false)
tf.Translation = { X = 1000, Y = 2000, Z = 300 }
MOCK.noEncompass = nil
race('L_Corgi_LOOP_A', 'TRAK_COR_Loop_A_REV', 'TrackCondition.Overcast.Snow'); frames(1.5)
check('  its width felt for', ar and ar.narrow and ar.narrow >= 2400 and ar.narrow <= 3400, true)
tf.Translation = { X = 1000, Y = -40000, Z = 300 }; frames(1.5)
inT, ar = V.picRoof()
check('a cave 200 m across: indoors, a tunnel', inT, true)
check('  its width told', ar and ar.narrow > 15000, true)
MOCK.ui.texts = {}; MOCK.menu('idle')
for _, l in ipairs(MOCK.ui.texts) do if l:find('Game area', 1, true) or l:find('게임 구역', 1, true) then areaLine = l end end
note('menu: '..tostring(areaLine))
tf.Translation = { X = 1000, Y = 2000, Z = 300 }
table.insert(MOCK.objectsOf[VOL], box('SAD_Dalmatian_Tracks_Exterior_Overhang', true, 1000, 30000, 300, 0, 10, 10, 10, 'L_Corgi_LOOP_A', true))
frames(2.5)
tf.Translation = { X = 1000, Y = 30000, Z = 300 }; frames(1.5)
inT, ar = V.picRoof()
check('streamed-in box named Overhang (typed Interior): not a tunnel', inT, false)
check('  taken as outdoors', ar and ar.interior, false)
tf.Translation = { X = 1000, Y = 2000, Z = 300 }
V.setPicVal(V.picPlace(), 'picTunnel', 0)
MOCK.objectsOf, MOCK.noObjectList = nil, nil
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_SHORT_02_HARD', 'TrackCondition.Sunset')
V.setPicVal(fe, 'picTunnel', 0); MOCK.pawn = nil; frames(0.5)
-- the older control: as before, and only while the new one is 0
V.setPicVal(fe, 'picLow', 85); frames(0.2)
check('older control 85: low', V.pic.low, 85)
check('older control 85: high', V.pic.high, 90)
V.setPicVal(fe, 'picLow', 95); frames(0.2)
check('older control 95: high', V.pic.high, 96.5)
V.setPicVal(fe, 'picLow', 0); frames(0.2)
check('nothing measured differently', V.pic.low, nil)
check('applied there', V.pic.active and V.pic.exp ~= nil, true)
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_SHORT_02', 'TrackCondition.BlueHour')
check('same track, other weather (BlueHour is lit as dawn)', V.picPlace(), 'L_Mastiff_LOOP_A|Fallen Empire|forward|Dawn')
note('label: '..V.mapLabel(V.picPlace()))
check('  untouched there', V.picVal('picExp'), 0)
check('  nothing applied', V.pic.active, false)
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_REV_HARD', 'TrackCondition.Sunset')
check('the other track, reversed, same weather', V.picPlace(), 'L_Mastiff_LOOP_A|The War Fields|reverse|Sunset')
note('label: '..V.mapLabel(V.picPlace()))
check('  untouched there', V.picVal('picExp'), 0)
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_FWD', 'TrackCondition.Scorching')
check('forward, scorching (lit as day)', V.picPlace(), 'L_Mastiff_LOOP_A|The War Fields|forward|Day')
race('L_Mastiff_LOOP_A', 'TRAK_TT_MAS_LOOP_A_SHORT_02', 'TrackCondition.Sunset')
if V.TRACK_NAMES.TRAK_TT_MAS_LOOP_A_SHORT_02 then
    check('another mode of the same track and weather shares', V.picPlace(), fe)
    check('  its value', V.picVal('picExp'), -1)
end
check('file', keys(file()), 'L_Mastiff_LOOP_A|Fallen Empire|forward|Sunset')

-- 2. the map in the level's other spelling, snow
race('L_Corgi_LOOP_A', 'TRAK_COR_Loop_A_REV', 'TrackCondition.Overcast.Snow')
check('Ando Prime, reverse, snow', V.picPlace(), 'L_Corgi_LOOP_A|'..tostring(V.TRACK_NAMES.TRAK_COR_Loop_A_REV)..'|reverse|Overcast')
note('label: '..V.mapLabel(V.picPlace()))
race('L_Dalmatian_A', 'TRAK_DAL_LOOP_A_FWD', 'TrackCondition.Night.Wet')
note('label (rain): '..V.mapLabel(V.picPlace()))
race('L_Corgi_Plane', 'TRAK_COR_PLANE_FWD', 'TrackCondition.Afternoon.Dry.MEM')
note('label (memory race): '..V.mapLabel(V.picPlace()))

-- 2b. the picture for every track: used where a place has none of its own; a place's own replaces it
V.setPicBase('picBlack', 40); V.setPicBase('picTemp', -20); frames(0.5)
check('every track: deeper blacks here (no own value)', V.picVal('picBlack', 'L_Mastiff_LOOP_A|The War Fields|forward|Day'), 40)
check('  written', V.pic.offset and string.format('%.3f', V.pic.offset), '-0.008')
check('  colour temperature written', V.pic.temp, 6100)
V.setPicVal(V.picPlace(), 'picBlack', 0); frames(0.5)
check('a place\'s own 0 replaces it', V.picVal('picBlack'), 0)
check('  kept (it differs from every track\'s)', V.picOwn('picBlack'), 0)
check('  nothing written for it', V.pic.offset, nil)
V.setPicVal(V.picPlace(), 'picBlack', 40); frames(0.5)
check('set back to every track\'s value: not kept apart', V.picOwn('picBlack'), nil)
V.saveNow()
local sv = MOCK.files['swgr_vr_settings.json'] or {}
check('every track\'s values in the settings file', sv.picBase and sv.picBase.picBlack, 40)
V.setPicVal(V.picPlace(), 'picVib', 50); frames(0.5)
check('vibrance: bright / middle / dark', V.pic.satHi and string.format('%.3f/%.3f/%.3f', V.pic.satHi, V.pic.satMid, V.pic.satLo), '1.150/1.150/1.075')
V.setPicVal(V.picPlace(), 'picVib', 0)
-- one slider for both: the floor, and the inside lifted back with a tone curve (the colour gamma) worked out
-- from it, the ratio scaling that
local function gammaFor(pair, ratio)
    local d = 7 * pair / 100
    return 1 / (1 - math.min(0.75, ratio / 100 * d / (6 + d)))
end
V.setPicVal(V.picPlace(), 'picPair', 100); frames(0.5)
check('pair 100: floor 15 EV', V.pic.minBright and string.format('%.3f', V.pic.minBright), string.format('%.3f', 0.012 * 2 ^ 15))
check('  gamma 13 / 6', V.pic.gamma and string.format('%.4f', V.pic.gamma), string.format('%.4f', gammaFor(100, 100)))
check('  no local exposure lift from it', V.pic.shadow, nil)
local gps = MOCK.cm.CameraCachePrivate.POV.PostProcessSettings
check('  gamma written into the camera', gps.bOverride_ColorGamma == true and string.format('%.4f', gps.ColorGamma.W), string.format('%.4f', gammaFor(100, 100)))
V.setPicVal(V.picPlace(), 'picPair', 57); frames(0.5)
check('pair 57: floor about 12 EV', V.pic.minBright and string.format('%.3f', V.pic.minBright), string.format('%.3f', 0.012 * 2 ^ (8 + 7 * 0.57)))
V.setPicVal(V.picPlace(), 'picPairLift', 50); frames(0.5)
check('  ratio 50: less lift', V.pic.gamma and string.format('%.4f', V.pic.gamma), string.format('%.4f', gammaFor(57, 50)))
V.setPicVal(V.picPlace(), 'picPairLift', 200); V.setPicVal(V.picPlace(), 'picPair', 100); frames(0.5)
check('  at most gamma 4', V.pic.gamma and string.format('%.2f', V.pic.gamma), '4.00')
V.setPicVal(V.picPlace(), 'picShadow', 100); frames(0.5)
check('  own Lift dark places: its own, as before', V.pic.shadow and string.format('%.2f', V.pic.shadow), '0.25')
V.setPicVal(V.picPlace(), 'picMinEV', 15.5); frames(0.5)
check('  own floor higher: it is used', V.pic.minBright and string.format('%.3f', V.pic.minBright), string.format('%.3f', 0.012 * 2 ^ 15.5))
V.setPicVal(V.picPlace(), 'picMinEV', 0); V.setPicVal(V.picPlace(), 'picShadow', 0)
-- keep the inside's contrast: the share lifted by the local exposure (the way before) against the curve
V.setPicVal(V.picPlace(), 'picPairLift', 100); V.setPicVal(V.picPlace(), 'picPairKeep', 100); frames(0.5)
check('keep contrast 100: no curve', V.pic.gamma, nil)
check('  the local lift as before', V.pic.shadow and string.format('%.4f', V.pic.shadow), string.format('%.4f', 2.5 / 9.5))
V.setPicVal(V.picPlace(), 'picPairKeep', 50); frames(0.5)
check('  50: half the curve', V.pic.gamma and string.format('%.4f', V.pic.gamma), string.format('%.4f', 1 / (1 - 0.5 * 7 / 13)))
check('  and half the local lift', V.pic.shadow and string.format('%.4f', V.pic.shadow), string.format('%.4f', 1 - 0.5 * (1 - 2.5 / 9.5)))
V.setPicVal(V.picPlace(), 'picShadow', 100); frames(0.5)
check('  own Lift dark places stronger: it is used', V.pic.shadow and string.format('%.2f', V.pic.shadow), '0.25')
V.setPicVal(V.picPlace(), 'picShadow', 0); V.setPicVal(V.picPlace(), 'picPairKeep', 0); frames(0.5)
check('  0: the curve alone again', V.pic.shadow == nil and V.pic.gamma and string.format('%.4f', V.pic.gamma), string.format('%.4f', gammaFor(100, 100)))
-- lamps, deep dark not lifted too far: below the inside an even gain, the curve undone there
check('cap off: shadow range untouched', V.pic.capMax, nil)
V.setPicVal(V.picPlace(), 'picPairCap', 1); frames(0.5)
check('cap: shadow range just above the inside', V.pic.capMax and string.format('%.6f', V.pic.capMax), string.format('%.6f', 2 ^ (0.5 - 13)))
check('  the gain = the curve\'s lift there', V.pic.capGain and string.format('%.4f', V.pic.capGain), string.format('%.4f', (2 ^ (0.5 - 13)) ^ (-7 / 13)))
local cps = MOCK.cm.CameraCachePrivate.POV.PostProcessSettings
check('  written: range, curve undone, gain', cps.bOverride_ColorCorrectionShadowsMax == true and cps.bOverride_ColorGammaShadows == true
    and cps.bOverride_ColorGainShadows == true and string.format('%.6f/%.4f/%.4f', cps.ColorCorrectionShadowsMax, cps.ColorGammaShadows.W * V.pic.gamma, cps.ColorGainShadows.W),
    string.format('%.6f/%.4f/%.4f', V.pic.capMax, 1, V.pic.capGain))
-- the engine's colour correction (shadow weight 1 - smoothstep(0, max, luma), gamma then gain) on grey:
-- never darker for brighter, nothing lifted much past 7 stops, the deepest near 7
local function engine(x)
    local t = math.min(1, math.max(0, x / V.pic.capMax)); local w = 1 - t * t * (3 - 2 * t)
    return w * (x ^ (1 / (V.pic.gamma * (1 / V.pic.gamma)))) * V.pic.capGain + (1 - w) * x ^ (1 / V.pic.gamma)
end
local prev, most, mono = 0, -99, true
for e = -400, 60 do
    local x = 2 ^ (e / 20); local y = engine(x)
    if y < prev then mono = false end
    prev = y; most = math.max(most, math.log(y / x, 2))
end
check('  never darker for brighter', mono, true)
check('  at most 7 stops (+0.06)', most < 7.06, true)
local deep = math.log(engine(2 ^ -20) / 2 ^ -20, 2)
check('  the deepest lifted near 7', deep > 6.6 and deep <= 7.0001, true)
V.setPicVal(V.picPlace(), 'picPairKeep', 100); frames(0.5)
check('  keep contrast 100: no curve, no cap', V.pic.capMax == nil and V.pic.gamma == nil, true)
V.setPicVal(V.picPlace(), 'picPairKeep', 0); V.setPicVal(V.picPlace(), 'picPairCap', 0); frames(0.5)
-- lamps: their own values set (their blueprint's refresh uses them), the game's put back at 100
local LAMP = 'BlueprintGeneratedClass /Game/Griffin/Lighting/Blueprints/LightFixture/BP_CMN_LightFixture_Base.BP_CMN_LightFixture_Base_C'
MOCK.uobjects[LAMP] = { name = LAMP }
local lampNo = 0
local function lamp(active)
    lampNo = lampNo + 1
    local id = lampNo
    local light = { VolumetricScatteringIntensity = 5 }
    local card = { bHiddenInGame = not active, visible = active }
    function card:SetHiddenInGame(h, c) self.bHiddenInGame = h end
    function card:SetVisibility(v, c) self.visible = v end
    local a = { ['Glow Intensity'] = 2, ['SM Glow Active'] = active, VolumetricScattering = 5, SM_Glow_Billboard = card, refreshed = 0 }
    function a:get_address() return 'lamp'..id end
    function a:K2_GetComponentsByClass(c) return { light } end
    -- (the game's refresh: the light's scattering from the lamp's value, the card hidden when off)
    function a:RefreshFixture()
        self.refreshed = self.refreshed + 1
        light.VolumetricScatteringIntensity = self.VolumetricScattering
        if not self['SM Glow Active'] then card:SetHiddenInGame(true, false); card:SetVisibility(false, false) end
    end
    return a, light, card
end
local la, lla, lca = lamp(true)
local lb, llb, lcb = lamp(false)
MOCK.objectsOf = MOCK.objectsOf or {}
MOCK.objectsOf[LAMP] = { la, lb }
V.setPicVal(V.picPlace(), 'picLampAir', 20); frames(1)
check('lamps: the light in the air x0.2', string.format('%.2f/%.2f', la.VolumetricScattering, lla.VolumetricScatteringIntensity), '1.00/1.00')
check('  the card untouched', la['Glow Intensity'] == 2 and la['SM Glow Active'] == true and lca.bHiddenInGame == false, true)
V.setPicVal(V.picPlace(), 'picLampCard', 50); frames(1)
check('  card half', la['Glow Intensity'], 1)
V.setPicVal(V.picPlace(), 'picLampCard', 0); frames(1)
check('  card 0: off and hidden', la['SM Glow Active'] == false and lca.bHiddenInGame == true and lca.visible == false, true)
check('  a lamp without a card stays without', lb['SM Glow Active'] == false and lcb.bHiddenInGame == true, true)
-- (a lamp coming in later)
local lc, llc = lamp(true)
table.insert(MOCK.objectsOf[LAMP], lc); frames(2.5)
check('  a lamp come later: set too', string.format('%.2f/%s', lc.VolumetricScattering, tostring(lc['SM Glow Active'])), '1.00/false')
V.setPicVal(V.picPlace(), 'picLampCard', 100); V.setPicVal(V.picPlace(), 'picLampAir', 100); frames(1)
check('  100: the game\'s back', string.format('%.2f/%.2f/%s/%s/%s', la.VolumetricScattering, lla.VolumetricScatteringIntensity, tostring(la['Glow Intensity']),
    tostring(la['SM Glow Active']), tostring(lca.bHiddenInGame)), '5.00/5.00/2/true/false')
check('  the card shown again', lca.visible, true)
check('  the one without a card: still without', lb['SM Glow Active'] == false and lcb.bHiddenInGame == true, true)
local before = la.refreshed; frames(3)
check('  then left alone', la.refreshed, before)
MOCK.objectsOf[LAMP] = nil
-- blending two pictures (Fusion): only with a local exposure use, written into the camera
V.setPicVal(V.picPlace(), 'picFusion', 1); frames(0.5)
check('fusion: not without a local exposure use', V.pic.fusion, nil)
V.setPicVal(V.picPlace(), 'picPairKeep', 100); frames(0.5)
check('  with the local lift: on', V.pic.fusion, true)
local fps = MOCK.cm.CameraCachePrivate.POV.PostProcessSettings
check('  written: the method Fusion', fps.bOverride_LocalExposureMethod == true and fps.LocalExposureMethod, 1)
V.setPicVal(V.picPlace(), 'picFusion', 0); V.setPicVal(V.picPlace(), 'picPairKeep', 0); frames(0.5)
check('  off again', V.pic.fusion, nil)
V.setPicVal(V.picPlace(), 'picPairLift', 100); V.setPicVal(V.picPlace(), 'picPair', 0); frames(0.5)
check('  off: nothing', V.pic.minBright == nil and V.pic.gamma == nil and V.pic.shadow == nil, true)
-- bright skies turning white: the game's limit on darkening lifted (ticked for every track)
V.setPicBase('picUncap', 1); frames(0.5)
check('skies: the darkening limit lifted to the engine\'s own', V.pic.maxBright and V.pic.maxBright > 1000, true)
local cps = MOCK.cm.CameraCachePrivate.POV.PostProcessSettings
check('  written into the camera', cps.bOverride_AutoExposureMaxBrightness == true and cps.AutoExposureMaxBrightness > 1000, true)
V.setPicVal(V.picPlace(), 'picUncap', 0); frames(0.5)
check('  a place can turn it off', V.pic.maxBright, nil)
V.setPicVal(V.picPlace(), 'picUncap', 1); frames(0.5)
check('  back on there = every track\'s: not kept apart', V.picOwn('picUncap'), nil)
MOCK.menu('idle')
V.clearPicBase(); frames(0.5)
check('every track cleared: nothing', V.pic.offset == nil and V.pic.temp == nil and V.pic.maxBright == nil, true)

-- 3. no race: the map's name at once
MOCK.world = 'L_Mastiff_Paddock'; frames(2)
check('paddock', V.picPlace(), 'L_Mastiff_Paddock')
note('label: '..V.mapLabel(V.picPlace()))
MOCK.world = 'L_FrontEnd'; frames(2)
check('menus', V.picPlace(), 'L_FrontEnd')
MOCK.world = 'L_Test_LOOP_A'; frames(2)
check('a map the tables don\'t know', V.picPlace(), 'L_Test_LOOP_A')

-- 4. while the race is read: no place (nothing written, the sliders wait)
MOCK.world = 'L_FrontEnd'; frames(2)
MOCK.world, MOCK.trackDef, MOCK.condition = 'L_Mastiff_LOOP_A', false, 'TrackCondition.Sunset'
frames(3)
check('race not read yet', V.picPlace(), nil)
MOCK.ui.texts = {}; MOCK.menu('idle')
local seen = false
for _, l in ipairs(MOCK.ui.texts) do if tostring(l):find('reading the race', 1, true) or tostring(l):find('읽는 중', 1, true) then seen = true end end
check('menu says it is reading the race', seen, true)
MOCK.trackDef = 'TRAK_MAS_LOOP_A_SHORT_02_HARD'; frames(2)
check('then read', V.picPlace(), fe)
check('  its value', V.picVal('picExp'), -1)

-- 5. the weather can't be read: the track alone after a few tries (no weather in the label)
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_SHORT_02_HARD', false, 1.5)
check('weather not read yet', V.picPlace(), nil)
frames(6)
check('track alone', V.picPlace(), 'L_Mastiff_LOOP_A|Fallen Empire|forward|')
note('label: '..V.mapLabel(V.picPlace()))

-- 6. nothing can be read: the whole map after 30 tries
race('L_Mastiff_P2P_A', false, false, 5)
check('reading', V.picPlace(), nil)
frames(30)
check('whole map', V.picPlace(), 'L_Mastiff_P2P_A')
check('  marked', V.picWholeMap(V.picPlace()), true)
MOCK.menu('idle'); MOCK.menu('click'); MOCK.menu('idle')
'''

OLD_VALUES = r'''
-- 7. values an older version saved for whole maps
local m = V.veh.maps
check('loaded', keys(m), 'L_Mastiff_LOOP_A ; L_Mastiff_LOOP_B ; L_Mastiff_Paddock ; L_Spaniel_Loop_A ; L_Spaniel_Loop_A|Salt Circle|forward|Day')
MOCK.menu('idle')
note('older, in the saved list: '..V.mapLabel('L_Mastiff_LOOP_B')..(V.picWholeMap('L_Mastiff_LOOP_B') and '  (whole map)' or ''))
race('L_Mastiff_LOOP_B', 'TRAK_MAS_LOOP_B_FWD', 'TrackCondition.Sunset')
local here = V.picPlace()
check('first race on that map gets them', V.picVal('picCon'), 112)
check('  and', V.picVal('picExp'), -0.3)
check('  the map\'s own entry is gone', V.veh.maps.L_Mastiff_LOOP_B, nil)
race('L_Mastiff_LOOP_B', 'TRAK_MAS_LOOP_B_FWD', 'TrackCondition.BlueHour')
check('the other weather is untouched', V.picOwn('picCon'), nil)
race('L_Mastiff_LOOP_B', 'TRAK_MAS_LOOP_B_FWD', 'TrackCondition.Sunset')
check('back at sunset: still there', V.picVal('picCon'), 112)
-- a whole map whose weather can't be read: kept (and used) until a race there is read
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_FWD', false, 8)
check('weather unread: kept', V.veh.maps.L_Mastiff_LOOP_A ~= nil, true)
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_FWD', 'TrackCondition.Sunset')
check('then read: moved', V.picVal('picExp'), -2)
check('  gone from the map', V.veh.maps.L_Mastiff_LOOP_A, nil)
-- a race that has its own already: the map's wait for the next one without
race('L_Spaniel_Loop_A', 'TRAK_SPA_Loop_A_SHORT_01', 'TrackCondition.Afternoon.Dry')
check('own values stay', V.picVal('picSat'), 140)
check('  the map\'s wait', V.veh.maps.L_Spaniel_Loop_A and V.veh.maps.L_Spaniel_Loop_A.picSat, 80)
race('L_Spaniel_Loop_A', 'TRAK_SPA_Loop_A_SHORT_01', 'TrackCondition.Night.Dry')
check('  the next race there gets them', V.picVal('picSat'), 80)
check('  then gone', V.veh.maps.L_Spaniel_Loop_A, nil)
-- the paddock keeps its own
MOCK.world = 'L_Mastiff_Paddock'; frames(2)
check('paddock keeps its own', V.picVal('picExp'), -0.5)
local f = file()
check('file', keys(f), 'L_Mastiff_LOOP_A|The War Fields|forward|Sunset ; L_Mastiff_LOOP_B|Debris Dunes|forward|Sunset ; '
    ..'L_Mastiff_Paddock ; L_Spaniel_Loop_A|Salt Circle|forward|Day ; L_Spaniel_Loop_A|Salt Circle|forward|Night')
MOCK.menu('idle'); MOCK.menu('click'); MOCK.menu('idle')
note('menu labels drawn: '..#MOCK.ui.labels)
'''

OLD_FILE = {'swgr_vr_vehicles.json': {'format': 4, 'eyes': {}, 'feel': {}, 'detail': {}, 'pilotFollow': {}, 'legacy': {}, 'moved': {},
            'maps': {'L_Mastiff_LOOP_B': {'picCon': 112, 'picExp': -0.3}, 'L_Mastiff_LOOP_A': {'picExp': -2},
                     'L_Mastiff_Paddock': {'picExp': -0.5}, 'L_Spaniel_Loop_A': {'picSat': 80},
                     'L_Spaniel_Loop_A|Salt Circle|forward|Day': {'picSat': 140}}}}


def lua_lit(v):
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return json.dumps(v)
    return '{' + ', '.join('[' + json.dumps(str(k)) + '] = ' + lua_lit(x) for k, x in v.items()) + '}'


def session(script, files, body):
    st = L.luaL_newstate(); L.luaL_openlibs(st)
    try:
        run(st, open(os.path.join(HERE, 'mock.lua'), encoding='utf-8').read(), 'mock')
        run(st, 'MOCK.newMock = true\nMOCK.files = ' + lua_lit(files) + '\nMOCK.setWidthApi("next")\nreturn ""', 'files')
        run(st, open(script, encoding='utf-8').read(), os.path.basename(script))
        r = run(st, COMMON + body + '\nfor _, e in ipairs(MOCK.errors or {}) do fails[#fails + 1] = "CALLBACK ERROR "..e end'
                + '\nreturn table.concat(out, "\\n").."\\n@@"..table.concat(fails, "\\n")', 'cases')
        return r.split('\n@@')
    finally:
        L.lua_close(st)


def main():
    bad = 0
    for script in sys.argv[1:3]:
        print('==', script)
        # (a public build has the picture options still being worked on off: those cases are for the
        # working build; the public one is checked by public_build_test.py)
        public = 'PIC_LAB = false' in open(script, encoding='utf-8').read()
        if public:
            print('-- new player: skipped (a public build; see public_build_test.py)')
        for title, files, body in ((() if public else (('new player', {}, CASES),)) + (('older values', OLD_FILE, OLD_VALUES),)):
            notes, fails = session(script, files, body)
            print('-- ' + title)
            for n in notes.split('\n'):
                print('   ' + n)
            for f in [x for x in fails.split('\n') if x]:
                print('   FAIL ' + f)
                bad += 1
    print('RESULT:', 'FAIL (%d)' % bad if bad else 'OK')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
