-- Race start. Before a race the game shows its own camera (view target FuseCinematicCameraActor:
-- the engine side-on, the start "bang"), then swings round behind the car. Here the cockpit pauses
-- during that shot (S.enabled = false, not saved) and, LEAVE_DELAY s after the engine starts (or
-- when the game leaves the shot), the view travels from the game camera into the cockpit.
-- Also: in the game's own cameras (the start shot, third person) the car body hums a little once
-- the engine runs (the game leaves it perfectly still).
local log = V.logger('intro')
local S = V.cam
local INTRO_CAMERA = 'FuseCinematicCameraActor'
local INTRO_MAX = 90                       -- s: never hold the cockpit off longer than this
V.tunable('start', 'leaveDelay', 2.7, 0, 6, 'Wait after the engine start (s)', 'In the engine start shot before the race: how many seconds it stays on after the engine starts before the view moves into the cockpit. 0 = moves in right away.')
V.tunable('start', 'blendTime', 2.1, 0.5, 5, 'Move into the cockpit (s)', 'How long the flight from the start shot\'s camera into your seat takes (seconds). Short = a quick swoop, long = slow.')
local HEAD_HIDE_AT = 0.9                   -- the pilot's head is hidden again at 90 % of the trip

local st = { state = 'idle', paused = false, introT = 0, blendT = 0, w = 1, gameCam = nil, skipped = false,
             sawOff = false, onT = nil, early = false, savedPilot = nil }
V.introBlend = 1                           -- 0..1 while travelling into the cockpit (view offsets fade with it)

local function viewTargetClass()
    local pc = api:get_player_controller(0)
    local cm = pc and pc.PlayerCameraManager
    local target = cm and cm.ViewTarget.Target
    return target and target:get_class():get_fname():to_string() or ''
end
local function ignitionStatus()
    local p = api:get_local_pawn(0)
    local v = p and p.VehicleState
    return v and tonumber(v.IgnitionStatus) or -1
end
-- the pilot stays fully visible during the shot and the trip (field only, not saved)
local function keepPilotVisible()
    if st.savedPilot == nil and S.pilotVisibility ~= 'visible' then
        st.savedPilot = S.pilotVisibility
        S.pilotVisibility = 'visible'
    end
end
local function restorePilotMode()
    if st.savedPilot ~= nil and S.pilotVisibility == 'visible' then S.pilotVisibility = st.savedPilot end
    st.savedPilot = nil
end
local function resume()
    if st.paused and S.cameraMode == 'cockpit' then S.enabled = true end
    st.paused = false
end
local function startBlend(why)
    resume()
    st.state, st.blendT, st.w, st.gameCam = 'blend', 0, 0, nil
    log('moving into the cockpit ('..why..')')
end

-- the game camera of this frame, read right before the cockpit overwrites it
V.beforeDraw = function()
    if st.state ~= 'blend' then return end
    local ok, cam = pcall(function()
        local pov = api:get_player_controller(0).PlayerCameraManager.CameraCachePrivate.POV
        local l, r = pov.Location, pov.Rotation
        return { l.X, l.Y, l.Z, r.Pitch, r.Yaw, r.Roll }
    end)
    st.gameCam = ok and cam or nil
end

local function update(dt)
    local inIntro = viewTargetClass() == INTRO_CAMERA
    if not V.cfg.extras or not V.cfg.intro then
        if st.state ~= 'idle' then resume(); restorePilotMode(); st.state = 'idle' end
        st.w = 1
        return
    end
    if st.state == 'idle' then
        if inIntro and S.cameraMode == 'cockpit' and not st.skipped and not st.early then
            st.state, st.introT = 'intro', 0
            st.sawOff, st.onT = false, nil
            S.enabled = false; st.paused = true
            keepPilotVisible()
            log('engine start shot: cockpit paused')
        end
        if not inIntro then st.skipped, st.early = false, false end
    elseif st.state == 'intro' then
        st.introT = st.introT + dt
        local ign = ignitionStatus()
        if ign == 0 then st.sawOff = true
        elseif ign >= 1 and st.sawOff and not st.onT then st.onT = st.introT end
        if S.cameraMode ~= 'cockpit' or (S.enabled and st.paused) then
            -- the user switched cameras during the shot (hotkey / menu): skip it
            st.paused, st.skipped, st.state = false, true, 'idle'
            restorePilotMode()
        elseif st.onT and st.introT - st.onT >= V.val('leaveDelay') then
            st.early = true                              -- the game camera is still the shot: don't pause again
            startBlend('engine started')
        elseif not inIntro or st.introT > INTRO_MAX then
            startBlend('shot over')
        else
            S.enabled = false
        end
    elseif st.state == 'blend' then
        st.blendT = st.blendT + dt
        local x = math.min(1, st.blendT / math.max(0.1, V.val('blendTime')))
        st.w = x * x * (3 - 2 * x)                       -- ease in / out
        if x >= HEAD_HIDE_AT then restorePilotMode() end
        if x >= 1 or (inIntro and not st.early) or S.cameraMode ~= 'cockpit' then
            st.state, st.w = 'idle', 1
            restorePilotMode()
        end
    end
end

local function wrapAngle(a) return ((a + 180) % 360) - 180 end
-- from the game camera (this frame) to the placed cockpit view
V.hooks.intro = function(view, position, rotation)
    if st.state ~= 'blend' or st.w >= 1 or not st.gameCam then return end
    local g, w = st.gameCam, st.w
    position.x = g[1] + (position.x - g[1]) * w
    position.y = g[2] + (position.y - g[2]) * w
    position.z = g[3] + (position.z - g[3]) * w
    rotation.x = g[4] + wrapAngle(rotation.x - g[4]) * w
    rotation.y = g[5] + wrapAngle(rotation.y - g[5]) * w
    rotation.z = g[6] + wrapAngle(rotation.z - g[6]) * w
end

-------------------------------------------------------------------------------- engine idle on the car body
-- While the cockpit is NOT placing the view, the vehicle's CustomisationRoot (parent of the body
-- meshes and the pilot) is jiggled a little around its resting place: idle hum, more while W revs.
V.tunable('start', 'carIdle', 2.15, 0, 5, 'Car body: idle hum', 'Seen with the game cameras (start shot, third person): how much the standing vehicle body trembles from the engine. Multiplied by "Car body engine hum". 0 = still.')
V.tunable('start', 'carRev', 1.1, 0, 5, 'Car body: revving (W)', 'Extra trembling of the vehicle body while you rev with W. 0 = W changes nothing.')
local cs = { comp = nil, pawn = nil, base = nil, last = nil, phase = 0, rev = 0, on = false, hit = nil, nextFind = 0, failed = false }
local function csFind(p)
    for _, c in ipairs(V.components(p, 'Engine.SceneComponent')) do
        if c:get_fname():to_string() == 'CustomisationRoot' then return c end
    end
    return nil
end
local function csSet(c, x, y, z, pitch, roll)
    local loc = StructObject.new(api:find_uobject('ScriptStruct /Script/CoreUObject.Vector')); loc.X, loc.Y, loc.Z = x, y, z
    local rot = StructObject.new(api:find_uobject('ScriptStruct /Script/CoreUObject.Rotator')); rot.Pitch, rot.Yaw, rot.Roll = pitch, cs.base.yaw, roll
    cs.hit = cs.hit or StructObject.new(api:find_uobject('ScriptStruct /Script/Engine.HitResult'))
    -- (location, rotation, no sweep, hit result out, teleport: no physics velocity from this)
    c:K2_SetRelativeLocationAndRotation(loc, rot, false, cs.hit, true)
    cs.last = { x, y, z }
end
local function csRead(c)
    local l, r = c.RelativeLocation, c.RelativeRotation
    return { x = l.X, y = l.Y, z = l.Z, pitch = r.Pitch, yaw = r.Yaw, roll = r.Roll }
end
local function csStop()
    if cs.on and cs.comp and cs.base then
        local b = cs.base
        pcall(csSet, cs.comp, b.x, b.y, b.z, b.pitch, b.roll)
    end
    cs.on = false
end
local function csUpdate(dt)
    local p = api:get_local_pawn(0)
    local id = p and p:get_address()
    if id ~= cs.pawn then cs.on = false; cs.comp, cs.pawn, cs.base, cs.last = nil, id, nil, nil; cs.nextFind = V.t + 1 end
    if not p then return end
    local v = p.VehicleState
    local ign = v and tonumber(v.IgnitionStatus) or 0
    local mph = v and tonumber(v.SpeedMPH) or 0
    local amount = V.cfg.extras and (tonumber(V.cfg.carShake) or 0) / 100 or 0
    if cs.failed or amount <= 0 or S.enabled or ign < 1 or mph >= 30 then csStop(); return end
    if not cs.comp then
        if V.t < cs.nextFind then return end
        cs.nextFind = V.t + 2
        cs.comp = csFind(p)
        if not cs.comp then return end
    end
    if not cs.on then cs.base = csRead(cs.comp); cs.on = true end
    -- if the game moved the body itself, follow its new resting place
    local cur = csRead(cs.comp)
    if cs.last and (math.abs(cur.x - cs.last[1]) > 0.01 or math.abs(cur.z - cs.last[3]) > 0.01) then cs.base = cur end
    local thr = v and math.max(tonumber(v.Throttle) or 0, tonumber(v.RPMScale) or 0) or 0
    cs.rev = cs.rev + (thr - cs.rev) * (1 - math.exp(-dt / (thr > cs.rev and 0.12 or 1.0)))
    local standing = 1 - math.min(1, math.max(0, (mph - 10) / 20))
    local amp = (0.25 * V.val('carIdle') + 0.6 * cs.rev * V.val('carRev')) * standing * amount     -- cm
    cs.phase = cs.phase + dt * (14 + 10 * cs.rev)
    local b, n = cs.base, V.noise
    local ok, err = pcall(csSet, cs.comp, b.x + n(cs.phase, 1) * 0.4 * amp, b.y + n(cs.phase, 2) * 0.6 * amp,
        b.z + n(cs.phase, 3) * amp, b.pitch + n(cs.phase * 0.8, 4) * amp * 0.15, b.roll + n(cs.phase * 0.8, 5) * amp * 0.2)
    if not ok then cs.failed = true; log('car body shake turned off: '..tostring(err)) end
end

V.onTick('intro', function(dt)
    dt = math.min(dt, 0.1)
    local okC, errC = pcall(csUpdate, dt)
    if not okC then log('car body shake error: '..tostring(errC)); pcall(csStop) end
    local ok, err = pcall(update, dt)
    if not ok then
        log('error: '..tostring(err))
        pcall(resume); pcall(restorePilotMode); st.state, st.w = 'idle', 1
    end
    V.introBlend = (st.state == 'blend') and st.w or 1
    V.introState = st.state
end)
-- never leave the cockpit switched off or the car body moved
V.onReset(function() pcall(resume); pcall(restorePilotMode); pcall(csStop) end)
