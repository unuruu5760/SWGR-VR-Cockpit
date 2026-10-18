-- Which vehicle is driven (model + type), its eye position and body follow on jumps (both saved for
-- the vehicle as soon as the menu sliders move; untouched values follow the shared ones).
local log = V.logger('vehicle')
local S = V.cam

V.TYPES = { 'Bike', 'Car', 'Skimmer', 'Plane' }
V.TYPE_NAMES = { Bike = { 'Bike' }, Car = { 'Landspeeder' }, Skimmer = { 'Skimmer' }, Plane = { 'Podracer' } }
-- body follow on jumps (bikes: the rider stands up): how much the eye follows the pilot chest up /
-- forward. Set in the View menu for the vehicle driven (not listed in "Fine tuning").
V.tunable('view', 'followUp', 0.74, 0, 3, 'Jumps: up with the pilot',
    'How much your eyes rise with the pilot\'s chest on jumps. 1 = exactly as much, 0 = not at all, above 1 = even more than the chest. Still inside the body: raise it. Too high: lower it.').main = true
V.tunable('view', 'followFwd', 0.0, -1, 3, 'Jumps: forward with the pilot',
    'How much your eyes move forward with the pilot on jumps. Above 1 = even more than the pilot. Dashboard too close in the air: lower it, below 0 the eyes even move back.').main = true
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

-- Which vehicle it is: the name its values are saved under ('<Type>/<Model>').
-- In the garage (Edit Vehicle) every part slot can take another model's part, and the game's own
-- event vehicles mix models too. What the player sits in and sees around them is the part the seat
-- is in: on landspeeders and skim speeders the rear, on speeder bikes the controls, on podracers the
-- pod. Swap that part and the seat and the cockpit change; swap any other part and they don't. So a
-- vehicle is named after the model of its seat part (the user's rule, 2026-10-18), and everything
-- saved for a vehicle (eye position, banking, shake, fine tuning) follows that part.
-- Read from the part's meshes (/Vehicles/<Type>s/Customisation/<Model>/<Slot>/...), else from the
-- vehicle's recipe (CustomisationRoot.ActiveRecipe or the player's: Parts { PartType = slot,
-- vehicleKit = model, 'MythP2' = a Myth tier }). Only if neither has the seat part: the model the
-- recipe's name names, then the model most meshes come from (how older versions named it).
-- Once found from the seat part, the name is kept for that vehicle until the next one.
V.MODELS = {
    Bike = { 'Boa', 'Boomslang', 'Bushmaster', 'Cobra', 'Cottonmouth', 'Hognose', 'Kingsnake', 'Lancehead', 'Mamba', 'Rattlesnake', 'Sidewinder', 'Taipan' },
    Car = { 'Beluga', 'Bluefin', 'Bowhead', 'Goblin', 'Hammerhead', 'Mako', 'Marlin', 'Minke', 'Orca', 'Snook', 'Tarpon', 'Wahoo' },
    Skimmer = { 'Albatross', 'Condor', 'Crow', 'Jackdaw', 'Merlin', 'Needletail', 'Pelican', 'Peregrine', 'Raven', 'Rook', 'Saker', 'Stork' },
    Plane = { 'Cretornis', 'Dearc', 'Hexing', 'Myth', 'Nesodon', 'Northropi', 'Sordes', 'Tarchia' },
}
V.SEAT_SLOT = { Car = 'Rear', Skimmer = 'Rear', Bike = 'Controls', Plane = 'Root' }
-- the name the game shows for a model (the mark in Choose Model; VehicleText VehicleType_<Model>);
-- podracers have none there
V.MARKS = {
    Boa = 'Zillo', Boomslang = 'Revasi G', Bushmaster = 'Novyok', Cobra = 'Killion', Cottonmouth = 'DRD 61', Hognose = "Ri'con",
    Kingsnake = 'KO-5', Lancehead = 'AM-1', Mamba = 'Ciza T', Rattlesnake = 'Kreed', Sidewinder = "Pel'ake", Taipan = 'RAR 27',
    Beluga = 'ARZ 41', Bluefin = 'Vornskr', Bowhead = "Zak'nee", Goblin = 'Napaco D', Hammerhead = 'Jakobeast', Mako = "Dre'shi",
    Marlin = 'WI-9', Minke = 'Magus', Orca = 'NL-4', Snook = 'KJC 99', Tarpon = 'Starweb', Wahoo = 'Darc X',
    Albatross = 'Reek', Condor = 'Rathtar', Crow = 'Wist L', Jackdaw = 'HC-8', Merlin = 'MSM 04', Needletail = 'Cesca',
    Pelican = 'SU-3', Peregrine = 'SAH 66', Raven = 'Rak S', Rook = 'Sling', Saker = "Ta'han", Stork = "Mok'si",
}
V.SLOT_ORDER = {
    Bike = { 'Front', 'Rear', 'Wings', 'Controls', 'EngineC', 'EngineB' },
    Car = { 'Front', 'Rear', 'FrontL', 'FrontR', 'EngineL', 'EngineR' },
    Skimmer = { 'Rear', 'FrontL', 'FrontR', 'Front', 'EngineL', 'EngineR' },
    Plane = { 'Root', 'FrontL', 'FrontR', 'MidL', 'MidR', 'CoreL', 'CoreR', 'RearL', 'RearR', 'EngineL', 'EngineR' },
}
local BASE = { Bike = true, Car = true, Skimmer = true, Plane = true, Layout = true, Root = true, None = true }
-- the model a text names: a known model of type ty as a word of its own ('Taipan FE Plus',
-- 'Bike_Taipan_Ace02', 'MythP2'; not inside another word), the earliest one
function V.modelIn(text, ty)
    if type(text) ~= 'string' or text == '' then return nil end
    local best, at = nil, nil
    for _, m in ipairs(V.MODELS[ty] or {}) do
        local from = 1
        while true do
            local i, j = text:find(m, from, true)
            if not i then break end
            if not text:sub(i - 1, i - 1):match('%a') and not text:sub(j + 1, j + 1):match('%l') then
                if not at or i < at then best, at = m, i end
                break
            end
            from = i + 1
        end
    end
    return best
end
-- a part's model from its kit name ('MythP2' -> 'Myth'); a model the list doesn't know yet (a game
-- update) stays as it is, without a tier number
local function kitModel(kit, ty)
    if type(kit) ~= 'string' then return nil end
    local m = V.modelIn(kit, ty) or kit:gsub('P%d+$', '')
    if m == '' or BASE[m] or not m:match('^%u%a+$') then return nil end
    return m
end
-- the vehicle's customisation component (on it: the recipe)
local function customisation(p)
    local cc = nil
    pcall(function() cc = p.CustomisationComponent end)
    if cc then return cc end
    for _, c in ipairs(V.components(p, 'Engine.SceneComponent')) do
        local ok, n = pcall(function() return c:get_fname():to_string() end)
        if ok and n == 'CustomisationRoot' then return c end
    end
    return nil
end
-- text from the game without control characters (its strings can end in a NUL)
local function clean(x)
    if x == nil then return nil end
    if type(x) ~= 'string' then x = tostring(x) end
    return (x:gsub('%c', ''))
end
-- a recipe object: name, { slot = model }, archetype, text for the log; nil if it has neither a name
-- nor parts
local ARCHETYPE = { [0] = 'Car', [1] = 'Plane', [2] = 'Bike', [3] = 'Skimmer' }   -- EVehicleArchetype
local function fromRecipe(r, ty, where)
    if not r then return nil end
    local slots, list = {}, {}
    for _, u in ipairs(r.UnitRecipes or {}) do
        for _, part in ipairs(u.Parts or {}) do
            local slot, kit = clean(part.PartType), clean(part.vehicleKit)
            list[#list + 1] = slot..' '..kit
            local m = kitModel(kit, ty)
            if m and slots[slot] == nil then slots[slot] = m end
        end
    end
    local name = clean(r.RecipeName)
    if #list == 0 and not name then return nil end
    local okA, arch = pcall(function() return ARCHETYPE[tonumber(r.VehicleArchetype)] end)
    return { name = name, slots = slots, text = table.concat(list, ', '), where = where, archetype = okA and arch or nil }
end
-- the vehicle's own recipe (the one it was built from), on its customisation component
local function ownRecipeObject(p)
    local comps = {}
    pcall(function() comps[#comps + 1] = p.CustomisationComponent end)
    pcall(function() comps[#comps + 1] = p.CstRootComponent and p.CstRootComponent.CustomisationComponent end)
    pcall(function() comps[#comps + 1] = customisation(p) end)
    for _, cc in ipairs(comps) do
        local ok, r = pcall(function() return cc and cc.ActiveRecipe end)
        if ok and r then return r end
    end
    return nil
end
-- the player's vehicle recipe: GfnPlayerState.VehicleCustomisationComponent.VehicleRecipe
local function playerRecipeObject(p)
    local ps = p.PlayerState
    local vc = ps and ps.VehicleCustomisationComponent
    return vc and vc.VehicleRecipe
end
-- the race's recipe for the player who drives p: GameState.EventRecipeState_Replication.Racers[]
-- (Player = the player's state, VehicleCustomisation = the recipe it drives)
local function raceRecipe(p)
    local ps = p.PlayerState
    local id = ps and ps:get_address()
    local gs = api:get_engine().GameViewport.World.GameState
    local racers = gs and gs.EventRecipeState_Replication and gs.EventRecipeState_Replication.Racers
    for _, r in ipairs(racers or {}) do
        local pl = r.Player
        if id and pl and pl:get_address() == id then return r.VehicleCustomisation end
    end
    return nil
end
-- does a recipe that is not on the vehicle itself match the vehicle's parts? (it could be the one of
-- another vehicle of the player's, or an older one): at least half its part slots as on the meshes.
-- nil = can't tell yet (no part meshes)
local function agrees(rec, mslots)
    local total, same = 0, 0
    for slot, m in pairs(rec.slots) do
        if mslots[slot] then
            total = total + 1
            if mslots[slot] == m then same = same + 1 end
        end
    end
    if total < 3 then return nil end          -- (too few parts loaded to tell)
    return same * 2 >= total
end
-- the recipe: the vehicle's own; else the player's or the race's one if it matches the parts; nil if
-- there is none (yet)
local function readRecipe(p, ty, mslots, loaded)
    local ok, r = pcall(function() return fromRecipe(ownRecipeObject(p), ty, 'the vehicle') end)
    if ok and r and (r.name or next(r.slots)) then return r end
    for _, src in ipairs({ { playerRecipeObject, 'the player' }, { raceRecipe, 'the race' } }) do
        local ok2, r2 = pcall(function() return fromRecipe(src[1](p), ty, src[2]) end)
        if ok2 and r2 and (not r2.archetype or r2.archetype == ty) then
            local a = agrees(r2, mslots or {})
            if a == true or (a == nil and loaded and not next(r2.slots)) then return r2 end
        end
    end
    return nil
end
-- what the game has about the vehicle's recipe, for the log (once per vehicle; it tells where the
-- recipe can be read in a game version this script was not made for)
function V.describeRecipes(p)
    local out = {}
    local function add(k, f)
        local ok, v = pcall(f)
        out[#out + 1] = k..' '..(ok and tostring(v) or 'error')
    end
    local function show(r)
        if not r then return 'none' end
        local n = 0
        for _, u in ipairs(r.UnitRecipes or {}) do n = n + #(u.Parts or {}) end
        return '"'..tostring(clean(r.RecipeName))..'", '..n..' parts, archetype '..tostring(r.VehicleArchetype)
    end
    add('component', function() local cc = p.CustomisationComponent; return cc and cc:get_fname():to_string() or 'none' end)
    add('root component', function()
        local cc = p.CstRootComponent and p.CstRootComponent.CustomisationComponent
        return cc and cc:get_fname():to_string() or 'none'
    end)
    add('its recipe', function() return show(ownRecipeObject(p)) end)
    add('player recipe', function() return show(playerRecipeObject(p)) end)
    add('race recipe', function() return show(raceRecipe(p)) end)
    add('racers', function()
        local gs = api:get_engine().GameViewport.World.GameState
        return #(gs.EventRecipeState_Replication.Racers or {})
    end)
    return table.concat(out, '; ')
end
-- from the meshes: { slot = model }, the model most meshes come from, and a text for the log
local function readMeshes(p)
    local slots, counts, most, mostN = {}, {}, nil, 0
    for _, cn in ipairs({ 'Engine.SkeletalMeshComponent', 'Engine.StaticMeshComponent' }) do
        for _, c in ipairs(V.components(p, cn)) do
            local ok, path = pcall(function()
                local a = c.SkeletalMesh or c.StaticMesh
                return a and a:get_full_name() or ''
            end)
            local m, slot = nil, nil
            if ok then
                m, slot = path:match('/Customisation/([^/]+)/([^/]+)/')
                if not m then m = path:match('/Customisation/([^/]+)/') end
            end
            if m and not BASE[m] then
                counts[m] = (counts[m] or 0) + 1
                if counts[m] > mostN then most, mostN = m, counts[m] end
                if slot and slots[slot] == nil then slots[slot] = m end
            end
        end
    end
    local text = {}
    for m, n in pairs(counts) do text[#text + 1] = m..' '..n end
    table.sort(text)
    return slots, most, table.concat(text, ', '), counts
end
-- the name of vehicle p of type ty (see above): model, how it was found, whether it is final for this
-- vehicle, and the details for the log; nil while its parts are still loading (loaded = waited enough)
function V.nameVehicle(p, ty, loaded)
    local mslots, most, counts = readMeshes(p)
    local okR, rec = pcall(readRecipe, p, ty, mslots, loaded)
    if not okR then rec = nil end
    local info = { recipe = rec, counts = counts, most = most, meshSlots = mslots }
    local seat = V.SEAT_SLOT[ty]
    if seat and mslots[seat] then return mslots[seat], 'the seat part ('..seat..')', true, info end
    if seat and rec and rec.slots[seat] then return rec.slots[seat], 'the seat part ('..seat..', recipe)', true, info end
    if not loaded then return nil, nil, false, info end    -- (its parts may still be loading)
    local m = rec and V.modelIn(rec.name, ty)
    if m then return m, 'the recipe name (no seat part found)', false, info end
    if most then return most, 'most parts (no seat part found)', false, info end
    return nil, nil, false, info
end
-- vehicle type from the pawn class: VBP_<Type>_C, or a variant such as VBP_Plane_Memory_C (the
-- podracer of the campaign's memory races)
local function vehicleType(p)
    local ok, n = pcall(function() return p:get_class():get_fname():to_string() end)
    return ok and n:match('^VBP_(%a+)_') or nil
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
-- the eye a vehicle has without the user's: its built-in one, else the cockpit default
function V.defaultEyeFor(m)
    local b = m and V.VEH_DEFAULTS.eyes[m]
    if validEye(b) then return b end
    return V.DEFAULT_EYE
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
-- 'Nik Skandaro' (the menu shows the name only; the game's code name, e.g. Spinach, is for the log);
-- "not found" for no character or one without a known name
function V.pilotLabel(c)
    local n = c and V.PILOT_NAMES[c]
    return n or V.tr('not found')
end
-- 'Beluga' from 'Car/Beluga'; "not found" without one
-- the name the game shows ('Car/Wahoo' -> 'Darc X'); a model it has no mark for keeps its own name
function V.modelLabel(m)
    if not m then return V.tr('not found') end
    local n = m:match('/(.+)$') or m
    return V.MARKS[n] or n
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

-- Older versions (up to 2.1.0) named a vehicle after the model most of its meshes come from (with a
-- tie, any of them, from race to race). The names a file had when it came from such a version are
-- 'legacy'. When a vehicle is driven, its older names are put right, once, with no question asked:
--   - its seat-part name has no values yet: the older name's values move to it
--   - it has values: they stay (by today's rule it is that vehicle); the older name's are dropped
-- Either way the older names leave the file; what each had waits in 'moved'. Should a vehicle whose
-- seat-part name was moved away turn up later, it gets those values back, and they leave 'moved'
-- too. Once nothing waits there, the file is just like a new player's.
local OWN_KINDS = { 'eyes', 'feel', 'detail', 'pilotFollow' }
local function hasAny(m)
    for _, kind in ipairs(OWN_KINDS) do if V.veh[kind][m] ~= nil then return true end end
    return false
end
local function copyTable(t)
    if type(t) ~= 'table' then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copyTable(v) end
    return c
end
-- the older names of the vehicle named key: its models with the most meshes (all of a tie) that had
-- values when the file was upgraded
local function olderNames(counts, key, ty)
    local top, out = 0, {}
    for _, n in pairs(counts or {}) do if n > top then top = n end end
    for m, n in pairs(counts or {}) do
        local k = ty..'/'..m
        if n == top and k ~= key and V.veh.legacy[k] and hasAny(k) then out[#out + 1] = k end
    end
    table.sort(out)
    return out
end
-- put the older names of the vehicle named key right; a text for the log when something changed
function V.tidyOlderNames(key, ty, counts)
    local olds = olderNames(counts, key, ty)
    local took = nil
    if olds[1] and not hasAny(key) then
        for _, kind in ipairs(OWN_KINDS) do
            if V.veh[kind][olds[1]] ~= nil then V.veh[kind][key] = copyTable(V.veh[kind][olds[1]]) end
        end
        took = olds[1]
    end
    for _, k in ipairs(olds) do
        local keep = {}
        for _, kind in ipairs(OWN_KINDS) do keep[kind] = copyTable(V.veh[kind][k]); V.veh[kind][k] = nil end
        V.veh.legacy[k], V.veh.moved[k] = nil, keep
    end
    local was = V.veh.legacy[key]
    V.veh.legacy[key] = nil                 -- (a vehicle with this seat part: what it has is its own)
    if #olds > 0 or was then V.saveVeh() end
    if #olds == 0 then return nil end
    return (took and ('values of the older name '..took..' moved to '..key) or (key..' keeps its own values'))
        ..'; older name(s) removed: '..table.concat(olds, ', ')
end
-- a name moved away earlier that turns out to be a vehicle of its own: what it had comes back (and
-- leaves 'moved')
function V.restoreMoved(key)
    local keep = V.veh.moved[key]
    if type(keep) ~= 'table' or hasAny(key) then return false end
    for _, kind in ipairs(OWN_KINDS) do
        if keep[kind] ~= nil then V.veh[kind][key] = copyTable(keep[kind]) end
    end
    V.veh.moved[key] = nil
    V.saveVeh()
    return true
end

local pawnId, nextFind, pawnSince, final, tidied = nil, 0, 0, false, false
local LOAD_WAIT = 3                                     -- seconds a vehicle's parts may take to load
V.onTick('vehicle', function(dt)
    local p = api:get_local_pawn(0)
    local id = p and p:get_address()
    if id ~= pawnId then
        -- another vehicle (or the same one in a new race): named again from its own parts
        pawnId, nextFind, pawnSince, final, tidied, V.pilot = id, 0, V.t, false, false, nil
        V.model, V.vtype = nil, nil
    end
    if not p then
        if V.model then V.model, V.vtype = nil, nil end
        return
    end
    if V.t < nextFind then return end
    local ty = vehicleType(p)
    local loaded = V.t - pawnSince >= LOAD_WAIT
    if not final and ty then
        local okM, m, how, isFinal, info = pcall(V.nameVehicle, p, ty, loaded)
        if okM and m then
            final = isFinal
            local key = ty..'/'..m
            if key ~= V.model then
                V.model, V.vtype = key, ty
                if V.restoreMoved(key) then log('  '..key..': its values, moved away when another vehicle was put right, came back') end
                applyEye()
                local e, own = V.eyeFor(key)
                log(string.format('vehicle %s, eye %.1f / %.1f / %.1f (%s)', key, e[1], e[2], e[3], own and 'saved' or 'default'))
                local rec = info and info.recipe
                log('  named after '..tostring(how)..'; recipe '..(rec and ('from '..tostring(rec.where)..' "'..tostring(rec.name)..'": '..rec.text) or 'not found')
                    ..'; meshes per model: '..tostring(info and info.counts))
                local okD, d = pcall(V.describeRecipes, p)
                log('  game data: '..tostring(okD and d or d))
                if V.onVehicle then pcall(V.onVehicle, key) end
            end
        end
    end
    if not V.model then nextFind = V.t + 0.5; return end   -- (parts not loaded yet)
    nextFind = V.t + 3
    -- what older versions saved for this vehicle under the name they gave it (once the parts loaded)
    if loaded and not tidied then
        tidied = true
        local okO, _, _, _, counts = pcall(function() return readMeshes(p) end)
        local okT, text = pcall(V.tidyOlderNames, V.model, V.vtype, okO and counts or nil)
        if okT and text then applyEye(); log('  '..text) end
    end
    local okP, pk, path = pcall(findPilot, p)
    if okP and pk and pk ~= V.pilot then
        V.pilot = pk
        log('character '..V.pilotLabel(pk)..' ['..tostring(pk)..'] ('..tostring(path)..')')
    end
end)
