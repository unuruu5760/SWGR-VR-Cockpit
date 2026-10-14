-- Which vehicle is driven (model + type), its eye position and body follow on jumps (both saved for
-- the vehicle as soon as the menu sliders move; untouched values follow the shared ones).
local log = V.logger('vehicle')
local S = V.cam

V.TYPES = { 'Bike', 'Car', 'Skimmer', 'Plane' }
V.TYPE_NAMES = { Bike = { 'Bike', '바이크' }, Car = { 'Car', '자동차' }, Skimmer = { 'Skimmer', '스키머' }, Plane = { 'Plane', '비행기형' } }
-- body follow on jumps (bikes: the rider stands up): how much the eye follows the pilot chest up /
-- forward. Set in the View menu for the vehicle driven (not listed in "Fine tuning").
V.tunable('view', 'followUp', 0.74, 0, 3, 'Jumps: up with the pilot', '점프 때 몸 따라 위로',
    'How much your eyes rise with the pilot\'s chest on jumps. 1 = exactly as much, 0 = not at all, above 1 = even more than the chest. Still inside the body: raise it. Too high: lower it.',
    '점프 때 조종사 가슴이 올라가는 만큼 눈이 같이 올라가는 정도. 1 = 똑같이, 0 = 안 올라감, 1보다 크면 가슴보다 더 많이. 아직 몸통에 박히면 올리고, 너무 뜨면 내리세요.').main = true
V.tunable('view', 'followFwd', 0.0, -1, 3, 'Jumps: forward with the pilot', '점프 때 몸 따라 앞으로',
    'How much your eyes move forward with the pilot on jumps. Above 1 = even more than the pilot. Dashboard too close in the air: lower it, below 0 the eyes even move back.',
    '점프 때 조종사가 앞으로 쏠리는 만큼 눈이 같이 앞으로 가는 정도. 1보다 크면 조종사보다 더 많이. 공중에서 계기판이 너무 가까우면 내리세요. 0보다 낮으면 오히려 뒤로 빠져요.').main = true
local FOLLOW_MAX = 60                      -- cm, the most the eye moves with the body (per axis)
-- older vehicle files kept body follow apart ({ up, forward }): move what differs from the shared value
if V.oldFollow then
    for m, f in pairs(V.oldFollow) do
        if type(f) == 'table' then
            for i, key in ipairs({ 'followUp', 'followFwd' }) do
                local v = tonumber(f[i])
                if v and math.abs(v - V.sharedVal(key)) > 0.001 then V.setOwnVal('detail', m, key, v) end
            end
        end
    end
    V.oldFollow = nil
end
V.model, V.vtype = nil, nil

-- vehicle model name from its customisation parts: /Vehicles/<Type>s/Customisation/<Model>/...
local BASE = { Bike = true, Car = true, Skimmer = true, Plane = true, Layout = true, Root = true }
local function findModel(p)
    local counts, best, bestN = {}, nil, 0
    for _, cn in ipairs({ 'Engine.SkeletalMeshComponent', 'Engine.StaticMeshComponent' }) do
        for _, c in ipairs(V.components(p, cn)) do
            local ok, path = pcall(function()
                local a = c.SkeletalMesh or c.StaticMesh
                return a and a:get_full_name() or ''
            end)
            local m = ok and path:match('/Customisation/([^/]+)/')
            if m and not BASE[m] then
                counts[m] = (counts[m] or 0) + 1
                if counts[m] > bestN then best, bestN = m, counts[m] end
            end
        end
    end
    return best
end
local function vehicleType(p)
    local ok, n = pcall(function() return p:get_class():get_fname():to_string() end)
    return ok and n:match('^VBP_(%a+)_C$') or nil
end

-- eye of a model: the user's own (second value true), else its built-in one, else the cockpit default
local function validEye(e) return type(e) == 'table' and tonumber(e[1]) and tonumber(e[2]) and tonumber(e[3]) end
function V.eyeFor(m)
    local e = m and V.veh.eyes[m]
    if validEye(e) then return e, true end
    local b = m and V.VEH_DEFAULTS.eyes[m]
    if validEye(b) then return b, false end
    return V.DEFAULT_EYE, false
end
local function applyEye()
    local e = V.eyeFor(V.model)
    S.setEye(e[1], e[2], e[3])
end
-- the menu's eye sliders (current vehicle): stored for this model right away
function V.setEye(x, y, z)
    S.setEye(x, y, z)
    if V.model then V.veh.eyes[V.model] = { x, y, z }; V.saveVeh() end
end
function V.resetEye(m)
    m = m or V.model
    if m then V.veh.eyes[m] = nil; V.saveVeh() end
    if m == V.model then applyEye() end
end

-- The character driving: the codename of its outfit mesh (SKM_<Name>_Outfit_.., e.g. 'Tomato02'),
-- nil until found. Body follow on jumps is saved per vehicle and character (builds differ).
V.pilot = nil
-- Display names of the characters: the string table CharacterText, matched to the outfit codename
-- through each RacerDef's DefaultRecipe (game files, 2026-10-15). Tomato = the player's own
-- customisable character (DarkEnigma, "Shade"); Swede and the plane racers are AI opponents.
V.PILOT_NAMES = {
    Tomato01 = 'Shade', Tomato02 = 'Shade', Asparagus = 'Katja Mox', Celeriac = 'Griff Halloran',
    Pumpkin = 'Ary Quill', Pea = 'Soren Zaks', Spinach = 'Nik Skandaro', Cucumber = 'Goli & 02-R0',
    Okra = 'Fola Kanjen', Broccoli = 'Sen Fira', Carrot = 'Biddy Blas', Radish = 'Malis Vazosk',
    Potato = 'Lyren Shok', Turnip = 'Kestar Bool', Swede = 'Sebulba',
    Cabbage = 'Dud Bolt', Celery = 'Gasgano', Garlic = 'Teemto Pagalies', Onion = 'Ben Quadinaros', Pepper = 'Ody Mandrell',
}
-- 'Nik Skandaro (Spinach)'
function V.pilotLabel(c)
    local n = c and V.PILOT_NAMES[c]
    return n and (n..' ('..c..')') or tostring(c)
end
local function findPilot(p)
    local animCls = V.class('Griffin.VehicleAnimationComponent')
    local fallback = nil
    for _, c in ipairs(V.components(p, 'Engine.SkeletalMeshComponent')) do
        local owner = c:get_outer()
        if owner and (not animCls or owner:is_a(animCls)) then
            local a = c.SkeletalMesh
            local path = a and a:get_full_name() or ''
            local lower = path:lower()
            if path ~= '' and not lower:find('/heads/', 1, true) and not lower:find('/helmets/', 1, true) then
                local name = path:match('([^/%.%s]+)$') or path
                local code = name:match('^SKM_(%a+%d*)_') or name:match('^SKM_(.+)$') or name
                if lower:find('outfit', 1, true) then return code, path end
                fallback = fallback or { code, path }
            end
        end
    end
    if fallback then return fallback[1], fallback[2] end
    return nil
end

-- body follow of the vehicle and character driven: theirs, else the vehicle's, else the defaults
local followNow = { 0, 0, 0, 30 }
function V.followFor()
    followNow[1], followNow[2] = V.followVal(V.model, V.pilot, 'followUp'), V.followVal(V.model, V.pilot, 'followFwd')
    followNow[3], followNow[4] = 0, FOLLOW_MAX
    return followNow
end
-- set / forget both values for the vehicle and character driven (the menu sets them one by one)
function V.setFollow(up, fwd)
    if not V.model then return end
    if V.pilot then
        V.setFollowVal(V.model, V.pilot, 'followUp', up); V.setFollowVal(V.model, V.pilot, 'followFwd', fwd)
    else
        V.setOwnVal('detail', V.model, 'followUp', up); V.setOwnVal('detail', V.model, 'followFwd', fwd)
    end
end
function V.resetFollow(m)
    m = m or V.model
    if V.pilot then V.clearFollowVal(m, V.pilot) end
    V.clearOwnVal('detail', m, 'followUp'); V.clearOwnVal('detail', m, 'followFwd')
end

local pawnId, nextFind = nil, 0
V.onTick('vehicle', function(dt)
    local p = api:get_local_pawn(0)
    local id = p and p:get_address()
    if id ~= pawnId then pawnId, nextFind, V.pilot = id, 0, nil end
    if not p then
        if V.model then V.model, V.vtype = nil, nil end
        return
    end
    if V.t < nextFind then return end
    local okM, m = pcall(findModel, p)
    m = okM and m or nil
    local ty = vehicleType(p)
    if m and ty then
        nextFind = V.t + 3
        local key = ty..'/'..m
        if key ~= V.model then
            V.model, V.vtype = key, ty
            applyEye()
            local e, own = V.eyeFor(key)
            log(string.format('vehicle %s, eye %.1f / %.1f / %.1f (%s)', key, e[1], e[2], e[3], own and 'saved' or 'default'))
            if V.onVehicle then pcall(V.onVehicle, key) end
        end
        local okP, pk, path = pcall(findPilot, p)
        if okP and pk and pk ~= V.pilot then
            V.pilot = pk
            log('character '..V.pilotLabel(pk)..' ('..tostring(path)..')')
        end
    else
        nextFind = V.t + 0.5                            -- parts not loaded yet
    end
end)
