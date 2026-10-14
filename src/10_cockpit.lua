-- VR cockpit camera. Based on "Galactic Racer VR cockpit v1.2.0" by madscy & elliotttate
-- (used and shared with their permission): the view sits at the pilot seat socket of the
-- vehicle's authored mesh, seat-local centimetres, pilot models face +Y in the seat frame.
-- Changes for this package: settings come from the shared settings file, the eye position is set
-- per vehicle by the "vehicle" section, other sections hook in after the view is placed.
local log = V.logger('cockpit')
local EYE = { x = 0.0, y = -11.2, z = 77.7 }        -- the original default (seat frame, cm)
V.DEFAULT_EYE = { EYE.x, EYE.y, EYE.z }
local AUTO_RECENTER_ON_FIRST_SEAT = true

if SWGR_COCKPIT_CAMERA then
    -- the separate scripts this package replaces are still in the scripts folder
    V.oldScriptsFound = true
    log('WARNING: the old swgr_cockpit_*.lua scripts are still installed - remove them, they fight with this one')
    if SWGR_COCKPIT_CAMERA.setCameraMode then pcall(SWGR_COCKPIT_CAMERA.setCameraMode, 'game') end
end
-- Prevent a previous chase-camera hook from replacing this cockpit pose.
if SWGR_STABLE_CAMERA then SWGR_STABLE_CAMERA.enabled = false end

local S = { enabled = true, applied = 0, skipped = 0, errors = 0, pawnChanges = 0, seatChanges = 0,
            pilotHides = 0, headHides = 0, pawn = 0, anchor = nil, headCentered = false, poll = 0,
            restore = {}, pilotOverrideActive = false }
V.cam = S
SWGR_VR_CAM = S
S.cameraMode = (V.cfg.cameraMode == 'game') and 'game' or 'cockpit'
S.enabled = S.cameraMode == 'cockpit'
S.pilotVisibility = (V.cfg.pilot == 'hidden' or V.cfg.pilot == 'visible') and V.cfg.pilot or 'head'
S.cameraLock = V.cfg.cameraLock
if S.cameraLock ~= 'track' and S.cameraLock ~= 'hills' and S.cameraLock ~= 'smooth'
    and S.cameraLock ~= 'light' and S.cameraLock ~= 'pilot' then S.cameraLock = 'smooth' end
S.showCinematics = V.cfg.showCinematics
S.showCrashCamera = V.cfg.showCrashCamera

local function finite(v) return type(v) == 'number' and v == v and math.abs(v) < 1e12 end
local rotate = V.rotate

-- The intro flyover uses the engine's CineCameraActor (yield to it); the engine start shot uses
-- FuseCinematicCameraActor (handled by the "intro" section).
local function detectCinematic()
    local pc = api:get_player_controller(0)
    local cm = pc and pc.PlayerCameraManager
    local target = cm and cm.ViewTarget.Target
    local name = target and target:get_class():get_fname():to_string() or ''
    if name ~= S.viewTargetClass then S.viewTargetClass = name; log('view target '..name) end
    return name:find('CineCamera', 1, true) ~= nil
end
local function yielding()
    return (S.showCinematics and S.cinematic) or (S.showCrashCamera and S.crashing)
end
S.yielding = yielding

-- set the eye (seat frame, cm); the vehicle section calls this with the vehicle's own eye
function S.setEye(x, y, z)
    EYE.x, EYE.y, EYE.z = x, y, z
    S.renderEye = nil; S.renderSeat = nil
    local a = S.anchor
    if a and a.seat and a.seatQ then
        local dx, dy, dz = rotate(a.seatQ, EYE.x, EYE.y, EYE.z)
        a.eye = { a.seat[1] + dx, a.seat[2] + dy, a.seat[3] + dz }
    end
end
function S.getEye() return EYE.x, EYE.y, EYE.z end

-- Per real-time seconds so repeated same-frame calls (draw + both eyes) are no-ops;
-- a gap over a second (cinematic, camera yield) snaps instead of lagging behind.
local function smoothedPitch(target)
    local now = os.clock()
    local dt = now - (S.pitchClock or now)
    S.pitchClock = now
    if S.pitch == nil or dt < 0 or dt > 1 then S.pitch = target
    elseif dt > 0 then S.pitch = S.pitch + (target - S.pitch) * (1 - math.exp(-dt / 0.2)) end
    return S.pitch
end
-- Full-orientation smoothing holds a quaternion and nlerps it toward the vehicle's (same
-- real-time no-op / snap rules). Filtering Euler angles separately would wrap badly.
local function smoothedQuat(q, tau)
    local now = os.clock()
    local dt = now - (S.quatClock or now)
    S.quatClock = now
    local held = S.heldQuat
    if held == nil or dt < 0 or dt > 1 then
        S.heldQuat = { q[1], q[2], q[3], q[4] }
        return S.heldQuat
    end
    if dt > 0 then
        local k = 1 - math.exp(-dt / tau)
        local dot = held[1] * q[1] + held[2] * q[2] + held[3] * q[3] + held[4] * q[4]
        local sign = dot < 0 and -1 or 1
        local n = 0
        for i = 1, 4 do held[i] = held[i] + (q[i] * sign - held[i]) * k; n = n + held[i] ^ 2 end
        n = 1 / math.sqrt(n)
        for i = 1, 4 do held[i] = held[i] * n end
    end
    return held
end
local function eulerFrom(q)
    local sinPitch = math.max(-1, math.min(1, 2 * (q[3] * q[1] - q[4] * q[2])))
    return math.deg(math.asin(sinPitch)),
        math.deg(math.atan(2 * (q[4] * q[3] + q[1] * q[2]), 1 - 2 * (q[2] ^ 2 + q[3] ^ 2))),
        math.deg(math.atan(-2 * (q[4] * q[1] + q[2] * q[3]), 1 - 2 * (q[1] ^ 2 + q[2] ^ 2)))
end
local function cameraRotation(q, hq)
    if S.cameraLock == 'smooth' then return eulerFrom(smoothedQuat(q, 0.15)) end
    if S.cameraLock == 'light' then return eulerFrom(smoothedQuat(q, 0.07)) end
    local yaw = math.deg(math.atan(2 * (hq[4] * hq[3] + hq[1] * hq[2]), 1 - 2 * (hq[2] ^ 2 + hq[3] ^ 2)))
    if S.cameraLock == 'track' then return 0, yaw, 0 end
    if S.cameraLock == 'hills' then
        local pitch = math.deg(math.asin(math.max(-1, math.min(1, 2 * (q[3] * q[1] - q[4] * q[2])))))
        return smoothedPitch(math.max(-45, math.min(45, pitch))), yaw, 0
    end
    return eulerFrom(q)
end
local function vec(v) return { v.X, v.Y, v.Z } end
local function quat(v)
    local q = { v.X, v.Y, v.Z, v.W }
    local n = 0
    for _, x in ipairs(q) do if not finite(x) then return nil end; n = n + x * x end
    if n < 0.9 or n > 1.1 then return nil end
    n = 1 / math.sqrt(n)
    for i = 1, 4 do q[i] = q[i] * n end
    return q
end
V.quat = quat
local function validPoint(p)
    return p and finite(p[1]) and finite(p[2]) and finite(p[3])
end
local classes = {}
local function class(name)
    -- (not found yet = looked up again next time: a class may only load with the first race)
    if classes[name] == nil then classes[name] = api:find_uobject('Class /Script/'..name) end
    return classes[name]
end
V.class = class
local function pawnAndVehicle()
    local p = api:get_local_pawn(0)
    local c = class('Griffin.VehiclePawn')
    if p == nil or c == nil or not p:is_a(c) then return nil end
    local v = p.VehicleState
    if v == nil or not v.Valid then return nil end
    return p, v
end
V.pawnAndVehicle = pawnAndVehicle
local function components(p, name)
    local c = class(name)
    return c and p:K2_GetComponentsByClass(c) or {}
end
V.components = components
local function discoverSeat(p)
    local wanted = 'PilotSeat'
    for _, c in ipairs(components(p, 'Griffin.VehicleAnimationComponent')) do
        if c.SeatSocketName then wanted = tostring(c.SeatSocketName) end
    end
    -- Static sockets are authored geometry, independent of driver animation.
    -- Resolve their actor-relative pose once per model, then keep only numbers.
    for _, c in ipairs(components(p, 'Engine.StaticMeshComponent')) do
        local asset = c.StaticMesh
        if asset then
            for _, socket in ipairs(asset.Sockets or {}) do
                if tostring(socket.SocketName) == wanted then
                    local tf = c:GetSocketTransform(socket.SocketName, 1) -- RTS_Actor
                    local q, p0 = quat(tf.Rotation), vec(tf.Translation)
                    if q and validPoint(p0) then
                        local dx, dy, dz = rotate(q, EYE.x, EYE.y, EYE.z)
                        local eye = { p0[1] + dx, p0[2] + dy, p0[3] + dz }
                        if validPoint(eye) and math.abs(eye[1]) < 5000
                            and math.abs(eye[2]) < 5000 and math.abs(eye[3]) < 5000 then
                            return { eye = eye, seat = p0, seatQ = q,
                                model = asset:get_full_name(), socket = wanted }
                        end
                    end
                end
            end
        end
    end
    return nil
end
local function pilotVisibility(p, mode)
    local animClass = class('Griffin.VehicleAnimationComponent')
    if animClass == nil then return end
    for _, mesh in ipairs(components(p, 'Engine.SkeletalMeshComponent')) do
        local owner = mesh:get_outer()
        -- Only meshes created by this local vehicle's animation component.
        if owner and owner:is_a(animClass) then
            local id = mesh:get_address()
            local asset = mesh.SkeletalMesh
            local model = asset and asset:get_full_name() or ''
            local r = S.restore[id]
            if r == nil then r = { hidden = mesh.bHiddenInGame }; S.restore[id] = r end
            if r.model ~= model then
                r.model = model; r.head = nil; r.headChanged = false
                local index = mesh:GetBoneIndex('Head')
                if index and index >= 0 then
                    r.head = tostring(mesh:GetBoneName(index))
                    r.headWasHidden = mesh:IsBoneHiddenByName(r.head)
                end
                local lower = model:lower()
                r.headOnly = lower:find('/heads/', 1, true) ~= nil or lower:find('/helmets/', 1, true) ~= nil
            end
            local hidden = r.hidden or mode == 'hidden' or (mode == 'head' and r.headOnly)
            if mesh.bHiddenInGame ~= hidden then
                mesh:SetHiddenInGame(hidden, false)
                if hidden then S.pilotHides = S.pilotHides + 1 end
            end
            if mode == 'head' and r.head and not r.headOnly then
                if not mesh:IsBoneHiddenByName(r.head) then
                    mesh:HideBoneByName(r.head, 0) -- PBO_None: leave physics bodies intact.
                    r.headChanged = true; S.headHides = S.headHides + 1
                end
            elseif r.head and r.headChanged then
                if not r.headWasHidden then mesh:UnHideBoneByName(r.head) end
                r.headChanged = false
            end
        end
    end
end
local function restorePilot(p)
    if not S.pilotOverrideActive then return end
    pilotVisibility(p, 'visible')
    S.pilotOverrideActive = false; S.restore = {}
end

-- settings changes (from the menu / hotkeys) -------------------------------------------------
function S.setCameraMode(mode)
    if mode ~= 'cockpit' and mode ~= 'game' then return false end
    S.cameraMode = mode; S.enabled = mode == 'cockpit'
    S.renderEye = nil; S.renderSeat = nil
    if S.enabled then S.cycleRequested = 0 end
    V.cfg.cameraMode = mode; V.save()
    log('camera mode '..mode)
    return true
end
function S.cycleGameCamera()
    S.setCameraMode('game')
    -- UI/input callbacks queue the engine call for the game thread.
    S.cycleRequested = math.min((S.cycleRequested or 0) + 1, 8)
end
function S.setPilotMode(mode)
    if mode ~= 'head' and mode ~= 'hidden' and mode ~= 'visible' then return false end
    S.pilotVisibility = mode
    V.cfg.pilot = mode; V.save()
    return true
end
function S.recenter()
    local p, q = Vector3f.new(0, 0, 0), Quaternionf.new(0, 0, 0, 1)
    uevr.params.vr.get_pose(uevr.params.vr.get_hmd_index(), p, q)
    uevr.params.vr.set_standing_origin(p)
    uevr.params.vr.recenter_view()
    S.headCentered = true
end
local function cycleNativeCamera(p)
    for _, c in ipairs(components(p, 'Griffin.VehicleCameraComponent')) do
        c:OnChangeCamera()
        S.nativeStack = c:GetActiveStackName():to_string()
        log('native camera '..S.nativeStack)
        return true
    end
    return false
end

-- Refresh from the visible vehicle's authored socket just before rendering.
-- VehicleState is physics data and can differ from the rendered / interpolated mesh.
function S.draw()
    if V.beforeDraw then pcall(V.beforeDraw) end      -- intro: reads the game camera of this frame
    S.renderEye = nil; S.renderSeat = nil
    if not S.enabled or not S.anchor or yielding() then return end
    local p, v = pawnAndVehicle()
    if not p or p:get_address() ~= S.pawn then return end
    for _, c in ipairs(components(p, 'Engine.StaticMeshComponent')) do
        local asset = c.StaticMesh
        if asset and asset:get_full_name() == S.anchor.model then
            local tf = c:GetSocketTransform(S.anchor.socket, 0) -- RTS_World
            local q, o = quat(tf.Rotation), vec(tf.Translation)
            if q and validPoint(o) then
                local x, y, z = rotate(q, EYE.x, EYE.y, EYE.z)
                S.renderEye = { o[1] + x, o[2] + y, o[3] + z }
                S.renderSeat = { origin = o, quaternion = q }
                break
            end
        end
    end
    local q, hq = quat(v.VehicleTransform.Rotation), quat(v.WorldFrameTransform.Rotation)
    if not S.renderEye or not q or not hq then return end
    -- Set the game camera too: desktop / spectator passes must show the same seat.
    local pc = api:get_player_controller(0)
    local cm = pc and pc.PlayerCameraManager
    if cm then
        for _, pov in ipairs({ cm.CameraCachePrivate.POV, cm.ViewTarget.POV }) do
            local l, r = pov.Location, pov.Rotation
            l.X, l.Y, l.Z = S.renderEye[1], S.renderEye[2], S.renderEye[3]
            r.Pitch, r.Yaw, r.Roll = cameraRotation(q, hq)
        end
    end
end
function S.update(dt)
    local p, v = pawnAndVehicle()
    if not p then
        S.pawn = 0; S.anchor = nil; S.renderEye = nil; S.restore = {}; S.pilotOverrideActive = false
        S.cinematic = false; S.crashing = false; S.cycleRequested = 0
        return
    end
    local id = p:get_address()
    if S.pawn ~= id then
        S.pawn = id; S.anchor = nil; S.renderEye = nil; S.restore = {}; S.pilotOverrideActive = false
        S.poll = 0; S.pawnChanges = S.pawnChanges + 1
    end
    if not S.enabled then
        restorePilot(p)
        if (S.cycleRequested or 0) > 0 then
            if cycleNativeCamera(p) then S.cycleRequested = S.cycleRequested - 1
            else S.cycleRequested = 0 end
        end
        return
    end
    local ok, cinematic = pcall(detectCinematic)
    S.cinematic = ok and cinematic or false
    local okCrash, crashing = pcall(function() return v:IsWrecked() or v:IsTumbling() end)
    crashing = okCrash and crashing or false
    if crashing ~= S.crashing then S.crashing = crashing; log('crashing '..tostring(crashing)) end
    if yielding() then restorePilot(p); return end
    S.poll = S.poll - (dt or 0)
    if S.poll <= 0 or S.anchor == nil then
        S.poll = 1.0
        local a = discoverSeat(p)
        if a and (not S.anchor or S.anchor.model ~= a.model or S.anchor.socket ~= a.socket) then
            S.anchor = a; S.seatChanges = S.seatChanges + 1
            log('seat '..a.model..' '..a.socket)
        end
    end
    if S.anchor then
        S.pilotOverrideActive = true
        pilotVisibility(p, S.pilotVisibility)
        if AUTO_RECENTER_ON_FIRST_SEAT and not S.headCentered then
            S.recenter()
            log('initial headset pose centered at seat')
        end
    end
end
function S.apply(view, scale, position, rotation)
    if not S.enabled or yielding() then return false end
    local p, v = pawnAndVehicle()
    if not p or S.pawn ~= p:get_address() or S.anchor == nil then return false end
    local body, heading = v.VehicleTransform, v.WorldFrameTransform
    local q, hq = quat(body.Rotation), quat(heading.Rotation)
    local origin = vec(body.Translation)
    if not q or not hq or not validPoint(origin) then return false end
    local eye = S.anchor.eye
    local dx, dy, dz = rotate(q, eye[1], eye[2], eye[3])
    local render = S.renderEye
    position.x, position.y, position.z = render and render[1] or origin[1] + dx,
        render and render[2] or origin[2] + dy, render and render[3] or origin[3] + dz
    rotation.x, rotation.y, rotation.z = cameraRotation(q, hq)
    S.applied = S.applied + 1
    V.runHooks(view, position, rotation)
    return true
end
local function guarded(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then S.errors = S.errors + 1; if S.errors <= 5 then log('error '..tostring(result)) end end
    return ok, result
end

callbacks.on_pre_viewport_client_draw(function() guarded(S.draw) end)
callbacks.on_pre_calculate_stereo_view_offset(function(device, view, scale, position, rotation)
    local ok, applied = guarded(S.apply, view, scale, position, rotation)
    if ok and not applied then S.skipped = S.skipped + 1 end
end)
V.onTick('cockpit', function(dt) S.update(dt) end)
V.onReset(function()
    local p = pawnAndVehicle()
    if p then restorePilot(p) end
end)
log('ready; camera '..S.cameraMode..', pilot '..S.pilotVisibility..', lock '..S.cameraLock)
