-- Menu screen positions. Some menus / scenes put the game camera far from where they are drawn
-- (under the map, inside a wall); for those the VR view gets a saved UEVR camera offset
-- (VR_CameraForwardOffset / Right / Up). Race, vehicle and character cameras are never touched,
-- and nothing is offset while the cockpit places the view.
local log = V.logger('views')
local S = V.cam
local vr = uevr.params.vr
local FILE = 'swgr_vr_views.json'
local KEYS = { 'VR_CameraForwardOffset', 'VR_CameraRightOffset', 'VR_CameraUpOffset' }
-- built in (can be changed, not removed): { forward, right, up, [save time] }
local DEFAULTS = {
    ORIGIN = { 7000, 0, 8000 },
    ['L_FrontEnd/FuseCinematicCameraActor_UAID_CC96E515467997BB02_1989858585'] = { 840, -20, 20, 7 },
    ['L_FrontEnd/FuseCinematicCameraActor_UAID_CC96E515467999BB02_1450431967'] = { 2050, -85.1, 0 },
    ['L_Mastiff_LOOP_A/CineCameraActor_UAID_CC96E509E6AA352D02_2147455930'] = { -85.1, 30, -15, 1 },
    ['L_Mastiff_LOOP_B/CineCameraActor_UAID_CC96E509E6AA352D02_2147469619'] = { -85, 30, 0, 2 },
    ['L_Mastiff_P2P_A/CineCameraActor_UAID_CC96E509E6AA352D02_2147463442'] = { -85, 40, 0, 3 },
    ['L_Spaniel_Loop_B/FuseCinematicCameraActor_2146976197'] = { -100, 0, 0, 4 },
}
V.VIEW_NAMES = {
    ORIGIN = { 'Tour start / logbook (no camera)' },
    ['L_FrontEnd/FuseCinematicCameraActor_UAID_CC96E515467997BB02_1989858585'] = { 'Main menu - campaign' },
    ['L_FrontEnd/FuseCinematicCameraActor_UAID_CC96E515467999BB02_1450431967'] = { 'Main menu - multiplayer' },
    ['L_Mastiff_LOOP_A/CineCameraActor_UAID_CC96E509E6AA352D02_2147455930'] = { 'Race results' },
    ['L_Mastiff_LOOP_B/CineCameraActor_UAID_CC96E509E6AA352D02_2147469619'] = { 'Race results (2)' },
    ['L_Mastiff_P2P_A/CineCameraActor_UAID_CC96E509E6AA352D02_2147463442'] = { 'Race results (3)' },
    ['L_Spaniel_Loop_B/FuseCinematicCameraActor_2146976197'] = { 'Engine start shot' },
}
local offsets = {}
for k, o in pairs(DEFAULTS) do offsets[k] = o end
do
    local ok, t = pcall(json.load_file, FILE)
    if ok and type(t) == 'table' then
        for k, o in pairs(t) do
            if type(o) == 'table' and tonumber(o[1]) and tonumber(o[2]) and tonumber(o[3]) then offsets[k] = o end
        end
    end
end
V.viewOffsets, V.viewDefaults = offsets, DEFAULTS
local function save() pcall(json.dump_file, FILE, offsets) end

-- Matching: exact key; same world + camera without its trailing number; or "auto": the same
-- camera in another map (every race map has its own copy of the results camera) - newest save wins.
local function stripNum(k) return (k:gsub('_%d+$', '')) end
local function actorBase(k) return stripNum(k:match('/(.*)$') or k) end
local function lookupKey(key)
    if not key then return nil end
    if type(offsets[key]) == 'table' then return key, false end
    local want, hit, n = stripNum(key), nil, 0
    for k, v in pairs(offsets) do
        if type(v) == 'table' and stripNum(k) == want then hit = k; n = n + 1 end
    end
    if n == 1 then return hit, false end
    if key == 'ORIGIN' then return nil end
    local base, best, bestT = actorBase(key), nil, -1
    for k, v in pairs(offsets) do
        if type(v) == 'table' and k ~= 'ORIGIN' and actorBase(k) == base then
            local tt = tonumber(v[4]) or 0
            if tt > bestT or (tt == bestT and k < best) then best, bestT = k, tt end
        end
    end
    if best then return best, true end
    return nil
end
V.viewLookup = lookupKey

local function setOffset(o)
    for i, k in ipairs(KEYS) do
        pcall(function() vr.set_mod_value(k, string.format('%.3f', o[i] or 0)) end)
    end
end
local function getOffset()
    local r = {}
    for i, k in ipairs(KEYS) do
        local ok, v = pcall(function() return vr:get_mod_value(k) end)
        r[i] = (ok and tonumber(v)) or 0
    end
    return r
end

-- Which view is active: ORIGIN for camera-less menus, <world>/<camera actor> for cinematic menu
-- cameras, nil for everything not handled.
local function viewKey()
    local pc = api:get_player_controller(0)
    local cm = pc and pc.PlayerCameraManager
    if not cm then return nil end
    local target = cm.ViewTarget.Target
    if not target then return nil end
    if S.enabled and S.renderEye then return nil end          -- the cockpit places the view
    local cls = target:get_class():get_fname():to_string()
    if cls == 'BP_GfnPlayerController_C' then
        local l = cm.CameraCachePrivate.POV.Location
        if math.abs(l.X) < 1 and math.abs(l.Y) < 1 and math.abs(l.Z) < 1 then return 'ORIGIN' end
        return nil
    end
    if not cls:find('Camera') then return nil end                       -- vehicles, characters
    if cls:find('^BP_Player') or cls:find('Crash') or cls:find('Takedown') then return nil end
    local world = '?'
    pcall(function() world = target:get_outer():get_outer():get_fname():to_string() end)
    return world..'/'..target:get_fname():to_string()
end

local st = { ticks = 0, currentKey = nil, appliedKey = nil, appliedOffset = nil }
V.viewState = st
local function clear()
    if st.appliedKey then setOffset({ 0, 0, 0 }) end
    st.appliedKey, st.appliedOffset = nil, nil
end
V.onTick('views', function()
    st.ticks = st.ticks + 1
    if not V.cfg.viewOffsets then
        if st.appliedKey then clear() end
        st.currentKey = nil
        return
    end
    -- the cockpit takes over from an offset scene camera: fade the offset out with the move-in
    if st.appliedKey and st.appliedOffset and S.enabled and S.renderEye then
        local w = tonumber(V.introBlend) or 1
        if w < 1 then
            local o = st.appliedOffset
            setOffset({ (o[1] or 0) * (1 - w), (o[2] or 0) * (1 - w), (o[3] or 0) * (1 - w) })
            return
        end
        clear(); st.currentKey = nil
        return
    end
    if st.ticks % 6 ~= 0 then return end
    local ok, key = pcall(viewKey)
    if not ok then key = nil end
    if key == st.currentKey then return end
    st.currentKey = key
    local k = lookupKey(key)
    local o = k and offsets[k]
    if o then
        setOffset(o); st.appliedKey, st.appliedOffset = key, o
        log('view '..key..' -> offset '..string.format('%g / %g / %g', o[1], o[2], o[3]))
    elseif st.appliedKey then
        clear()
    end
end)
V.onReset(clear)

-- menu helpers: save the current UEVR camera offset for the current view / forget it
function V.viewSaveCurrent()
    local key = st.currentKey
    if not key then return false end
    local o = getOffset()
    local newest = 0
    for _, v in pairs(offsets) do if type(v) == 'table' then newest = math.max(newest, tonumber(v[4]) or 0) end end
    o[4] = newest + 1                                 -- newest save wins on other maps
    offsets[key] = o
    st.appliedKey, st.appliedOffset = key, o
    save()
    return true
end
function V.viewForget(k)
    offsets[k] = DEFAULTS[k]
    save()
    if st.appliedKey and lookupKey(st.appliedKey) == nil then clear() end
    st.currentKey = nil                              -- re-evaluate on the next check
end
