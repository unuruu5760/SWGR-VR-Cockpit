-- Shared core: language, settings, vehicle data, small math helpers.
-- Everything the sections share lives in the table V (also global SWGR_VR, for debugging).
V.LANG = LANG
V.VERSION = VERSION
V.t = 0                                    -- seconds since load (real time, from the engine tick)
local function logger(prefix)
    return function(s) uevr.params.functions.log_info('[SWGR VR] ['..prefix..'] '..tostring(s)) end
end
V.logger = logger
local log = logger('core')

-------------------------------------------------------------------------------- language
-- The code is written in English. The Korean build adds V.KO (lang_ko.lua: English text -> Korean)
-- and tr(text) looks the text up there; anything missing stays English.
V.KO = V.KO or {}
function V.tr(en)
    if V.LANG == 'ko' then return V.KO[en] or en end
    return en
end
-- Tooltips are wrapped into short lines (ImGui doesn't wrap them: one long line runs off the
-- screen). Width counts Hangul (3 UTF-8 bytes) as 2, other characters as 1.
local TIP_WIDTH = 60
local function textWidth(s)
    local cont = select(2, s:gsub('[\128-\191]', ''))
    return #s - cont / 2
end
local function wrap(text)
    local out = {}
    for para in (text..'\n'):gmatch('(.-)\n') do
        local line = ''
        for word in para:gmatch('%S+') do
            if line ~= '' and textWidth(line) + 1 + textWidth(word) > TIP_WIDTH then
                out[#out + 1] = line; line = word
            else
                line = (line == '') and word or (line..' '..word)
            end
        end
        out[#out + 1] = line
    end
    return table.concat(out, '\n')
end
V.wrap = wrap
local tipCache = {}
-- description shown while the pointer is over the last item
function V.tip(en)
    local ok, hov = pcall(imgui.is_item_hovered)
    if not (ok and hov) then return end
    local text = V.tr(en)
    local w = tipCache[text]
    if not w then w = wrap(text); tipCache[text] = w end
    pcall(imgui.set_tooltip, w)
end
-- ImGui's default font has no Hangul: the Korean build loads Nanum Gothic (SIL OFL, shipped in the
-- Korean profile) from <profile>\fonts
-- (UEVR's load_font only reads that folder). Without it the menu still works, Hangul shows as '?'.
V.font = nil
if V.LANG == 'ko' then
    local ranges = { 0x0020, 0x00FF, 0x2000, 0x206F, 0x2190, 0x21FF, 0x2500, 0x257F, 0x3131, 0x3163, 0xAC00, 0xD7A3, 0 }
    local ok, font = pcall(function() return imgui.load_font('NanumGothic-Regular.ttf', 18, ranges) end)
    V.font = ok and font or nil
    -- (UEVR hands out a font even when the file is missing; then the menu shows '?')
    log('Korean font NanumGothic-Regular.ttf requested from the profile fonts folder: '..(V.font and 'ok' or 'failed'))
end
function V.withFont(fn)
    local pushed = false
    if V.font then pushed = pcall(imgui.push_font, V.font) end
    local ok, err = pcall(fn)
    if pushed then pcall(imgui.pop_font) end
    if not ok then log('menu error: '..tostring(err)) end
end

-------------------------------------------------------------------------------- settings
-- All user settings in one file. Percent values: 100 = the recommended amount.
V.SETTINGS_FILE = 'swgr_vr_settings.json'
V.DEFAULTS = {
    extras = true,                 -- all add-on effects (off = like the original cockpit script)
    cameraMode = 'cockpit',        -- 'cockpit' / 'game'
    cameraLock = 'hills',          -- 'track' / 'hills' / 'smooth' / 'light' / 'pilot'
    pilot = 'head',                -- 'head' / 'hidden' / 'visible'
    showCinematics = true,         -- race intro flyover with the game camera
    showCrashCamera = true,        -- the game's crash camera when crashing
    showTakedownCamera = true,     -- the game's takedown camera when you take a rival down
    showFinishCamera = true,       -- the game's finish camera when you cross the line
    showLookBack = true,           -- look back: the game's own (End: the cockpit steps aside) and from the cockpit seat (hotkey)
    roll = 100,                    -- % banking (shared; a vehicle's own % is in the vehicles file)
    -- "Exactly like the vehicle" keeps a banking of its own (the game's lean); the other modes another one
    bankMode = 'other',            -- which of the two the shared banking values are now
    bankPilotRoll = 200, bankPilotMax = 90, bankPilotAmount = 0.55,
    bankOtherRoll = 100, bankOtherMax = 50.92, bankOtherAmount = 0.65,
    feelOn = true,                 -- cockpit shake / boost punch
    engine = 100, road = 100, motion = 100, boost = 100, landing = 100,   -- %
    -- % on top of the shake, per vehicle type: the amounts saved for a vehicle / all others
    shakeDefault_Bike = 100, shakeSaved_Bike = 100, rideDefault_Bike = 100, rideSaved_Bike = 100,
    shakeDefault_Car = 100, shakeSaved_Car = 100, rideDefault_Car = 100, rideSaved_Car = 100,
    shakeDefault_Skimmer = 100, shakeSaved_Skimmer = 100, rideDefault_Skimmer = 100, rideSaved_Skimmer = 100,
    shakeDefault_Plane = 100, shakeSaved_Plane = 100, rideDefault_Plane = 100, rideSaved_Plane = 100,
    shakeAlongOn = false,          -- the vehicle body shakes too and carries you along (test)
    hitstop = true, warp = true,
    screen = 100,                  -- % boost screen colours (0 = off)
    intro = true,                  -- engine start shot, then into the cockpit
    carShake = 100,                -- % engine idle on the car body in game cameras
    bodyFollow = true,             -- eye follows the rider standing up on jumps
    nearClip = true,               -- don't draw what is right at the eye
    headHit = true,                -- landings hit your head (the view angle snaps)
    viewOffsets = true,            -- saved VR camera positions for menu screens
    keyToggle = 'F3', keyCycle = 'F4', keyRecenter = 'None',
    padToggle = 'None', padCycle = 'None', padRecenter = 'None',
    keyExtras = 'F5', padExtras = 'None',
    keyLookBack = 'None', padLookBack = 'Right stick up',   -- look back from the cockpit seat while held
    detail = {},                   -- fine tuning: key -> value (only what the user changed)
    picBase = {},                  -- picture values for every track and weather (65_picture; a place's own replace them)
    format = 2,                    -- 2 = 2.1.1: settings of older versions put right, their old keys gone
}
-- Settings older versions saved and this one no longer keeps: read once from an older file (V.old) to
-- carry them over (40_feel), never saved again.
V.OLD_DEFAULTS = {
    shakeSaved = 100, shakeDefault = 100,   -- one overall shake pair for all types (now per type)
    shakeMasterByType = false, shakeAlongPerVehicle = false, landSlamV2 = false,   -- 'done once' marks
    shakeAlong = 100, shakeAlongAir = 50, shakeAlongSmooth = 0, shakeAlongSmooth2 = 0, shakeAlongMove = 100,
    shakeAlongLand = 500,                  -- ride shake amounts for every vehicle (now per vehicle)
    blockCamButton = true,                 -- (now always on)
}
V.old = {}
function V.resetSettings()
    for k, v in pairs(V.DEFAULTS) do V.cfg[k] = (type(v) == 'table') and {} or v end
end
V.cfg = {}
V.resetSettings()
V.cfgFormat = 2                            -- format of the loaded settings (no file: nothing to put right)
do
    local ok, t = pcall(json.load_file, V.SETTINGS_FILE)
    if ok and type(t) == 'table' then
        V.cfgFormat = tonumber(t.format) or 1
        -- an older file: kept as it is, once, before anything is put right
        if V.cfgFormat < 2 then
            local bk = V.SETTINGS_FILE:gsub('%.json$', '_backup_format'..V.cfgFormat..'.json')
            local okB, had = pcall(json.load_file, bk)
            if not (okB and type(had) == 'table') then pcall(json.dump_file, bk, t) end
        end
        for k, v in pairs(t) do
            if V.OLD_DEFAULTS[k] ~= nil and type(v) == type(V.OLD_DEFAULTS[k]) then V.old[k] = v end
            if V.DEFAULTS[k] ~= nil and type(v) == type(V.DEFAULTS[k]) then
                if k == 'detail' or k == 'picBase' then
                    for dk, dv in pairs(v) do if type(dv) == 'number' then V.cfg[k][dk] = dv end end
                else
                    V.cfg[k] = v
                end
            end
        end
    end
    V.cfg.format = 2
end

-------------------------------------------------------------------------------- fine tuning
-- Every value a section uses is registered here with its recommended value and range; the
-- "Fine tuning" menu lists them. V.val(key) = the user's value or the recommended one.
V.TUNABLES, V.TUNE_INDEX = {}, {}
function V.tunable(sec, key, base, lo, hi, en, tipEn)
    local item = { sec = sec, key = key, base = base, lo = lo, hi = hi, en = en, tipEn = tipEn }
    V.TUNABLES[#V.TUNABLES + 1] = item
    V.TUNE_INDEX[key] = item
    return item
end
-- the shared value (what every vehicle uses unless it has its own)
function V.sharedVal(key)
    local d = V.cfg.detail[key]
    if type(d) == 'number' then return d end
    local item = V.TUNE_INDEX[key]
    return item and item.base or 0
end
-- vehicle m's own value if the user changed it for that vehicle, else the shared one
function V.valFor(m, key) return V.ownVal('detail', m, key) or V.builtinVal('detail', m, key) or V.sharedVal(key) end
-- for the vehicle driven now
function V.val(key) return V.valFor(V.model, key) end
local saveAt = nil
-- saving is delayed a little so dragging a slider writes the file once
function V.save() saveAt = V.t + 0.5 end
function V.saveNow()
    saveAt = nil
    local ok, err = pcall(json.dump_file, V.SETTINGS_FILE, V.cfg)
    if not ok then log('saving settings failed: '..tostring(err)) end
end

-------------------------------------------------------------------------------- per-vehicle data
-- eyes[model] = { x, y, z } (seat frame cm), feel[model] = { key = % } (banking and shake amounts),
-- detail[model] = { key = value } (body follow and fine tuning). feel and detail only hold what the
-- user changed for that vehicle (while driving it, or in its "Saved vehicles" entry); everything
-- else follows the shared value.
-- Built-in defaults (the author's tuning, baked in 2026-10-14). A vehicle uses them unless the
-- user changed the value for it. Lookup: the user's own value -> the vehicle's built-in value ->
-- its type's built-in value -> the shared value -> the recommended value.
-- Eye positions are per vehicle (seats differ); everything else is per vehicle type, tuned on one
-- vehicle of each type (Bike: Taipan, Car: Beluga, Skimmer: Saker / Merlin, Plane: Myth).
V.VEH_DEFAULTS = {
    eyes = {
        ['Bike/Boomslang'] = { 0, 0, 64.95 },
        ['Bike/Sidewinder'] = { 0, 10.05, 57.2 },
        ['Bike/Taipan'] = { 0, -7.45, 70.45 },
        ['Car/Beluga'] = { 0, -5.45, 76 },
        ['Car/Hammerhead'] = { 0, -11.2, 80.5 },
        ['Car/Orca'] = { 0, -8.95, 81.45 },
        ['Plane/Myth'] = { 0, -5.45, 74.2 },
        ['Plane/Northropi'] = { 0, -11.2, 60.1 },
        ['Skimmer/Merlin'] = { 0, 1.3, 70.45 },
        ['Skimmer/Rook'] = { 0, -11.2, 77.7 },
        ['Skimmer/Saker'] = { 0, -11.2, 67.4 },
    },
    feel = {},                             -- (per vehicle, when one ever needs its own)
    detail = {},
}
V.TYPE_DEFAULTS = {
    Bike = {
        feel = { road = 75 },
        detail = { followUp = 0.85, followFwd = 1.21, airLift = 7.17, landFloor = 5.22, landHit = 3.39, landHitHz = 4.23, landLean = 0.14, near = 12.55, nearLow = 8.82 },
    },
    Car = {
        feel = {},
        detail = { followUp = 0.74, followFwd = 0, hitstopAB = 0.33, hitstopStrength = 0.53, hitstopTime = 0.16, landFloor = 5.11, landHit = 3.05, landing = 0.45, ramjet = 2.66, warpAmount = 5 },
    },
    Skimmer = {
        feel = { road = 73 },
        detail = { followUp = 0.74, followFwd = 0, near = 3 },
    },
    Plane = {
        feel = {},
        detail = { followUp = 0.74, followFwd = 0, bumps = 1.779, cruise = 2.527, ramjet = 3 },
    },
}
-- Body follow on jumps per character (builds differ): [type][character] = { followUp, followFwd }.
-- The type's own values above were tuned with the default character (Tomato02).
V.PILOT_DEFAULTS = {
    Bike = {
        Spinach = { followUp = 1.66, followFwd = 2.17 },
    },
}
-- vehicle type of a model key 'Type/Model' (cached)
local typeOfModel = {}
function V.typeOf(m)
    if not m then return nil end
    local ty = typeOfModel[m]
    if ty == nil then ty = m:match('^(%a+)/') or false; typeOfModel[m] = ty end
    return ty or nil
end
-- the built-in default of vehicle m: its own, else its type's (nil = none)
function V.builtinVal(kind, m, key)
    if not m then return nil end
    local t = V.VEH_DEFAULTS[kind][m]
    local v = type(t) == 'table' and tonumber(t[key]) or nil
    if v then return v end
    local ty = V.typeOf(m)
    t = ty and V.TYPE_DEFAULTS[ty] and V.TYPE_DEFAULTS[ty][kind]
    return type(t) == 'table' and tonumber(t[key]) or nil
end
-- the built-in body follow of character c in vehicle m's type (nil = none)
function V.pilotBuiltin(m, c, key)
    local ty = c and V.typeOf(m)
    local t = ty and V.PILOT_DEFAULTS[ty] and V.PILOT_DEFAULTS[ty][c]
    return type(t) == 'table' and tonumber(t[key]) or nil
end
V.VEHICLES_FILE = 'swgr_vr_vehicles.json'
-- maps: picture per map. legacy: the vehicle names that had values when the file came from a version
-- before 2.1.1 (named the older way), until each is put right (20_vehicle); moved: what older names
-- had when they were put right, until a vehicle of that name turns up and takes it back.
-- format 4 = 2.1.1 (vehicles named after their seat part).
V.veh = { eyes = {}, feel = {}, detail = {}, pilotFollow = {}, maps = {}, legacy = {}, moved = {}, format = 4 }
V.vehFormat = 4                            -- format of the loaded file (older ones are converted)
do
    local ok, t = pcall(json.load_file, V.VEHICLES_FILE)
    if ok and type(t) == 'table' then
        for _, k in ipairs({ 'eyes', 'feel', 'detail', 'pilotFollow', 'maps', 'legacy', 'moved' }) do
            if type(t[k]) == 'table' then V.veh[k] = t[k] end
        end
        for m, v in pairs(V.veh.moved) do if type(v) ~= 'table' then V.veh.moved[m] = nil end end   -- (a test build's marks)
        V.vehFormat = tonumber(t.format) or 1
        if V.vehFormat < 2 then
            -- older files: body follow was kept apart ({ up, forward }; moved into detail by the
            -- vehicle section) and "own settings" copied every shake amount: keep only what differs
            V.migrating, V.oldFollow = true, type(t.follow) == 'table' and t.follow or nil
            for _, f in pairs(V.veh.feel) do
                if type(f) == 'table' then
                    for g, v in pairs(f) do if tonumber(v) == (tonumber(V.cfg[g]) or 100) then f[g] = nil end end
                end
            end
        end
        -- a value equal to the vehicle's built-in default is not the user's own
        local function same(a, b, eps) return tonumber(a) and tonumber(b) and math.abs(a - b) < eps end
        for _, k in ipairs({ 'feel', 'detail' }) do
            for m, tbl in pairs(V.veh[k]) do
                if type(tbl) == 'table' then
                    for key, v in pairs(tbl) do
                        if same(v, V.builtinVal(k, m, key), 0.001) then tbl[key] = nil; V.vehPruned = true end
                    end
                end
            end
        end
        for m, e in pairs(V.veh.eyes) do
            local b = V.VEH_DEFAULTS.eyes[m]
            if type(e) == 'table' and type(b) == 'table' and same(e[1], b[1], 0.01) and same(e[2], b[2], 0.01) and same(e[3], b[3], 0.01) then
                V.veh.eyes[m] = nil; V.vehPruned = true
            end
        end
        for _, k in ipairs({ 'feel', 'detail' }) do
            for m, tbl in pairs(V.veh[k]) do if type(tbl) ~= 'table' or next(tbl) == nil then V.veh[k][m] = nil end end
        end
        -- a file from before 2.1.1: remember which names have values (they were named the older way)
        if V.vehFormat < 4 then
            for _, k in ipairs({ 'eyes', 'feel', 'detail', 'pilotFollow' }) do
                for m in pairs(V.veh[k]) do V.veh.legacy[m] = true end
            end
        end
    end
end
V.veh.format = 4
local vehSaveAt = nil
function V.saveVeh() vehSaveAt = V.t + 0.5 end
function V.saveVehNow()
    vehSaveAt = nil
    local ok, err = pcall(json.dump_file, V.VEHICLES_FILE, V.veh)
    if not ok then log('saving vehicle data failed: '..tostring(err)) end
end
if V.vehFormat < 4 or V.vehPruned then V.saveVeh() end
-- one per-vehicle value (kind 'feel' or 'detail'); nil = not changed for that vehicle
function V.ownVal(kind, m, key)
    local t = m and V.veh[kind][m]
    return type(t) == 'table' and tonumber(t[key]) or nil
end
function V.setOwnVal(kind, m, key, v)
    if not m then return end
    local t = V.veh[kind][m]
    if type(t) ~= 'table' then t = {}; V.veh[kind][m] = t end
    t[key] = v
    V.saveVeh()
end
-- key = nil: all of that kind for the vehicle
function V.clearOwnVal(kind, m, key)
    local t = m and V.veh[kind][m]
    if type(t) ~= 'table' then return end
    if key ~= nil then t[key] = nil end
    if key == nil or next(t) == nil then V.veh[kind][m] = nil end
    V.saveVeh()
end
function V.hasOwn(m) return m ~= nil and (V.veh.feel[m] ~= nil or V.veh.detail[m] ~= nil or V.veh.pilotFollow[m] ~= nil) end
-- Body follow on jumps depends on the pilot's build, so it is also saved per vehicle AND character:
-- pilotFollow[model][character] = { followUp = x, followFwd = y }. A character without its own
-- values uses the vehicle's (its own / built-in / shared).
function V.followOwn(m, c, key)
    local t = m and c and V.veh.pilotFollow[m]
    t = type(t) == 'table' and t[c] or nil
    return type(t) == 'table' and tonumber(t[key]) or nil
end
-- lookup: this vehicle + character (user) -> the character's built-in -> the vehicle's value
function V.followVal(m, c, key) return V.followOwn(m, c, key) or V.pilotBuiltin(m, c, key) or V.valFor(m, key) end
function V.setFollowVal(m, c, key, v)
    if not (m and c) then return end
    local t = V.veh.pilotFollow[m]
    if type(t) ~= 'table' then t = {}; V.veh.pilotFollow[m] = t end
    local u = t[c]
    if type(u) ~= 'table' then u = {}; t[c] = u end
    u[key] = v
    V.saveVeh()
end
-- key nil: both values of the character; c nil: every character of the vehicle
function V.clearFollowVal(m, c, key)
    local t = m and V.veh.pilotFollow[m]
    if type(t) ~= 'table' then return end
    if c == nil then
        V.veh.pilotFollow[m] = nil
    else
        local u = t[c]
        if type(u) == 'table' then
            if key ~= nil then u[key] = nil end
            if key == nil or next(u) == nil then t[c] = nil end
        end
        if next(t) == nil then V.veh.pilotFollow[m] = nil end
    end
    V.saveVeh()
end
-- a % amount (banking 'roll' or a shake group) for vehicle m: its own, else the shared one
function V.sharedPct(g) return tonumber(V.cfg[g]) or 100 end
function V.pctFor(m, g) return V.ownVal('feel', m, g) or V.builtinVal('feel', m, g) or V.sharedPct(g) end
-- called every tick by the footer
function V.flushSaves()
    if saveAt and V.t >= saveAt then V.saveNow() end
    if vehSaveAt and V.t >= vehSaveAt then V.saveVehNow() end
end

-------------------------------------------------------------------------------- math
function V.clamp01(x) x = tonumber(x) or 0; return x < 0 and 0 or (x > 1 and 1 or x) end
function V.clamp(x, m) return x < -m and -m or (x > m and m or x) end
function V.rotate(q, x, y, z)
    local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
    local tx, ty, tz = 2 * (qy * z - qz * y), 2 * (qz * x - qx * z), 2 * (qx * y - qy * x)
    return x + qw * tx + (qy * tz - qz * ty),
           y + qw * ty + (qz * tx - qx * tz),
           z + qw * tz + (qx * ty - qy * tx)
end
function V.unrotate(q, x, y, z) return V.rotate({ -q[1], -q[2], -q[3], q[4] }, x, y, z) end
-- smooth 1D value noise in [-1, 1], two octaves: irregular, not a clean sine
local function hash(i) local s = math.sin(i * 127.1 + 311.7) * 43758.5453; return (s - math.floor(s)) * 2 - 1 end
local function vnoise(x)
    local i = math.floor(x); local f = x - i
    local u = f * f * (3 - 2 * f)
    return hash(i) * (1 - u) + hash(i + 1) * u
end
function V.noise(x, seed) return 0.7 * vnoise(x + seed * 31.7) + 0.3 * vnoise(x * 2.3 + seed * 17.3) end
function V.approach(cur, target, dt, up, down)
    local tau = target > cur and up or down
    return cur + (target - cur) * (1 - math.exp(-dt / tau))
end

-------------------------------------------------------------------------------- hooks
-- After the cockpit has placed the view (position / rotation of this eye), these run in this order.
V.HOOK_ORDER = { 'roll', 'feel', 'intro' }
V.hooks = {}
function V.runHooks(view, position, rotation)
    for _, n in ipairs(V.HOOK_ORDER) do
        local h = V.hooks[n]
        if h then
            local ok, err = pcall(h, view, position, rotation)
            if not ok and V.t > (V.hookErrT or 0) then V.hookErrT = V.t + 5; log('hook '..n..' error: '..tostring(err)) end
        end
    end
end

-- small per-tick list for sections (each runs protected; one failing doesn't stop the others)
V.ticks = {}
function V.onTick(name, fn) V.ticks[#V.ticks + 1] = { name = name, fn = fn } end
V.resets = {}
function V.onReset(fn) V.resets[#V.resets + 1] = fn end
