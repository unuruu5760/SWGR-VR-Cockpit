-- Picture per map (2026-10-17): some maps look blown out in VR - the bright parts far too bright, as if
-- HDR were forced onto a plain monitor - while the flat game looks right, and the game's brightness
-- option then makes every other place dull. Seen inside tunnels and structures: at some spots the
-- outside is far too bright, fine again once out = the game's eye adaptation brightening for the dark
-- inside (in the cockpit more of the view is dark than in the flat chase camera). Its speed made no
-- difference (tried); leaving more of the dark out when it measures helped. So, for the map you are
-- on and saved for it only (V.veh.maps, next to the vehicles): how much of the dark is ignored, the
-- least light it still brightens for (dark places are not lifted beyond that, bright ones stay), and
-- the whole picture (exposure, bright parts, bloom, saturation, contrast). Written into the game
-- camera's post-process each frame together with the boost effects (60_screen: V.pic); a map without
-- values = nothing is written. The map and its weather (SkyCreator) are logged.
local log = V.logger('picture')
V.pic = { active = false }
-- the values and what each one is when untouched (= the game's picture)
V.PIC_NEUTRAL = { picLow = 0, picMinEV = 0, picExp = 0, picHi = 100, picBloom = 100, picSat = 100, picCon = 100 }

-- how the engine counts the adaptation limits: EV100 (extended range, UE5's usual) or plain luminance
local function cvarInt(name)
    local ok, v = pcall(function() return api:get_console_manager():find_variable(name):get_int() end)
    return ok and tonumber(v) or nil
end
local extendedRange = cvarInt('r.DefaultFeature.AutoExposure.ExtendDefaultLuminanceRange')
log(string.format('exposure: extended luminance range %s, method %s, eye adaptation quality %s',
    tostring(extendedRange), tostring(cvarInt('r.DefaultFeature.AutoExposure.Method')), tostring(cvarInt('r.EyeAdaptationQuality'))))
local function fromEV(ev)
    if extendedRange == 0 then return 0.012 * 2 ^ ev end       -- (luminance = 1.2 * 2^EV100 / 100)
    return ev
end

local sky = { world = nil, obj = nil, tries = 0, nextLook = 0, info = {}, logged = nil }
local function alive(o)
    if not o then return false end
    local ok, yes = pcall(function() return UEVR_UObjectHook.exists(o) end)
    return ok and yes == true
end
local function worldName()
    local ok, n = pcall(function() return api:get_engine().GameViewport.World:get_fname():to_string() end)
    return ok and n or nil
end
-- the map you are on (its level name), nil while unknown
function V.picMapName() return sky.world end
-- 'L_Mastiff_LOOP_A' -> 'Mastiff Loop A'; the menus' level -> "menus"
function V.mapLabel(m)
    if not m then return V.tr('not found') end
    if m:find('FrontEnd', 1, true) then return V.tr('menus') end
    local n = m:gsub('^L_', ''):gsub('_', ' ')
    n = n:gsub('(%a)(%w*)', function(a, b) return a..b:lower() end)
    return n
end
-- a value of map m (the map you are on if nil): its own, else the neutral one
function V.picVal(key, m)
    local t = V.veh.maps[m or sky.world or '']
    local v = type(t) == 'table' and tonumber(t[key]) or nil
    return v or V.PIC_NEUTRAL[key]
end
function V.picOwn(key, m)
    local t = V.veh.maps[m or sky.world or '']
    return type(t) == 'table' and tonumber(t[key]) or nil
end
function V.setPicVal(m, key, v)
    if not m then return end
    local t = V.veh.maps[m]
    if type(t) ~= 'table' then t = {}; V.veh.maps[m] = t end
    if math.abs(v - V.PIC_NEUTRAL[key]) < 0.0005 then t[key] = nil else t[key] = v end
    if next(t) == nil then V.veh.maps[m] = nil end
    V.saveVeh()
end
function V.clearPicMap(m)
    if m and V.veh.maps[m] then V.veh.maps[m] = nil; V.saveVeh() end
end

-- (all objects are walked: only when the map changes, a few tries; the first try says what it found)
local function findSky(first)
    local ok, obj = pcall(function()
        local c = api:find_uobject('Class /Script/SkyCreatorPlugin.SkyCreator')
        if not c then
            if first then log('weather: no SkyCreator class') end
            return nil
        end
        local list = c:get_objects_matching(false) or {}
        local best, n = nil, 0
        for _, o in ipairs(list) do
            n = n + 1
            if pcall(function() return o.TimeOfDay end) then best = o end
        end
        if first then log(string.format('weather: %d SkyCreator objects, %s', n, best and best:get_full_name() or 'none readable')) end
        return best
    end)
    if not ok and first then log('weather: search failed: '..tostring(obj)) end
    return ok and obj or nil
end
local function num(f) local ok, v = pcall(f); return ok and tonumber(v) or nil end
local function readSky(o)
    local i = {}
    i.tod = num(function() return o.TimeOfDay end)
    i.sun = num(function() return o.SunCurrentElevation end)
    i.wExp = num(function() return o.WeatherSettings.PostProcessSettings.ExposureCompensation end)
    i.wBloom = num(function() return o.WeatherSettings.PostProcessSettings.BloomIntensity end)
    i.wBloomTh = num(function() return o.WeatherSettings.PostProcessSettings.BloomThreshold end)
    pcall(function()
        local s = o.PostProcess.Settings
        if s.bOverride_AutoExposureBias then i.ppExp = tonumber(s.AutoExposureBias) end
        if s.bOverride_BloomIntensity then i.ppBloom = tonumber(s.BloomIntensity) end
        if s.bOverride_AutoExposureMinBrightness then i.ppMin = tonumber(s.AutoExposureMinBrightness) end
        if s.bOverride_AutoExposureMaxBrightness then i.ppMax = tonumber(s.AutoExposureMaxBrightness) end
    end)
    return i
end
local function f2(x) return x and string.format('%.2f', x) or '-' end
local function lookAround()
    local w = worldName()
    if w ~= sky.world then sky.world, sky.obj, sky.tries, sky.info = w, nil, 0, {} end
    if not alive(sky.obj) then
        sky.obj = nil
        if sky.tries < 3 and w then sky.tries = sky.tries + 1; sky.obj = findSky(sky.tries == 1) end
    end
    local i = sky.obj and readSky(sky.obj) or {}
    sky.info = i
    -- (logged when the map or its weather changes; the time of day moves slowly, so it is left out)
    local key = tostring(w)..f2(i.wExp)..f2(i.wBloom)..f2(i.ppExp)..f2(i.ppBloom)
    if key ~= sky.logged then
        sky.logged = key
        log(string.format('map %s - time of day %s h, sun %s deg up, weather exposure %s, weather bloom %s (threshold %s), sky post-process exposure %s, bloom %s, min / max brightness %s / %s',
            tostring(w), i.tod and string.format('%.1f', i.tod) or '-', i.sun and string.format('%.0f', i.sun) or '-',
            f2(i.wExp), f2(i.wBloom), f2(i.wBloomTh), f2(i.ppExp), f2(i.ppBloom), f2(i.ppMin), f2(i.ppMax)))
    end
end

V.onTick('picture', function(dt)
    if V.t >= sky.nextLook then
        sky.nextLook = V.t + (sky.obj and 2 or 4)
        pcall(lookAround)
    end
    local exp = V.picVal('picExp')
    local hi = V.picVal('picHi') / 100
    local bloom = V.picVal('picBloom') / 100
    local sat = V.picVal('picSat') / 100
    local con = V.picVal('picCon') / 100
    local low = V.picVal('picLow')
    local minEV = V.picVal('picMinEV')
    local p = V.pic
    p.active = V.cfg.extras and (math.abs(exp) > 0.001 or math.abs(hi - 1) > 0.001 or math.abs(bloom - 1) > 0.001
        or math.abs(sat - 1) > 0.001 or math.abs(con - 1) > 0.001 or low > 0.5 or minEV > 0.05) or false
    -- eye adaptation (0 = the game's own): how much of the darkest part of the picture it leaves out when
    -- it measures (Unreal's default 10 of 100); the least light it still brightens for (EV100)
    p.low = low > 0.5 and low or nil
    p.minBright = minEV > 0.05 and fromEV(minEV) or nil
    local i = sky.info or {}
    -- exposure: on top of what the sky's post-process (or else its weather) sets here, else the default 0
    p.exp = math.abs(exp) > 0.001 and ((i.ppExp or i.wExp or 0) + exp) or nil
    -- bloom: a share of the bloom here (the engine default 0.675 if none is known)
    p.bloom = math.abs(bloom - 1) > 0.001 and ((i.ppBloom or i.wBloom or 0.675) * bloom) or nil
    p.hi, p.sat, p.con = hi, sat, con
end)
