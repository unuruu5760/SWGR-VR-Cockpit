"""Vehicle names under every kind of build: every model of every type, parts swapped between models,
recipe names of every kind (or no recipe), parts listed in another order each race, parts loading
late and breaking off. The name a vehicle gets is where its values are saved, so it must be right
from the first moment and never change during a race. Also: values saved under the name older
versions gave (the model most meshes come from) are taken over once, and never deleted.
usage: python tools/luacheck/vehicle_names_test.py <script.lua>
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
local function fail(s) fails[#fails + 1] = s end
local FOLDER = { Bike = 'Bikes', Car = 'Cars', Skimmer = 'Skimmers', Plane = 'Planes' }
local seed = 20261018
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
local function shuffle(t) for i = #t, 2, -1 do local j = rnd(i); t[i], t[j] = t[j], t[i] end return t end
local function mesh(ty, model, slot, i)
    local n = 'SM_'..model..slot..'_Panel'..i
    local path = 'StaticMesh /Game/Griffin/Vehicles/'..FOLDER[ty]..'/Customisation/'..model..'/'..slot..'/'..n..'.'..n
    return { StaticMesh = { get_full_name = function() return path end, Sockets = {} }, SkeletalMesh = false }
end
-- a vehicle in a race: build = { ty, slots = { slot = model }, kits = { slot = kit }, recipeName,
-- noRecipe, n = { slot = meshes }, delay = { slot = s }, breakAt, order }; returns a state table
local raceNo = 0
local function spawn(b)
    raceNo = raceNo + 1
    -- (the seat is on a root every model shares, as on bikes, landspeeders and skimmers)
    local pawn = MOCK.makeVehicle(b.ty, b.ty)
    local id, born = 'pawn_names'..raceNo, MOCK.clockT
    local all = {}
    for slot, model in pairs(b.slots) do
        for i = 1, b.n[slot] do all[#all + 1] = { slot = slot, c = mesh(b.ty, model, slot, i), broken = (i % 2 == 0) } end
    end
    shuffle(all)
    local parts = {}
    for slot, model in pairs(b.slots) do parts[#parts + 1] = { PartType = slot, vehicleKit = b.kits[slot] or model, ParentIndex = 0 } end
    shuffle(parts)
    local recipe = { RecipeName = (b.recipeName or '')..(b.nul and '\0' or ''), UnitRecipes = { { UnitName = 'Main', Parts = parts } } }
    -- (the vehicle's own recipe; or only the race's one, for the player; or none)
    MOCK.custom.ActiveRecipe = (not b.noRecipe and not b.raceOnly and not b.playerOnly) and recipe or false
    -- (the player's recipe on its player state: the right one, or one of another vehicle)
    local stale = nil
    if b.stale then
        local used = {}
        for _, m in pairs(b.slots) do used[m] = true end
        for _, m in ipairs(V.MODELS[b.ty]) do if not used[m] then stale = m; break end end
        local sp = {}
        for slot in pairs(b.slots) do sp[#sp + 1] = { PartType = slot, vehicleKit = stale, ParentIndex = 0 } end
        stale = { RecipeName = stale, UnitRecipes = { { UnitName = 'Main', Parts = sp } } }
    end
    MOCK.playerState.VehicleCustomisationComponent = (b.playerOnly and { VehicleRecipe = recipe }) or (stale and { VehicleRecipe = stale }) or nil
    MOCK.racers = b.raceOnly and { { Player = { get_address = function() return 'someone else' end }, VehicleCustomisation = { RecipeName = 'Raven', UnitRecipes = {} } },
                                   { Player = MOCK.playerState, VehicleCustomisation = recipe } } or {}
    local orig = pawn.K2_GetComponentsByClass
    pawn.get_address = function() return id end
    pawn.K2_GetComponentsByClass = function(self, c)
        local r = orig(self, c)
        if not c.name:find('StaticMeshComponent', 1, true) then return r end
        local t, age = {}, MOCK.clockT - born
        for _, x in ipairs(r) do t[#t + 1] = x end
        for _, x in ipairs(all) do
            if age >= (b.delay[x.slot] or 0) and not (x.broken and b.breakAt and age >= b.breakAt) then t[#t + 1] = x.c end
        end
        return t
    end
    MOCK.pawn = pawn
end
-- the name that build must get
-- (the truth, kept here and not taken from the script: the part the seat is in, seen in the game)
local SEAT = { Car = 'Rear', Skimmer = 'Rear', Bike = 'Controls', Plane = 'Root' }
local function expected(b)
    return b.ty..'/'..b.slots[SEAT[b.ty]]
end
-- drive one race: the first name must be the expected one and stay
local function race(b, tag)
    spawn(b)
    local want, first, changed, frames = expected(b), nil, nil, 0
    for i = 1, 60 do
        MOCK.frame(0.1); frames = frames + 1
        local m = V.model
        if m and not first then first = m end
        if first and m ~= first and not changed then changed = tostring(m)..' at '..string.format('%.1f', i * 0.1)..' s' end
    end
    if first ~= want then fail(tag..': named '..tostring(first)..', want '..want) end
    if changed then fail(tag..': name changed from '..tostring(first)..' to '..changed) end
    MOCK.pawn = nil; MOCK.frame(0.1)
    return first == want and not changed
end
'''

CASES = r'''
local total, okN, perType = 0, 0, {}
-- (recipe names as the game saves them: 'Kingsnake', 'Taipan (Protagonist)', 'MythP1', 'Taipan FE Plus', ...)
local KINDS = { 'name', 'protagonist', 'tier', 'name plus', 'long name', 'empty name', 'no recipe', 'race recipe only', 'player recipe only', 'player recipe of another vehicle', 'name ends in NUL' }
for _, ty in ipairs(V.TYPES) do
    local models, order = V.MODELS[ty], V.SLOT_ORDER[ty]
    perType[ty] = { 0, 0 }
    for _, theme in ipairs(models) do
        for mixLevel = 0, 3 do                 -- 0 = all parts the theme's, 3 = every part may be another model's
            for _, kind in ipairs(KINDS) do
                local b = { ty = ty, slots = {}, kits = {}, n = {}, delay = {}, breakAt = 4 }
                for _, slot in ipairs(order) do
                    local m = theme
                    if mixLevel > 0 and rnd(4) <= mixLevel then m = models[rnd(#models)] end
                    b.slots[slot] = m
                    b.n[slot] = rnd(6)
                    b.delay[slot] = (rnd(6) - 1) * 0.5           -- 0 to 2.5 s
                    if ty == 'Plane' and rnd(3) == 1 then b.kits[slot] = m..'P'..rnd(3) end   -- (tier parts: MythP2)
                end
                if kind == 'name' then b.recipeName = theme
                elseif kind == 'protagonist' then b.recipeName = theme..' (Protagonist)'
                elseif kind == 'tier' then b.recipeName = theme..'P1'
                elseif kind == 'name plus' then b.recipeName = theme..' FE Plus'
                elseif kind == 'long name' then b.recipeName = ty..'_'..theme..'_Ace02_Ace02Colour_AllRust'
                elseif kind == 'empty name' then b.recipeName = ''
                elseif kind == 'race recipe only' then b.recipeName = theme; b.raceOnly = true
                elseif kind == 'player recipe only' then b.recipeName = theme; b.playerOnly = true
                elseif kind == 'player recipe of another vehicle' then b.noRecipe = true; b.stale = true
                elseif kind == 'name ends in NUL' then b.recipeName = theme; b.nul = true
                else b.noRecipe = true end
                for r = 1, 2 do
                    total = total + 1; perType[ty][1] = perType[ty][1] + 1
                    if race(b, string.format('%s %s, mix %d, %s, race %d', ty, theme, mixLevel, kind, r)) then
                        okN = okN + 1; perType[ty][2] = perType[ty][2] + 1
                    end
                end
            end
        end
    end
end
-- the player's own vehicles as the game saved them after parts were swapped (save game, 2026-10-18):
-- each is named after its seat part (landspeeder / skimmer rear, bike controls, podracer pod)
local SAVED = {
    { 'Bike', 'Cottonmouth', { Controls = 'Cottonmouth', EngineC = 'Cottonmouth', EngineB = 'Cottonmouth', Front = 'Kingsnake', Rear = 'Cottonmouth', Wings = 'Cottonmouth' } },
    { 'Skimmer', 'Pelican', { Front = 'Merlin', Rear = 'Pelican', FrontL = 'Pelican', EngineL = 'Pelican', FrontR = 'Pelican', EngineR = 'Pelican' } },
    { 'Car', 'Mako', { FrontR = 'Mako', FrontL = 'Mako', Front = 'Mako', EngineR = 'Mako', EngineL = 'Mako', Rear = 'Mako' } },
    { 'Plane', 'MythP1', { Root = 'Myth', RearR = 'Myth', MidR = 'Myth', CoreR = 'Myth', FrontR = 'Myth', RearL = 'Myth', MidL = 'Myth', CoreL = 'Myth', FrontL = 'Myth' } },
    { 'Bike', 'Taipan (Protagonist)', { Controls = 'Taipan', EngineC = 'Taipan', EngineB = 'Taipan', Front = 'Taipan', Rear = 'Taipan', Wings = 'Taipan' } },
    -- (the same save a few minutes later: three models tied, and four models with the chosen one in the minority)
    { 'Car', 'Mako', { FrontR = 'Wahoo', FrontL = 'Beluga', Front = 'Mako', EngineR = 'Mako', EngineL = 'Beluga', Rear = 'Wahoo' } },
    { 'Skimmer', 'Jackdaw', { Front = 'Jackdaw', Rear = 'Raven', FrontL = 'Merlin', EngineL = 'Pelican', FrontR = 'Raven', EngineR = 'Pelican' } },
}
for _, sv in ipairs(SAVED) do
    local b = { ty = sv[1], recipeName = sv[2], slots = sv[3], kits = {}, n = {}, delay = {}, breakAt = 4 }
    for slot in pairs(b.slots) do b.n[slot] = 3; b.delay[slot] = (rnd(6) - 1) * 0.5 end
    for r = 1, 2 do
        total = total + 1
        if race(b, 'saved "'..sv[2]..'" race '..r) then okN = okN + 1 end
    end
    note(string.format('  saved recipe "%s": named %s', sv[2], tostring(expected(b))))
end
for _, ty in ipairs(V.TYPES) do note(string.format('  %-8s %d models: %d / %d races named right and never renamed', ty, #V.MODELS[ty], perType[ty][2], perType[ty][1])) end
note(string.format('vehicle names: %d / %d races', okN, total))
'''

ADOPT = r'''
-- 2.1.0 saved this mixed bike's values under 'Bike/Lancehead' (most meshes); today it is 'Bike/Taipan'
-- (its controls): the values move there and the older name leaves the file
local b = { ty = 'Bike', recipeName = 'Taipan', n = {}, delay = {}, kits = {},
    slots = { Front = 'Lancehead', Rear = 'Lancehead', Wings = 'Lancehead', Controls = 'Taipan', EngineC = 'Taipan', EngineB = 'Lancehead' } }
for slot in pairs(b.slots) do b.n[slot] = 3 end
spawn(b); for i = 1, 50 do MOCK.frame(0.1) end
local key, old = V.model, 'Bike/Lancehead'
local e = V.veh.eyes[key]
note(string.format('older name moved: %s eye %s, trembling share %s, engine %s; older entry left in the file: %s',
    tostring(key), e and table.concat(e, ' / ') or '-', tostring(V.valFor(key, 'shakeAlong')), tostring(V.veh.feel[key] and V.veh.feel[key].engine),
    tostring(V.veh.detail[old] ~= nil or V.veh.eyes[old] ~= nil or V.veh.feel[old] ~= nil)))
note('  kept aside for a real Lancehead: '..tostring(V.veh.moved[old] ~= nil))
if not (V.veh.moved[old] and V.veh.moved[old].detail and V.veh.moved[old].detail.shakeAlong == 33) then fail('tidy: what the older name had was not kept aside') end
if key ~= 'Bike/Taipan' then fail('tidy: named '..tostring(key)) end
if not (e and e[3] == 77) then fail('tidy: eye not moved') end
if V.valFor(key, 'shakeAlong') ~= 33 then fail('tidy: trembling share not moved') end
if not (V.veh.feel[key] and V.veh.feel[key].engine == 130) then fail('tidy: shake amount not moved') end
if V.veh.detail[old] or V.veh.eyes[old] or V.veh.feel[old] then fail('tidy: the older entry is still in the file') end
-- the user then sets this vehicle back to its defaults: the older values must not come back
V.clearOwnVal('detail', key); V.clearOwnVal('feel', key); V.veh.eyes[key] = nil; V.saveVeh()
MOCK.pawn = nil; MOCK.frame(0.1)
spawn(b); for i = 1, 50 do MOCK.frame(0.1) end
note('after "back to default" and a new race: trembling share '..tostring(V.valFor(key, 'shakeAlong'))..', eye saved '..tostring(V.veh.eyes[key] ~= nil))
if V.veh.detail[key] or V.veh.eyes[key] then fail('tidy: the older values came back after the user cleared them') end
-- a real Lancehead bike (its controls Lancehead) turns up later: what it had comes back from the backup
local bl = { ty = 'Bike', recipeName = 'Lancehead', n = {}, delay = {}, kits = {}, slots = {} }
for _, slot in ipairs(V.SLOT_ORDER.Bike) do bl.slots[slot] = 'Lancehead'; bl.n[slot] = 2 end
MOCK.pawn = nil; MOCK.frame(0.1); spawn(bl); for i = 1, 50 do MOCK.frame(0.1) end
note('a real Lancehead later: '..tostring(V.model)..', trembling share '..tostring(V.valFor(V.model, 'shakeAlong'))..' (came back), still kept aside: '..tostring(V.veh.moved['Bike/Lancehead'] ~= nil))
if V.model ~= 'Bike/Lancehead' or V.valFor(V.model, 'shakeAlong') ~= 33 then fail('tidy: a vehicle of a moved name did not get its values back') end
if V.veh.moved['Bike/Lancehead'] then fail('tidy: values taken back are still kept aside') end
-- a skimmer whose parts tie (older versions called it Raven or Pelican from race to race) and whose
-- values were saved under the tie's other model: today it is Raven (its rear), and gets them
local b3 = { ty = 'Skimmer', recipeName = 'Jackdaw', n = {}, delay = {}, kits = {},
    slots = { Front = 'Jackdaw', Rear = 'Raven', FrontL = 'Merlin', EngineL = 'Pelican', FrontR = 'Raven', EngineR = 'Pelican' } }
for slot in pairs(b3.slots) do b3.n[slot] = 3 end
MOCK.pawn = nil; MOCK.frame(0.1); spawn(b3); for i = 1, 50 do MOCK.frame(0.1) end
note('tied parts, values under the other model: '..tostring(V.model)..', cut distance '..tostring(V.valFor(V.model, 'near'))..' (Pelican left: '..tostring(V.veh.detail['Skimmer/Pelican'] ~= nil)..')')
if V.model ~= 'Skimmer/Raven' or V.valFor(V.model, 'near') ~= 17 or V.veh.detail['Skimmer/Pelican'] then fail('tidy: tied parts not put right') end
-- a vehicle that is not mixed: nothing moves
local before = 0
for _ in pairs(V.veh.detail) do before = before + 1 end
local b2 = { ty = 'Car', recipeName = 'Goblin', n = {}, delay = {}, kits = {}, slots = {} }
for _, slot in ipairs(V.SLOT_ORDER.Car) do b2.slots[slot] = 'Goblin'; b2.n[slot] = 2 end
MOCK.pawn = nil; MOCK.frame(0.1); spawn(b2); for i = 1, 50 do MOCK.frame(0.1) end
local after = 0
for _ in pairs(V.veh.detail) do after = after + 1 end
note('a vehicle that is not mixed: '..tostring(V.model)..', rollAmount '..tostring(V.valFor(V.model, 'rollAmount'))..', entries before / after: '..before..' / '..after)
if after ~= before or V.valFor(V.model, 'rollAmount') ~= 0.8 then fail('tidy: a vehicle that is not mixed changed') end
-- the settings file: written in today's shape (format 2, no older keys), its older one kept
local st = MOCK.files['swgr_vr_settings.json'] or {}
note('settings: format '..tostring(st.format)..', older key left: '..tostring(st.shakeAlongPerVehicle ~= nil or st.shakeSaved ~= nil)
    ..', backup: '..tostring(MOCK.files['swgr_vr_settings_backup_format1.json'] ~= nil))
if st.format ~= 2 or st.shakeAlongPerVehicle ~= nil or st.shakeSaved ~= nil then fail('tidy: the settings file still has older keys') end
if not MOCK.files['swgr_vr_settings_backup_format1.json'] then fail('tidy: no backup of the older settings file') end
'''

CONFLICT = r'''
-- an older version had two skimmers under two names: a plain 'Saker' and a mixed one (rear Saker,
-- most parts Rook) it called 'Rook'. Today both are 'Saker' (their rear): the plain one's values stay,
-- no question is asked, and 'Rook' leaves the file; a real Rook later gets its values from the backup.
local plain = { ty = 'Skimmer', recipeName = 'Saker', n = {}, delay = {}, kits = {}, slots = {} }
local mixed = { ty = 'Skimmer', recipeName = 'Saker', n = {}, delay = {}, kits = {}, slots = {} }
local rook = { ty = 'Skimmer', recipeName = 'Rook', n = {}, delay = {}, kits = {}, slots = {} }
for _, slot in ipairs(V.SLOT_ORDER.Skimmer) do
    plain.slots[slot] = 'Saker'; plain.n[slot] = 2
    mixed.slots[slot] = (slot == 'Rear') and 'Saker' or 'Rook'; mixed.n[slot] = 2
    rook.slots[slot] = 'Rook'; rook.n[slot] = 2
end
local function drive(b) MOCK.pawn = nil; MOCK.frame(0.1); spawn(b); local first = nil
    for i = 1, 50 do MOCK.frame(0.1); first = first or V.model end
    return first end
local f2 = drive(mixed)
note('mixed Saker first: '..tostring(f2)..', cut distance '..tostring(V.valFor(V.model, 'near'))..', Rook left in the file: '..tostring(V.veh.detail['Skimmer/Rook'] ~= nil))
if f2 ~= 'Skimmer/Saker' or V.valFor(V.model, 'near') ~= 5 or V.veh.detail['Skimmer/Rook'] then fail('conflict: the mixed one did not keep the Saker values / Rook not removed') end
local f1 = drive(plain)
note('plain Saker: '..tostring(f1)..', cut distance '..tostring(V.valFor(V.model, 'near')))
if f1 ~= 'Skimmer/Saker' or V.valFor(V.model, 'near') ~= 5 then fail('conflict: the plain one changed') end
local f3 = drive(rook)
note('a real Rook later: '..tostring(f3)..', cut distance '..tostring(V.valFor(V.model, 'near'))..' (came back); nothing left aside: '..tostring(next(V.veh.moved) == nil)
    ..', older names left: '..tostring(next(V.veh.legacy) == nil and 'none' or 'some'))
if f3 ~= 'Skimmer/Rook' or V.valFor(V.model, 'near') ~= 25 then fail('conflict: the Rook values did not come back') end
if next(V.veh.moved) ~= nil or next(V.veh.legacy) ~= nil then fail('conflict: all put right, yet something is left in the file') end
'''

CONFLICT_DATA = {
    'swgr_vr_settings.json': {},
    'swgr_vr_vehicles.json': {'format': 3, 'eyes': {}, 'feel': {}, 'pilotFollow': {}, 'maps': {},
        'detail': {'Skimmer/Saker': {'near': 5}, 'Skimmer/Rook': {'near': 25}}},
}

OLD_DATA = {
    'swgr_vr_settings.json': {'shakeAlongOn': True},
    'swgr_vr_vehicles.json': {'format': 3,
        'eyes': {'Bike/Lancehead': [1, -9, 77], 'Car/Goblin': [0, -5, 70]},
        'feel': {'Bike/Lancehead': {'engine': 130}},
        'detail': {'Bike/Lancehead': {'shakeAlong': 33, 'shakeAlongMove': 21}, 'Car/Goblin': {'rollAmount': 0.8},
                   'Skimmer/Pelican': {'near': 17}},
        'pilotFollow': {}, 'maps': {}},
}


def lua_lit(v):
    if isinstance(v, bool): return 'true' if v else 'false'
    if v is None: return 'nil'
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return json.dumps(v)
    if isinstance(v, list): return '{' + ', '.join(lua_lit(x) for x in v) + '}'
    return '{' + ', '.join('[' + json.dumps(str(k)) + '] = ' + lua_lit(x) for k, x in v.items()) + '}'


def session(script, files, body):
    st = L.luaL_newstate(); L.luaL_openlibs(st)
    run(st, open(os.path.join(HERE, 'mock.lua'), encoding='utf-8').read(), 'mock')
    run(st, 'MOCK.files = ' + lua_lit(files) + '\nMOCK.setWidthApi("next")\nreturn ""', 'files')
    run(st, open(script, encoding='utf-8').read(), os.path.basename(script))
    res = run(st, COMMON + body + r'''
for _, e in ipairs(MOCK.errors) do fail('CALLBACK ERROR '..e) end
note('FAILS '..#fails)
for i = 1, math.min(#fails, 30) do note('  '..fails[i]) end
return table.concat(out, '\n')''', 'cases')
    L.lua_close(st)
    return res


def main():
    script = sys.argv[1]
    a = session(script, {}, CASES)
    print(a)
    b = session(script, OLD_DATA, ADOPT)
    print(b)
    c = session(script, CONFLICT_DATA, CONFLICT)
    print(c)
    bad = 'FAILS 0' not in a or 'FAILS 0' not in b or 'FAILS 0' not in c
    print('RESULT:', 'FAIL' if bad else 'OK')
    sys.exit(1 if bad else 0)


main()
