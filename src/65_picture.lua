-- Picture per map (2026-10-17): some maps look blown out in VR - the bright parts far too bright, as if
-- HDR were forced onto a plain monitor - while the flat game looks right, and the game's brightness
-- option then makes every other place dull. Seen inside tunnels and structures: at some spots the
-- outside is far too bright, fine again once out = the game's eye adaptation brightening for the dark
-- inside (in the cockpit more of the view is dark than in the flat chase camera). Its speed made no
-- difference (tried); leaving more of the dark out when it measures helped. So, for the map you are
-- on and saved for it only (V.veh.maps, next to the vehicles): how much of the dark is ignored, the
-- least light it still brightens for (dark places are not lifted beyond that, bright ones stay), and
-- the whole picture (exposure, bright parts, bloom, saturation, contrast); since 2026-10-18 also the
-- glaring and the dark places on their own (Unreal's local exposure). Written into the game
-- camera's post-process each frame together with the boost effects (60_screen: V.pic); a place without
-- values = nothing is written. The map and its weather (SkyCreator) are logged.
-- Per track and weather (2026-10-18): one map is raced as several tracks (routes, reverse) and each race
-- gets one of its weathers (RaceEventVM.trackConditions, a GameplayTag 'TrackCondition.Sunset') with
-- its own light: values for a map glaring in the midday sun made it far too dark at night. So the values
-- are saved for the track (as the game names it; reverse apart) in the light its weather gives (66_tracks:
-- the tag's name doesn't always say it, Jakku's 'BlueHour' is lit as dawn): the place
-- 'L_Mastiff_LOOP_A|Fallen Empire|forward|Sunset'. Every other track and weather keeps the game's
-- picture. Places without a race (menus, paddock), and a race that can't be read, keep the map's name.
local log = V.logger('picture')
V.pic = { active = false }
-- the values and what each one is when untouched (= the game's picture)
V.PIC_NEUTRAL = { picLow = 0, picMinEV = 0, picExp = 0, picHi = 100, picBloom = 100, picSat = 100, picCon = 100,
    picGlare = 0, picShadow = 0, picTunnel = 0, picBlack = 0, picVib = 0, picTemp = 0, picUncap = 0,
    picPair = 0, picPairLift = 100, picPairKeep = 0, picPairCap = 0, picFusion = 0, picLampCard = 100, picLampAir = 100 }
-- The VR picture for everywhere (2026-10-18): seen through the headset (Quest 3: LCD, its blacks grey,
-- the lenses scattering bright light) every game looks paler and brighter than on the monitor, so the
-- user wanted a look for all tracks, ReShade-like (its plain saturation turned the sand neon): the
-- picture values can be set for every track and weather at once (V.cfg.picBase, in the settings); a
-- place's own value replaces that one there. New with it: deeper blacks (the black point lowered, like
-- ReShade's Levels), vibrance (the washed-out bright parts' colour brought back more than the rest) and
-- colour temperature.
-- the value for every place: the user's, else the neutral one
function V.picBase(key)
    local v = tonumber(V.cfg.picBase and V.cfg.picBase[key])
    if v then return v end
    return V.PIC_NEUTRAL[key]
end
function V.picBaseOwn(key) return tonumber(V.cfg.picBase and V.cfg.picBase[key]) end
function V.setPicBase(key, v)
    V.cfg.picBase = V.cfg.picBase or {}
    if math.abs(v - V.PIC_NEUTRAL[key]) < 0.0005 then V.cfg.picBase[key] = nil else V.cfg.picBase[key] = v end
    V.save()
end
function V.clearPicBase() V.cfg.picBase = {}; V.save() end

-- how the engine counts the adaptation limits: EV100 (extended range, UE5's usual) or plain luminance
local function cvarInt(name)
    local ok, v = pcall(function() return api:get_console_manager():find_variable(name):get_int() end)
    return ok and tonumber(v) or nil
end
local extendedRange = cvarInt('r.DefaultFeature.AutoExposure.ExtendDefaultLuminanceRange')
-- local exposure (tone down glaring / lift dark places) needs the renderer's switch on; at the engine's
-- default contrast it changes nothing, so it is switched on (once) only when one of those two is used
local localExposure = cvarInt('r.LocalExposure')
local function needLocalExposure()
    if localExposure ~= 0 then return end
    localExposure = 1
    local ok, err = pcall(function() api:execute_command('r.LocalExposure 1') end)
    log('local exposure was off in the renderer: switched on ('..(ok and 'ok' or tostring(err))..')')
end
log(string.format('exposure: extended luminance range %s, method %s, eye adaptation quality %s, local exposure %s',
    tostring(extendedRange), tostring(cvarInt('r.DefaultFeature.AutoExposure.Method')), tostring(cvarInt('r.EyeAdaptationQuality')),
    tostring(localExposure)))
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
-- the map (level) in 66_tracks (its name's case can differ from the level's)
local function mapInfo(m)
    if not m or not V.MAP_TRACKS then return nil end
    local t = V.MAP_TRACKS[m]
    if t then return t end
    local lm = m:lower()
    for k, v in pairs(V.MAP_TRACKS) do if k:lower() == lm then return v end end
    return nil
end
-- the race on this map: its track (TrackDef asset name), the game's name for it, reverse, the weather's
-- tag and its light; read a second apart until known (RACE_TRIES: then the map's name alone is used)
local race = { world = nil, tries = 0, id = nil, course = nil, rev = false, tag = nil, light = nil }
local RACE_TRIES = 30
local function placeKey(w, course, rev, light)
    return table.concat({ w, course, rev and 'reverse' or 'forward', light or '' }, '|')
end
-- a place -> map, track, reverse, light (a map's name alone: just the map)
local function splitPlace(k)
    local w, course, dir, light = k:match('^([^|]*)|([^|]*)|([^|]*)|([^|]*)$')
    if not w then return k end
    return w, course, dir == 'reverse', light ~= '' and light or nil
end
-- where the picture values are now: the track and weather raced (nil while still reading them), else
-- the map you are on; nil while unknown
function V.picPlace()
    local w = sky.world
    if not w then return nil end
    if race.world == w and race.id then return placeKey(w, race.course, race.rev, race.light) end
    if mapInfo(w) and not (race.world == w and race.tries >= RACE_TRIES) then return nil end
    return w
end
-- a place saved for a whole map although races there are told apart (an older version's)
function V.picWholeMap(k)
    return k ~= nil and not k:find('|', 1, true) and mapInfo(k) ~= nil
end
-- the names the game shows for a map (66_tracks): the tracks raced on it and its planet
function V.mapCourses(m)
    local mt = mapInfo(m)
    if not mt or not mt[1] then return nil end
    local names = {}
    for i, n in ipairs(mt) do names[i] = V.tr(n) end
    return table.concat(names, ' · ')
end
local function planetOf(m)
    local mt = mapInfo(m)
    if mt and mt.planet then return mt.planet end
    local code = m:match('^L_(%a+)_')                  -- (a map of a planet without races: its paddock)
    for k, n in pairs(V.PLANET_NAMES or {}) do if code and k:lower() == ('PLA_'..code):lower() then return n end end
    return nil
end
-- a weather as the player sees it: the light (66_tracks), with rain or snow when that weather on that
-- map has it; a memory race's own light says so (the game's name for those races)
local LIGHT_NAMES = { Day = 'Day', Night = 'Night', Sunset = 'Sunset', Dawn = 'Dawn', BlueHour = 'Twilight', Overcast = 'Overcast' }
function V.weatherLabel(m, light)
    local base = light:gsub('_MEM$', '')
    local n = LIGHT_NAMES[base] and V.tr(LIGHT_NAMES[base]) or base
    local mt = mapInfo(m)
    local rain, snow = false, false
    for tag, l in pairs(mt and mt.light or {}) do
        if l == light and tag:find('Wet', 1, true) then rain = true end
        if l == light and tag:find('Snow', 1, true) then snow = true end
    end
    if snow then n = n..', '..V.tr('snow') elseif rain then n = n..', '..V.tr('rain') end
    if light:find('_MEM$') then n = n..' ('..V.tr('Podracing Memory')..')' end
    return n
end
-- a place as the menu shows it: the track (reverse), its planet and the weather, as the game names
-- them; a map alone: the tracks raced on it, else its planet (the paddock), else a name made from the level's
function V.mapLabel(k)
    if not k then return V.tr('not found') end
    local m, course, rev, light = splitPlace(k)
    if m:find('FrontEnd', 1, true) then return V.tr('menus') end
    local pl = planetOf(m)
    local where = pl and (' ('..V.tr(pl)..')') or ''
    if course then
        local n = V.tr(course)..(rev and (' '..V.tr('Reverse')) or '')..where
        return light and (n..' / '..V.weatherLabel(m, light)) or n
    end
    local courses = V.mapCourses(m)
    if courses then return courses..where end
    -- (the place between races on a planet, the paddock: the game shows no name for it, so its planet's)
    if pl and m:lower():find('paddock', 1, true) then return V.tr(pl) end
    local n = m:gsub('^L_', ''):gsub('_', ' ')
    n = n:gsub('(%a)(%w*)', function(a, b) return a..b:lower() end)
    return n..where
end
-- a value of place m (where you are now if nil): its own, else the one for every place
-- Picture options still being worked on (2026-10-18): only in the working build (PIC_LAB, set by the
-- build). A public build has 2.1.0's picture controls, per track and weather; it leaves these at the
-- game's own (a value saved for one is kept in the file, just not used) and does not read the game's areas.
V.PIC_LAB = PIC_LAB
V.PIC_LAB_KEYS = { picGlare = true, picShadow = true, picTunnel = true, picBlack = true, picVib = true, picTemp = true,
    picUncap = true, picPair = true, picPairLift = true, picPairKeep = true, picPairCap = true, picFusion = true,
    picLampCard = true, picLampAir = true }
local function labOff(key) return not V.PIC_LAB and V.PIC_LAB_KEYS[key] end
function V.picVal(key, m)
    if labOff(key) then return V.PIC_NEUTRAL[key] end
    local t = V.veh.maps[m or V.picPlace() or '']
    local v = type(t) == 'table' and tonumber(t[key]) or nil
    return v or V.picBase(key)
end
function V.picOwn(key, m)
    if labOff(key) then return nil end
    local t = V.veh.maps[m or V.picPlace() or '']
    return type(t) == 'table' and tonumber(t[key]) or nil
end
-- (a place's value equal to the one for every place is not kept: it follows that one then)
function V.setPicVal(m, key, v)
    if not m then return end
    local t = V.veh.maps[m]
    if type(t) ~= 'table' then t = {}; V.veh.maps[m] = t end
    if math.abs(v - V.picBase(key)) < 0.0005 then t[key] = nil else t[key] = v end
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
-- The race: its track and weather, from the race's view model on the game state
-- (RacingGameState.RaceEventViewModel: track = TrackDef, trackConditions = GameplayTag; the race's
-- recipe has them too, but in an array of structs, which UEVR's Lua does not hand over). The game's
-- texts can't be read here: the track's name comes from 66_tracks by the asset's name.
-- a game name (FName / FText) as a Lua string
local function text(t)
    if t == nil or type(t) == 'string' then return t end
    local ok, s = pcall(function() return t:to_string() end)
    if ok and type(s) == 'string' then return s end
    return tostring(t)
end
local function readRace()
    local gs = api:get_engine().GameViewport.World.GameState
    local vm = gs and gs.RaceEventViewModel
    local td = vm and vm.track
    if not td then return nil end
    local tag = nil
    pcall(function() tag = text(vm.trackConditions.TagName) end)
    if type(tag) ~= 'string' or not tag:find('^TrackCondition%.') then tag = nil end
    return td:get_fname():to_string(), tag
end
-- what the game state has about the race, for the log when the race couldn't be read (it tells where
-- it can be read)
function V.describeTrackData()
    local out = {}
    local function add(k, f)
        local ok, v = pcall(f)
        out[#out + 1] = k..' '..(ok and tostring(v) or 'error')
    end
    local function cls(o) return o and o:get_class():get_fname():to_string() or 'none' end
    local gs = nil
    pcall(function() gs = api:get_engine().GameViewport.World.GameState end)
    add('game state', function() return cls(gs) end)
    add('view model', function() return cls(gs.RaceEventViewModel) end)
    add('its track', function() local t = gs.RaceEventViewModel.track; return t and (cls(t)..' '..t:get_fname():to_string()) or 'none' end)
    add('its planet', function() local t = gs.RaceEventViewModel.Planet; return t and t:get_fname():to_string() or 'none' end)
    add('its weather', function() local c = gs.RaceEventViewModel.trackConditions; return type(c)..' '..tostring(c and text(c.TagName)) end)
    add('route', function() local r = gs.RaceRoute; return r and (cls(r)..' '..r:get_fname():to_string()) or 'none' end)
    return table.concat(out, '; ')
end
-- values an older version saved for the whole map (2.1.0) go to the first race there that is read,
-- track and weather (likely where they were set); every other track and weather keeps the game's
-- picture. (A race that has its own already: they wait for the next one there without.)
local function moveMapValues(w, place)
    local t = V.veh.maps[w]
    if type(t) ~= 'table' or V.veh.maps[place] ~= nil then return end
    V.veh.maps[place] = t; V.veh.maps[w] = nil
    V.saveVeh()
    log('picture values saved for the whole map '..w..' (older version) are now for this race only: '..place)
end
local function lookForRace(w)
    if w ~= race.world then
        race.world, race.tries, race.id, race.course, race.rev, race.tag, race.light = w, 0, nil, nil, false, nil, nil
        V.trackName = nil
    end
    if race.id or not w or not mapInfo(w) or race.tries >= RACE_TRIES then return end
    race.tries = race.tries + 1
    local ok, id, tag = pcall(readRace)
    -- (the weather may come a moment after the track: a few tries for it, then the track alone)
    if ok and id and (tag or race.tries >= 5) then
        local short = tag and tag:gsub('^TrackCondition%.', '')
        local mt = mapInfo(w)
        race.id, race.tag = id, tag
        race.course = V.TRACK_NAMES and V.TRACK_NAMES[id] or id
        race.rev = V.TRACK_REVERSE and V.TRACK_REVERSE[id] or false
        race.light = short and (mt and mt.light and mt.light[short] or short) or nil
        V.trackName = race.course
        log(string.format('race: %s%s (%s) on map %s, weather %s, light %s', race.course, race.rev and ' reverse' or '', id, w,
            tostring(tag), tostring(race.light))..(tag and '' or ('; game data: '..V.describeTrackData())))
        if race.light then moveMapValues(w, V.picPlace()) end
    elseif race.tries == RACE_TRIES then
        log('race on map '..w..': not found ('..tostring(ok and 'no track' or id)..'), values for the whole map; game data: '..V.describeTrackData())
    end
end
local lookForAreas
local function lookAround()
    local w = worldName()
    if w ~= sky.world then sky.world, sky.obj, sky.tries, sky.info = w, nil, 0, {} end
    lookForRace(w)
    if w and lookForAreas and V.PIC_LAB then lookForAreas(w) end
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

-- Tunnels (2026-10-18): the user wanted, inside a tunnel, the glaring outside toned down while the inside
-- stays as it is, and out in the open the game's own picture. Toning down glaring places everywhere did
-- the first but made a sunny day look overcast outside; measuring the light by the bright part made the
-- tunnel turn dark or bright with every turn of the head. So "Tunnels" is the same toning down, only
-- while the vehicle is in one of the game's own tunnels; in for 0.3 s turns it on (a bridge passed under at
-- speed does not), over 0.6 s; it goes over 1 s once out. (Lines cast around the vehicle were tried first:
-- under a wreck open on one side they flicked on and off - the user wants the game's own data.)
local roof = { next = 0, hit = false, since = nil, amount = 0, flips = 0, world = nil }
local ROOF_HOLD, ROOF_IN, ROOF_OUT = 0.3, 0.6, 1.0
-- The game's own areas: the game marks its places for the sound (its SweejAmbience plugin): boxes in the
-- map (SweejAmbienceVolume; Jakku: stretched and turned 2 m cubes, other planets: shaped by hand, in the
-- map or in the parts streamed in while racing), each with an area asset (SAD_Mastiff_Tracks_Interior_Small
-- ...) of the type Exterior or Interior (its value: 'AATE_Gfn_Ambience_AreaTypeEnum::NewEnumerator1' =
-- Interior). The game's own marks were right in the game (2026-10-18): the wreck open at its side, with
-- the low sun, is Exterior_Large; a wide tunnel inside a wreck is Interior_Large (so the name Large does
-- not mean open: an earlier version left those out and turned the wide tunnel off). So a tunnel = inside an
-- Interior box not named Exterior / Overhang / Open by the game (Lantaana's Exterior_Overhang is typed
-- Interior); how wide it is across the vehicle is felt for (AREA_STEP steps, up to AREA_WIDE) for the menu
-- only. Inside = the engine's own check
-- (Volume.EncompassesPoint; it did not work in the game), else the box as a turned cube from its scale -
-- or, for a box shaped by hand (scale 1, other planets: the engine's bounds much bigger than that cube),
-- its bounds in the world. The boxes come from the engine's list of
-- the world's actors of that class (GameplayStatics.GetAllActorsOfClass; UEVR's own object list, which
-- stayed empty in the game, only if that gives none). A map whose boxes can't be read: no Tunnels there.
local areas = { world = nil, byAddr = {}, list = {}, nextRead = 0, reads = 0, encompass = nil }   -- (lookForAreas: declared above lookAround)
local AREA_WIDE, AREA_STEP = 30000, 1000          -- (cm)
local AREA_INTERIOR = 'NewEnumerator1'
local AREA_SKIP = { 'Exterior', 'Overhang', 'Open' }
-- the box's own axes in the world from its rotator (Unreal's rotation matrix rows)
local function boxAxes(r)
    local p, y, l = math.rad(tonumber(r.Pitch) or 0), math.rad(tonumber(r.Yaw) or 0), math.rad(tonumber(r.Roll) or 0)
    local sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(l), math.cos(l)
    return { cp * cy, cp * sy, sp }, { sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp },
        { -(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp }
end
local function areaVec()
    areas.vecS = areas.vecS or api:find_uobject('ScriptStruct /Script/CoreUObject.Vector')
    return StructObject.new(areas.vecS)
end
-- a box, read once: its name and kind, where it is (its world bounds, to pass it by quickly when far),
-- and its turned cube from the scale (used when the engine's check does not work)
local function readArea(vol)
    local comp = vol.AmbienceComponent
    local def = comp and comp.AmbienceDefinition
    local at = (comp and comp.bUseComponentAreaType) and comp.AreaType or (def and def.AreaType)
    local name = def and def:get_fname():to_string() or '?'
    local kind = tostring(text(at and at.Name) or ''):match('([^:]+)$')        -- ('...AreaTypeEnum::NewEnumerator1')
    local indoor, skipped = kind == AREA_INTERIOR, false
    for _, w in ipairs(AREA_SKIP) do if indoor and name:find(w, 1, true) then indoor, skipped = false, true end end
    local root = vol.RootComponent
    local l, r, s = root.RelativeLocation, root.RelativeRotation, root.RelativeScale3D
    local a = { vol = vol, name = name, interior = indoor, skipped = skipped, c = { l.X, l.Y, l.Z }, axes = { boxAxes(r) },
        half = { 100 * math.abs(s.X), 100 * math.abs(s.Y), 100 * math.abs(s.Z) } }
    -- (when boxes overlap: a tunnel one first, then an indoor one left out, then an outdoor one; the
    -- smaller first among the same)
    a.rank = indoor and 3 or skipped and 2 or 1
    local o, e = areaVec(), areaVec()
    local ok = pcall(function() vol:GetActorBounds(false, o, e, false) end)
    if ok and tonumber(e.X) and e.X > 0 then
        a.lo = { o.X - e.X - 100, o.Y - e.Y - 100, o.Z - e.Z - 100 }
        a.hi = { o.X + e.X + 100, o.Y + e.Y + 100, o.Z + e.Z + 100 }
        a.size = e.X * e.Y * e.Z
        -- (the turned cube's own bounds; the engine's much bigger = a box shaped by hand: its bounds are its shape)
        local ext = { e.X, e.Y, e.Z }
        for i = 1, 3 do
            local cube = 0
            for j = 1, 3 do cube = cube + math.abs(a.axes[j][i]) * a.half[j] end
            if ext[i] > cube * 1.5 + 100 then a.shaped = true end
        end
        a.dims = string.format('%.0f x %.0f x %.0f m', 2 * e.X / 100, 2 * e.Y / 100, 2 * e.Z / 100)
    else
        a.size = a.half[1] * a.half[2] * a.half[3]
        a.dims = string.format('%.0f x %.0f x %.0f m (cube)', 2 * a.half[1] / 100, 2 * a.half[2] / 100, 2 * a.half[3] / 100)
    end
    return a
end
-- is a point in box a: the engine's own check (any shape), else the turned cube, or the bounds of a box
-- shaped by hand
local function inArea(a, x, y, z)
    if a.lo and (x < a.lo[1] or y < a.lo[2] or z < a.lo[3] or x > a.hi[1] or y > a.hi[2] or z > a.hi[3]) then return false end
    if a.shaped and not areas.encompass then return true end
    if areas.encompass then
        local p = areas.pt or areaVec(); areas.pt = p
        p.X, p.Y, p.Z = x, y, z
        local ok, yes = pcall(function() return a.vol:EncompassesPoint(p, 0, {}) end)
        return ok and yes == true
    end
    local dx, dy, dz = x - a.c[1], y - a.c[2], z - a.c[3]
    for i = 1, 3 do
        local ax = a.axes[i]
        if math.abs(dx * ax[1] + dy * ax[2] + dz * ax[3]) > a.half[i] then return false end
    end
    return true
end
local function areaCount()
    local n = 0
    for _, a in ipairs(areas.list) do if a.interior then n = n + 1 end end
    return n
end
-- the boxes in the world now: the engine's list of its actors of that class, else UEVR's object list
local function areaActors(c)
    local out, err = {}, nil
    local ok, e = pcall(function()
        areas.gs = areas.gs or api:find_uobject('Class /Script/Engine.GameplayStatics'):get_class_default_object()
        areas.gs:GetAllActorsOfClass(api:get_engine().GameViewport.World, c, out)
    end)
    if not ok then err = tostring(e) end
    local list = {}
    for _, v in ipairs(out) do list[#list + 1] = v end
    if #list > 0 then return list, 'the engine\'s list' end
    local ok2, objs = pcall(function() return c:get_objects_matching(false) end)
    if ok2 and type(objs) == 'table' and #objs > 0 then return objs, 'UEVR\'s object list' end
    return {}, 'none in either list'..(err and (' - the engine\'s: '..err) or '')
end
-- the boxes of the map raced on, read again every 2 s while racing (parts of the map stream in): new ones
-- read once, gone ones dropped. The first time on a map: does the engine's check work (a box holds its
-- own middle)?
function lookForAreas(w)
    if areas.world ~= w then areas.world, areas.byAddr, areas.list, areas.nextRead, areas.reads, areas.encompass, areas.said = w, {}, {}, 0, 0, nil, false end
    if not race.id or V.t < areas.nextRead then return end
    areas.nextRead = V.t + 2
    local c = api:find_uobject('Class /Script/SweejAmbience.SweejAmbienceVolume')
    if not c then
        if not areas.said then areas.said = true; log('game areas on '..w..': their class is not there - no Tunnels here') end
        return
    end
    local vols, from = areaActors(c)
    local mine, seen, added, others, failed, firstErr, firstOther = '/'..w:lower(), {}, 0, 0, 0, nil, nil
    for _, vol in ipairs(vols) do
        local ok, err = pcall(function()
            local addr = vol:get_address()
            seen[addr] = true
            if areas.byAddr[addr] ~= nil then return end
            local full = vol:get_full_name()
            if not full:lower():find(mine, 1, true) then                 -- (another map's, not gone yet)
                areas.byAddr[addr] = false
                others = others + 1
                firstOther = firstOther or full
                return
            end
            areas.byAddr[addr] = readArea(vol)                             -- (a read that fails: tried again next time)
            added = added + 1
        end)
        if not ok then failed = failed + 1; firstErr = firstErr or tostring(err) end
    end
    local list = {}
    for addr, a in pairs(areas.byAddr) do
        if not seen[addr] then areas.byAddr[addr] = nil elseif a then list[#list + 1] = a end
    end
    areas.list = list
    -- (the first reads on a map, any new boxes, any failing: what was found)
    if areas.reads < 3 or ((added > 0 or failed > 0) and areas.reads < 60) then
        log(string.format('game areas on %s, read %d: %d boxes (%s), %d new, %d of other maps%s, %d failed to read%s; %d boxes here, %d of them tunnels',
            w, areas.reads + 1, #vols, from, added, others, firstOther and (' (e.g. '..firstOther..')') or '', failed,
            firstErr and (' ('..firstErr..')') or '', #list, areaCount()))
    end
    areas.reads = areas.reads + 1
    if areas.encompass == nil and #list > 0 then
        local works = 0
        for _, a in ipairs(list) do
            local p = areaVec()
            p.X, p.Y, p.Z = a.lo and (a.lo[1] + a.hi[1]) / 2 or a.c[1], a.lo and (a.lo[2] + a.hi[2]) / 2 or a.c[2], a.lo and (a.lo[3] + a.hi[3]) / 2 or a.c[3]
            local ok, yes = pcall(function() return a.vol:EncompassesPoint(p, 0, {}) end)
            if ok and yes == true then works = works + 1 end
        end
        areas.encompass = works > 0
        log(string.format('game areas on %s: the engine\'s inside check works on %d of %d boxes%s', w, works, #list,
            works > 0 and '' or ' - the boxes are taken as turned cubes'))
    end
end
-- the vehicle: where it is and its right on the ground
local function vehicleFrame()
    local p = api:get_local_pawn(0)
    local tf = p and p.VehicleState and p.VehicleState.VehicleTransform
    local t, q = tf and tf.Translation, tf and tf.Rotation
    if not t or not q then return nil end
    local qx, qy, qz, qw = q.X, q.Y, q.Z, q.W
    local fx, fy = 1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy + qw * qz)
    local len = math.sqrt(fx * fx + fy * fy)
    if len < 1e-3 then fx, fy, len = 1, 0, 1 end
    return t.X, t.Y, t.Z, -fy / len, fx / len
end
-- how wide box a is across the vehicle here (cm): felt for to each side in steps until out of it, or
-- until it is known to be wider than AREA_WIDE
local function areaWidth(a, x, y, z, rx, ry)
    local left, right, inL, inR, d = 0, 0, true, true, AREA_STEP
    while (inL or inR) and left + right <= AREA_WIDE do
        if inL then if inArea(a, x - rx * d, y - ry * d, z) then left = d else inL = false end end
        if inR then if inArea(a, x + rx * d, y + ry * d, z) then right = d else inR = false end end
        d = d + AREA_STEP
    end
    return left + right + AREA_STEP
end
-- the box the vehicle is in (see rank), with how wide it is here
local function areaHere()
    local x, y, z, rx, ry = vehicleFrame()
    if not x then return nil end
    local best = nil
    for _, a in ipairs(areas.list) do
        if (not best or a.rank > best.rank or (a.rank == best.rank and a.size < best.size)) and inArea(a, x, y, z) then best = a end
    end
    if not best then return nil end
    local width = nil
    if best.interior then width = areaWidth(best, x, y, z, rx, ry) end
    return { name = best.name, interior = best.interior, skipped = best.skipped, narrow = width, dims = best.dims }
end
local function roofAmount(dt, wanted)
    if roof.world ~= sky.world then roof.world, roof.flips, roof.area, roof.areaName = sky.world, 0, nil, nil end
    if not wanted then
        roof.hit, roof.since, roof.amount = false, nil, 0
        return 0
    end
    if V.t >= roof.next then
        roof.next = V.t + 0.1
        local hit = false
        roof.readable = #areas.list > 0
        if roof.readable then
            local a = areaHere()
            roof.area = a
            hit = a ~= nil and a.interior
            local key = a and (a.name..(hit and '+' or '-')) or 'none'
            if key ~= roof.areaName then
                roof.areaName = key
                roof.flips = roof.flips + 1
                if roof.flips <= 40 then
                    log(string.format('tunnel check: game area %s%s -> %s (map %s)', a and a.name or 'none',
                        a and ((a.interior and string.format(' (indoor, %s m across', a.narrow > AREA_WIDE and ('over '..(AREA_WIDE / 100)) or
                            string.format('%.0f', a.narrow / 100)) or a.skipped and ' (indoor, named outdoor or open' or ' (outdoor')
                            ..', box '..tostring(a.dims)..')') or '',
                        hit and 'tunnel' or 'not a tunnel', tostring(sky.world)))
                end
            end
        end
        if hit ~= roof.hit then
            roof.hit = hit
            roof.since = hit and V.t or nil
        end
    end
    local on = roof.hit and roof.since and V.t - roof.since >= ROOF_HOLD
    roof.amount = on and math.min(1, roof.amount + dt / ROOF_IN) or math.max(0, roof.amount - dt / ROOF_OUT)
    return roof.amount
end
-- for the menu: in a tunnel now (true / false) and the game's box the vehicle is in (nil = none); nil if
-- the game's areas could not be read on this map
function V.picRoof()
    if not roof.readable then return nil end
    return roof.hit, roof.area
end
V.AREA_WIDE_M = AREA_WIDE / 100
-- how much glaring places are toned down: the contrast left in the bright parts (1 = the engine's
-- default; 100 -> 0.25, then on to 0 = the most there is at 200)
local function glareScale(g)
    if g <= 100 then return 1 - 0.0075 * g end
    return math.max(0, 0.25 - 0.0025 * (g - 100))
end

-- Lamps (2026-10-18): the bright ball round the game's standing lamps (BP_CMN_LightFixture_Base). The lamp's
-- blueprint sets its parts from its own values again and again (RefreshFixture, many times a second - the
-- earlier tries on the parts themselves were undone at once): its glow card (SM_Glow_Billboard, material
-- 'Glow Intensity' = the lamp's 'Glow Intensity' x 'SM Glow Ratio'; hidden when 'SM Glow Active' is off) and
-- its light's scattering in the fog (= its VolumetricScattering, 5 on these lamps, x the global lighting's
-- multiplier). So the lamp's own values are set and its refresh uses them; a slider each, to tell which one
-- makes the ball. The game's values are kept per lamp and put back at 100.
local LAMP_CLASS = 'BlueprintGeneratedClass /Game/Griffin/Lighting/Blueprints/LightFixture/BP_CMN_LightFixture_Base.BP_CMN_LightFixture_Base_C'
local lamps = { world = nil, list = {}, next = 0, findAt = 0, said = nil, checkAt = nil, card = 1, air = 1 }
local function lampFind()
    local c = api:find_uobject(LAMP_CLASS)
    if not c then
        if lamps.said ~= lamps.world then lamps.said = lamps.world; log('lamps: none of the game\'s here (their class is not loaded)') end
        return
    end
    local actors = {}
    pcall(function()
        areas.gs = areas.gs or api:find_uobject('Class /Script/Engine.GameplayStatics'):get_class_default_object()
        areas.gs:GetAllActorsOfClass(api:get_engine().GameViewport.World, c, actors)
    end)
    local added, failed, err1 = 0, 0, nil
    for _, a in ipairs(actors) do
        local ok, err = pcall(function()
            local addr = a:get_address()
            if lamps.list[addr] then return end
            local l = { actor = a, ownGlow = tonumber(a['Glow Intensity']), ownActive = a['SM Glow Active'] == true,
                ownAir = tonumber(a.VolumetricScattering) }
            if not l.ownGlow or not l.ownAir then error('its values are not readable') end
            lamps.list[addr] = l
            added = added + 1
        end)
        if not ok then failed = failed + 1; err1 = err1 or tostring(err) end
    end
    if added > 0 or failed > 0 then
        log(string.format('lamps on %s: %d found, %d new%s', tostring(lamps.world), #actors, added,
            failed > 0 and string.format(', %d not readable (%s)', failed, err1) or ''))
    end
end
-- a lamp set to shares of its own values (1 = the game's); its blueprint's refresh applies them
local function lampApply(l, card, air)
    local a = l.actor
    local glowV, airV = l.ownGlow * card, l.ownAir * air
    local active = l.ownActive and card > 0.005
    local changed = false
    if math.abs((tonumber(a['Glow Intensity']) or -1) - glowV) > 1e-6 then a['Glow Intensity'] = glowV; changed = true end
    if (a['SM Glow Active'] == true) ~= active then a['SM Glow Active'] = active; changed = true end
    if math.abs((tonumber(a.VolumetricScattering) or -1) - airV) > 1e-4 then a.VolumetricScattering = airV; changed = true end
    -- (its refresh hides the card when it is off, but never shows it again)
    local comp = a.SM_Glow_Billboard
    if comp and l.ownActive then
        if not active and not l.hid then
            comp:SetHiddenInGame(true, false); comp:SetVisibility(false, false); l.hid = true
        elseif active and l.hid then
            comp:SetHiddenInGame(false, false); comp:SetVisibility(true, false); l.hid = false
        end
    end
    if changed then pcall(function() a:RefreshFixture() end) end
end
local function lampTick()
    if lamps.world ~= sky.world then lamps.world, lamps.list, lamps.checkAt = sky.world, {}, nil end
    local p = V.pic
    local card = p.active and math.max(0, math.min(1, V.picVal('picLampCard') / 100)) or 1
    local air = p.active and math.max(0, math.min(1, V.picVal('picLampAir') / 100)) or 1
    local want = card < 0.995 or air < 0.995
    if not want then card, air = 1, 1 end
    if not want and next(lamps.list) == nil then lamps.card, lamps.air = 1, 1; return end
    local changed = card ~= lamps.card or air ~= lamps.air
    if not changed and V.t < lamps.next then return end
    lamps.next = V.t + 1
    if want and V.t >= lamps.findAt then lamps.findAt = V.t + 2; lampFind() end
    local n, first = 0, nil
    for addr, l in pairs(lamps.list) do
        if pcall(lampApply, l, card, air) then n = n + 1; first = first or l else lamps.list[addr] = nil end
    end
    if changed then
        lamps.card, lamps.air, lamps.checkAt = card, air, V.t + 2
        log(string.format('lamps: glow card x%.2f, light in the air x%.2f on %d lamps', card, air, n))
    end
    -- (2 s after a change: one lamp read back - did the game keep it)
    if lamps.checkAt and V.t >= lamps.checkAt and first then
        lamps.checkAt = nil
        local ok, err = pcall(function()
            local a = first.actor
            lamps.lightClass = lamps.lightClass or api:find_uobject('Class /Script/Engine.LocalLightComponent')
            local light = (a:K2_GetComponentsByClass(lamps.lightClass) or {})[1]
            local comp = a.SM_Glow_Billboard
            log(string.format('lamps: one reads Glow Intensity %s (game %s), card active %s, hidden %s; VolumetricScattering %s (game %s), its light\'s %s',
                tostring(a['Glow Intensity']), tostring(first.ownGlow), tostring(a['SM Glow Active']), tostring(comp and comp.bHiddenInGame),
                tostring(a.VolumetricScattering), tostring(first.ownAir), tostring(light and light.VolumetricScatteringIntensity)))
        end)
        if not ok then log('lamps: reading one back failed: '..tostring(err)) end
    end
    if not want then lamps.list = {} end
end

V.onTick('picture', function(dt)
    if V.t >= sky.nextLook then
        sky.nextLook = V.t + 1
        pcall(lookAround)
    end
    local exp = V.picVal('picExp')
    local hi = V.picVal('picHi') / 100
    local bloom = V.picVal('picBloom') / 100
    local sat = V.picVal('picSat') / 100
    local con = V.picVal('picCon') / 100
    local low = V.picVal('picLow')
    local tunnel = V.picVal('picTunnel')
    local minEV = V.picVal('picMinEV')
    local glare = V.picVal('picGlare')
    local shadow = V.picVal('picShadow')
    local black, vib, temp = V.picVal('picBlack'), V.picVal('picVib'), V.picVal('picTemp')
    local pair, pairLift = V.picVal('picPair'), V.picVal('picPairLift')
    local pairKeep = math.min(1, math.max(0, V.picVal('picPairKeep') / 100))
    local p = V.pic
    p.active = V.cfg.extras and (math.abs(exp) > 0.001 or math.abs(hi - 1) > 0.001 or math.abs(bloom - 1) > 0.001
        or math.abs(sat - 1) > 0.001 or math.abs(con - 1) > 0.001 or low > 0.5 or tunnel > 0.5 or minEV > 0.05
        or glare > 0.5 or shadow > 0.5 or black > 0.5 or vib > 0.5 or math.abs(temp) > 0.5 or V.picVal('picUncap') > 0.5
        or pair > 0.5 or V.picVal('picLampCard') < 99.5 or V.picVal('picLampAir') < 99.5) or false
    -- deeper blacks: the black point lowered - the engine's colour offset, taken off every colour before
    -- its film curve (scene light: middle grey 0.18; 100 here takes off 0.02, the darkest parts go black)
    p.offset = black > 0.5 and -0.0002 * black or nil
    -- vibrance: more colour where the film curve washed it out - by brightness range, the engine has no
    -- other way (it can't tell a pale colour from a vivid one): the bright range most turned lamps and
    -- candles neon (the user, 2026-10-18), so now the bright and the middle range alike, the dark less
    -- (100 = +30 / +30 / +15 %)
    p.satHi = vib > 0.5 and 1 + 0.003 * vib or nil
    p.satMid = vib > 0.5 and 1 + 0.003 * vib or nil
    p.satLo = vib > 0.5 and 1 + 0.0015 * vib or nil
    -- colour temperature: the engine's white balance (6500 K); higher = warmer (+100 here = 8500 K)
    p.temp = math.abs(temp) > 0.5 and 6500 + 20 * temp or nil
    -- (the menu's compare box: the game's own picture while it is ticked; off once the menu is closed)
    if V.picCompare and V.t - (V.picCompareSeen or 0) > 1 then V.picCompare = false end
    if V.picCompare then p.active = false end
    pcall(lampTick)
    -- tone down glaring places (everywhere, or under a roof: Tunnels) / lift dark places: Unreal's local
    -- exposure, which darkens or brightens each part of the picture by its own brightness
    local g = math.max(glare, tunnel * roofAmount(dt, p.active and tunnel > 0.5))
    p.glare = g > 0.5 and glareScale(g) or nil
    -- Expose for the bright outside, keep the inside (2026-10-18; the user found it by hand: the floor raised
    -- to 11 - 13 took the glare off the outside seen from a tunnel but darkened the inside, Lift dark places
    -- brought the inside back): one slider moves both. The floor 8 + 7 x (0..100 %) EV100 (the game's own in
    -- its picture volumes is 8 - 10; lower would brighten); the game is taken to have measured about 8 EV, so
    -- the floor darkens the picture by d = floor - 8 stops. The inside is lifted back with a tone curve, not
    -- the local exposure: that one judges each part by its neighbourhood and turned the faint light around
    -- lamps into flat bright balls (the user; it was nothing in the map: fog, fog planes, glow cards and bloom
    -- all ruled out). The engine's colour gamma (pow(colour, 1 / gamma) on the light after exposure) lifts
    -- each part by its own brightness only - the darker the more, 1.0 stays, brighter than that is pulled down
    -- a little. The inside taken to sit about 6 stops below 1.0 before the floor: (6 + d)(1 - 1 / gamma) = d
    -- lifts it back by d, the ratio scaling that (100 = as worked out; near, not exact). Next to the own
    -- floor slider the higher floor is used; the own Lift dark places stays its own (the local exposure).
    -- Keep the inside's contrast (2026-10-18): the lamps' glow grew with the tone curve too and the inside
    -- looked flat (the user) - the glow is the lamp's fading light squeezed by any lift that keeps the bright
    -- down, the way does not matter. So the share lifted by the local exposure (the way before, the inside
    -- keeps its contrast: max(0.1, 1 - ratio x (1 - 2.5 / (2.5 + d)))) against the tone curve: 0 = the curve
    -- alone, 100 = the local exposure alone, between = each its part. Next to the own Lift dark places the
    -- stronger lift is used.
    -- Lamps, deep dark: not lifted too far (2026-10-18; the user: with the floor raised the lamps' soft light
    -- shows in the dark tunnel, lifting the dark then made it glow far too much): the curve lifts the darker
    -- the more, so what is darker than the inside (a lamp's faint light in the dark, deep shadows) went past
    -- the game's own picture. Ticked: below the inside the lift stays what the curve gives there (about d
    -- stops x the ratio) - the engine's shadow range set to just above the inside (2^(0.5 - (6 + d))), the
    -- curve undone in it (its gamma x 1 / gamma) and an even gain instead, the curve's own lift at that edge
    -- (no step, never darker for brighter; at most 0.06 stops over, the deepest up to 0.4 under). Only on the
    -- curve's share: the local exposure can't be held like that.
    local pairFloor, pairGamma, pairShadow, capMax, capGain = nil, nil, nil, nil, nil
    if pair > 0.5 then
        pairFloor = 8 + 7 * math.min(1, pair / 100)
        local d = pairFloor - 8
        local k = math.min(0.75, (pairLift / 100) * d / (6 + d))
        pairGamma = 1 / (1 - k * (1 - pairKeep))
        pairShadow = math.max(0.1, 1 - pairKeep * (pairLift / 100) * (1 - 2.5 / (2.5 + d)))
        local ke = k * (1 - pairKeep)
        if V.picVal('picPairCap') > 0.5 and ke > 0.0005 then
            capMax = 2 ^ (0.5 - (6 + d))
            capGain = capMax ^ (-ke)
        end
    end
    p.gamma = pairGamma and pairGamma > 1.0005 and pairGamma or nil
    p.capMax = p.gamma and capMax or nil
    p.capGain = p.gamma and capGain or nil
    local sh = shadow > 0.5 and (1 - 0.0075 * shadow) or nil
    if pairShadow and pairShadow < 0.9995 and (not sh or pairShadow < sh) then sh = pairShadow end
    p.shadow = sh
    -- Lift by blending two pictures (2026-10-18; the lamps' glow stayed too strong with the curve, its cap
    -- and the local exposure): the engine's other local exposure (Fusion, UE 5.5) makes a darker and a
    -- brighter picture and takes each part from where it is neither too bright nor too dark, so a lamp too
    -- bright in the brighter one comes from the darker one. For every local exposure use here.
    p.fusion = (p.glare or p.shadow) and V.picVal('picFusion') > 0.5 or nil
    if p.active and (p.glare or p.shadow) then needLocalExposure() end
    -- eye adaptation (0 = the game's own): the part of the picture it measures by, from its darkest share up
    -- (Unreal's default 10 to 90 of 100; the older tunnel control); the least light it still brightens for
    -- (EV100)
    if low > 0.5 then
        p.low, p.high = low, math.min(100, math.max(90, low + 1.5))
    else
        p.low, p.high = nil, nil
    end
    local floorEV = minEV > 0.05 and minEV or nil
    if pairFloor and (not floorEV or pairFloor > floorEV) then floorEV = pairFloor end
    p.minBright = floorEV and fromEV(floorEV) or nil
    -- Bright skies turning white (2026-10-18): the game's own picture volumes (Jakku, around the big wrecks,
    -- in its sunset / dawn light; 75 - 100 m blending in) do not let the picture get darker than a set level
    -- (AutoExposureMaxBrightness 12 - 13 EV100), so looking at the bright sky from under a wreck it turned
    -- white, and fine again a little further on. Ticked: that limit set back to the engine's own (20 EV100,
    -- what it is outside those volumes) - the camera's settings come after the volumes'.
    p.maxBright = V.picVal('picUncap') > 0.5 and fromEV(20) or nil
    local i = sky.info or {}
    -- exposure: on top of what the sky's post-process (or else its weather) sets here, else the default 0
    p.exp = math.abs(exp) > 0.001 and ((i.ppExp or i.wExp or 0) + exp) or nil
    -- bloom: a share of the bloom here (the engine default 0.675 if none is known)
    p.bloom = math.abs(bloom - 1) > 0.001 and ((i.ppBloom or i.wBloom or 0.675) * bloom) or nil
    p.hi, p.sat, p.con = hi, sat, con
    -- what is written now, in the log when it changes (at most every 2 s; to see what a test really used)
    if V.t >= (p.toldAt or 0) + 2 then
        local function f(v, fmt) return v and string.format(fmt, v) or '-' end
        local now = p.active and string.format('exposure %s, floor %s EV, curve gamma %s, cap %s (gain %s), local lift %s, glare %s, fusion %s, black %s, lamps card x%.2f air x%.2f',
            f(p.exp, '%.2f'), f(floorEV, '%.1f'), f(p.gamma, '%.3f'), f(p.capMax, '%.5f'), f(p.capGain, '%.2f'), f(p.shadow, '%.3f'),
            f(p.glare, '%.3f'), p.fusion and 'on' or '-', f(p.offset, '%.4f'), lamps.card, lamps.air) or 'the game\'s own'
        if now ~= p.told then
            p.told, p.toldAt = now, V.t
            log('picture now ('..tostring(V.picPlace())..'): '..now)
        end
    end
end)
