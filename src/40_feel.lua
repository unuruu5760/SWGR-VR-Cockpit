-- Cockpit feel: designed, event-driven head motion on a damped spring ("head on a spring" in the
-- seat); only pitch is ever rotated (nose lift / nod). Triggers come from the game's VehicleState:
--   afterburner (AfterburnerState -> 0 Active, burned >= 0.12 s, max once per 1 s) -> forward lunge
--   ramjet (RamjetState -> 3 Active = real ignition) -> big lunge, nose lift, warp, hum + heat shudder
--   race start (IgnitionPhase 2 PerfectStart -> 3 PostPerfectStart, and you accelerate) -> launch
--   landing (vertical speed stops falling / LandingState -> 2) -> pressed down, then back
--   impacts, cornering / drift / slipstream push, road rumble, engine idle and while driving
-- Fades out while paused or when the AI drives (race finished).
-- The menu has five amounts in % (100 = recommended); each scales a group of values below.
local log = V.logger('feel')
local S = V.cam
local vr = uevr.params.vr

-- MASTER multiplies most values (kept as tuned, not shown: the menu's % are relative to it)
local MASTER = 3.0
-- the five menu groups and the fine-tuning values in each (recommended value, range)
local function T(key, base, hi, en, tipEn) V.tunable('feel', key, base, 0, hi, en, tipEn); return key end
local GROUPS = {
    engine = {
        T('idle', 0.594, 3, 'Engine idle (standing)', 'How much the cockpit trembles from the engine while you stand still (before the start). 0 = no trembling.'),
        T('idleRev', 1.0, 3, 'Revving with W (standing)', 'The heavy throb when you press W while standing still (revving before the start). 0 = no throb.'),
        T('cruise', 1.041, 3, 'Engine while driving', 'Engine trembling while you drive. 0 = none.'),
    },
    road = {
        T('road', 0.731, 3, 'Road rumble', 'Fine rumble from the ground while driving: grows with speed, stops in the air. Too buzzy at high speed: lower it. 0 = none.'),
        T('bumps', 0.96, 3, 'Ups and downs (terrain)', 'When the track goes up and down, your head lags a little behind and bobs, like in a real vehicle. Feels floaty or sickening: lower it. 0 = the head moves exactly with the vehicle.'),
    },
    motion = {
        T('accel', 0.0, 3, 'Acceleration push', 'Your head is pushed back when you speed up and forward when you slow down. Off by default (0).'),
        T('corner', 0.2, 3, 'Corner push', 'Your head is pushed to the outside in corners. Higher = bigger sway in turns. 0 = none.'),
        T('drift', 3.0, 3, 'Drift rumble', 'The cockpit rattles while you drift (Space). 0 = none.'),
        T('draft', 2.334, 3, 'Slipstream buffeting', 'Right behind another racer (slipstream) the air makes you sway left and right. 0 = none.'),
    },
    boost = {
        T('afterburner', 1.427, 3, 'Afterburner', 'Afterburner (Shift): how hard the view lunges forward when it fires, and the hum / shaking while it burns. 0 = no afterburner effect.'),
        T('abRumble', 1.0, 3, 'Afterburner rumble', 'A heavy shudder while the afterburner burns, clearly above the road rumble (so a boost feels different from just driving fast). It comes in quickly when the burner fires and fades out after. 0 = none.'),
        T('ramjet', 2.466, 3, 'Ramjet', 'Ramjet (C): the big forward lunge and long rumble when it ignites. 0 = no ramjet lunge / rumble.'),
        T('launch', 1.0, 3, 'Race start launch', 'The forward lunge at the moment the race starts, bigger with a perfect start. 0 = no start lunge.'),
        T('nod', 3.0, 3, 'Nose lift', 'On boosts the view tilts up a little (the nose lifts), on landings it nods down. 0 = the view angle never changes (only the position moves).'),
        T('lowHum', 1.013, 3, 'Low hum while boosting', 'A deep, slow hum you feel while the ramjet / afterburner is burning. 0 = none.'),
        T('heatShake', 1.0, 3, 'Overheating shudder', 'Heavy shaking that grows the hotter the ramjet gets (wild at the warning stage). 0 = none.'),
        T('ebrake', 0.0, 3, 'Energy brake', 'Thrown forward when you use the energy brake. Off by default (0).'),
    },
    landing = {
        T('landing', 0.562, 3, 'Landing', 'After a jump the view is pressed down when you land, then comes back up; deeper after longer jumps (never below "Lowest point below normal"). 0 = not pressed down.'),
        T('impact', 1.0, 3, 'Impacts', 'When you hit a wall or another racer the view is knocked the other way. 0 = none.'),
        T('landHit', 3.83, 6, 'Landing hit (thud at touchdown)',
          'The short sharp hit at the moment you touch down, harder after longer jumps. Not limited by the lowest point, so it is always felt.'),
    },
}
V.FEEL_GROUPS = { 'engine', 'road', 'motion', 'boost', 'landing' }
-- values not in a group (fine tuning only)
V.tunable('feel', 'springHz', 3.888, 1, 8, 'Spring speed (Hz)', 'All the shaking moves your head on a "spring". This is how fast that spring is: low = big slow sways, high = short tight jolts. Usually no need to touch it.')
V.tunable('feel', 'landHitHz', 5.5, 4, 20, 'Landing hit sharpness (Hz)', 'The feel of the "Landing hit": higher = a short sharp thud, lower = a softer, longer thump.')
-- Landing head hit (menu: Cockpit shake): a landing hits your head. Moving the view's position reads in
-- VR as the vehicle moving (your real head stays still); turning the view's angle reads as your
-- head moving (like the nose lift). So at touchdown the view angle snaps down and back and wobbles
-- sideways a little, on a stiff spring of its own, on top of the usual press down.
V.tunable('feel', 'headHitPitch', 3.0, 0, 12, 'Head hit: snap down (degrees)',
    'How far your view snaps down at the moment you land, harder after longer jumps and with a higher "Landings and hits". 0 = no snap.')
V.tunable('feel', 'headHitRoll', 1.5, 0, 8, 'Head hit: side wobble (degrees)',
    'How much your view wobbles sideways at the landing (a different side each time). 0 = none.')
V.tunable('feel', 'headHitHz', 7.0, 3, 15, 'Head hit: sharpness (Hz)',
    'Higher = a short sharp knock, lower = a slower, heavier sway.')
V.tunable('feel', 'damping', 0.387, 0.1, 1, 'Spring damping', 'How quickly the spring settles: low = after a move the head bounces a few more times, high = it stops at once. Usually no need to touch it.')
V.tunable('feel', 'fwdScale', 0.5, 0, 1.5, 'Forward lunges (dashboard close)', 'How far boost and start lunges move the view forward, toward the dashboard. You end up in the dashboard (bikes): lower it. 0 = never forward (only the other movements).')
V.tunable('feel', 'landLean', 0.286, 0, 1.5, 'Lean forward on landings', 'While a landing presses the view down it also leans forward by this much. You sink into the pilot body on landings: raise it (the eye dodges forward). 0 = straight down only.')
V.tunable('feel', 'airLift', 5.0, 0, 15, 'Rise in the air (cm)', 'While airborne the view rises by this much, then comes down with the landing, so the landing feels bigger. 0 = stays at the normal height in the air.')
V.tunable('feel', 'lungeMax', 12.5, 5, 60, 'Lunges: farthest forward (cm)',
    'How far forward the view may go on boost and start lunges (and when it leans forward on landings). The lunge goes out to here and stays a moment, so this is how far the boost throws you. Raise it for a bigger lunge; lower it if you end up in the dashboard. 12.5 = as before.')
V.tunable('feel', 'landFloor', 8.29, 0, 15, 'Lowest point below normal (cm)', 'How far below your normal eye height a landing may press the view. You see inside the pilot body or it is too deep: lower it. Landings feel weak: raise it. 0 = never below the normal height.')
V.tunable('boost', 'hitstopStrength', 0.333, 0, 1, 'Hit-stop strength (ramjet / start)', 'At ramjet ignition and the race start the whole game slows down for a split second (when "Hit-stop" is ticked). 1 = down to about a quarter speed. 0 = no slow-down.')
V.tunable('boost', 'hitstopAB', 0.077, 0, 1, 'Hit-stop strength (afterburner)', 'The same split-second slow-down for the afterburner lunge; very light by default. 0 = none.')
V.tunable('boost', 'hitstopTime', 0.164, 0.05, 0.4, 'Hit-stop length (s)', 'How long the slow-down lasts (seconds). Longer = a longer "freeze".')
V.tunable('boost', 'warpAmount', 3.0, -5, 5, 'Warp pulse strength (+ / -)', 'At ramjet ignition and the race start the size of the world pulses for a moment (when "Warp pulse" is ticked). Plus = the world briefly shrinks and moves away, minus = it briefly grows and rushes at you. Further from 0 = stronger. 0 = no pulse.')

-- % of a group for the current vehicle: its own value if it has one, else the shared one. On top, per
-- vehicle type: one overall % for the amounts saved for a vehicle, one for all the others (its default
-- or the shared value), so the defaults can be turned up or down without touching what was set by hand.
-- (Older versions had one pair for every type: it becomes each type's, once.)
if not V.cfg.shakeMasterByType then
    for _, ty in ipairs({ 'Bike', 'Car', 'Skimmer', 'Plane' }) do
        V.cfg['shakeDefault_'..ty] = tonumber(V.cfg.shakeDefault) or 100
        V.cfg['shakeSaved_'..ty] = tonumber(V.cfg.shakeSaved) or 100
    end
    V.cfg.shakeMasterByType = true
    V.save()
end
local function master(kind)
    local ty = V.vtype or V.typeOf(V.model)
    return ty and tonumber(V.cfg[kind..'_'..ty]) or 100
end
function V.feelPct(group)
    local own = V.ownVal('feel', V.model, group)
    if own then return own * master('shakeSaved') / 100 end
    return (V.builtinVal('feel', V.model, group) or V.sharedPct(group)) * master('shakeDefault') / 100
end
-- a ride shake amount (trembling / sways world share, landing slam) through its type's master: the
-- one for values saved for the vehicle, or the one for the others
function V.rideVal(key)
    local own = V.ownVal('detail', V.model, key)
    return (tonumber(own or V.val(key)) or 0) * master(own and 'rideSaved' or 'rideDefault') / 100
end
local cfg = { lungeForward = true }
local function computeCfg()
    for g, keys in pairs(GROUPS) do
        local k = V.feelPct(g) / 100
        for _, key in ipairs(keys) do cfg[key] = V.val(key) * k end
    end
    for _, key in ipairs({ 'springHz', 'damping', 'landLean', 'airLift', 'landFloor', 'hitstopTime', 'landHitHz', 'lungeMax',
        'headHitPitch', 'headHitRoll', 'headHitHz' }) do cfg[key] = V.val(key) end
    local fwd = V.val('fwdScale')
    cfg.fwdBike, cfg.fwdCar, cfg.fwdSkimmer, cfg.fwdPlane = fwd, fwd, fwd, fwd
    cfg.hitstop = V.cfg.hitstop and V.val('hitstopStrength') or 0
    cfg.hitstopAB = V.cfg.hitstop and V.val('hitstopAB') or 0
    cfg.warp = V.cfg.warp and V.val('warpAmount') or 0
end
computeCfg()

-------------------------------------------------------------------------------- tuning
-- Impulses are velocity kicks in cm/s given to the spring; a kick of J cm/s moves the head ~J / 22 cm.
local K = {
    AFTERBURNER_KICK = 70, RAMJET_KICK = 90,
    -- "pressed into the seat": the spring's rest point moves by this much and returns over the decay
    AFTERBURNER_PUSH = 12, AFTERBURNER_PUSH_DECAY = 0.5, RAMJET_PUSH = 18, RAMJET_PUSH_DECAY = 0.7,
    IMPACT_MIN_DV = 600, IMPACT_KICK_MAX = 180,
    ACCEL_LAG = 1.6 / 980, LAG_MAX = 6,              -- cm of head lag per cm/s^2, cap
    ROAD_MAX = 0.35,                                 -- cm noise amplitude at top speed
    IDLE_HUM = 0.18, IDLE_REV = 0.30,                -- cm: engine at idle / extra at full revs
    CRUISE_HUM = 0.10, CRUISE_REV = 0.08,            -- cm: engine while driving / extra on throttle
    REV_RISE = 0.12, REV_FALL = 1.0,                 -- s: revs build up / spin down after W
    BURST_AFTERBURNER = 0.35, BURST_RAMJET = 0.6, BURST_DECAY_AB = 0.35, BURST_DECAY_RJ = 0.8,
    RAMJET_HOLD = 0.05, RAMJET_CRITICAL = 0.35, AFTERBURNER_HOLD = 0.05,
    RJ_HEAVY = 1.0, RJ_HEAVY_CRITICAL = 1.6,         -- cm big slow shudder (heat^1.5 / overheat warning)
    DRAFT_BUFFET = { [1] = 0.35, [2] = 0.6, [3] = 0.25 },   -- by DraftingState (gaining / maintaining / decaying)
    DRIFT_RUMBLE = 0.3, EBRAKE_KICK = 90,
    LAUNCH_KICK = 110, LAUNCH_KICK_PERFECT = 160, LAUNCH_PUSH = 16, LAUNCH_PUSH_PERFECT = 22,
    LAUNCH_WAIT = 0.6,                               -- s after the start: the launch needs the throttle by then
    JOLT_HZ = 9, JOLT_DAMP = 0.35, JOLT_TAP = 120,   -- landing: stiff spring, short tap at contact
    LAND_KICK = 90, LAND_PUSH_MIN = 6, LAND_PUSH_MAX = 14, LAND_PUSH_DECAY = 0.6, LAND_NOD = 14,
    TOUCH_DVZ = 250,                                 -- cm/s upward change in one tick = hit the ground
    NOD_KICK_RJ = 18, NOD_KICK_AB = 8, NOD_HOLD_RJ = 0.8, NOD_HZ = 2.0, NOD_DAMP = 0.55, NOD_AB_PEAK = 1.2,
    WARP_AMOUNT = 0.12, WARP_RISE = 0.06, WARP_FALL = 0.45, WARP_LEN = 2.0,
    RJ_LOW = 0.5, RJ_LOW_HZ = 2.6, AB_LOW = 0.8, AB_HEAVY = 0.6,
    AB_RUMBLE = 0.45, AB_RUMBLE_HZ = 8, AB_RUMBLE_IN = 0.12, AB_RUMBLE_OUT = 0.4,   -- cm, Hz, s: afterburner rumble
    AB_MIN_HOLD = 0.12, AB_REPEAT = 1.0, AB_FRESH = 4.0, AB_LUNGE_RISE = 0.2, AB_LUNGE_FALL = 0.6,
    LIFT_RISE = 0.35, LIFT_DROP = 0.08, HS_RAMP = 0.12,
    FOLLOW_BONE = 'spine_05', FOLLOW_AFTER = 1.0,
}
-- game enums (from the state log, 2026-10-13)
local AB_ACTIVE, RJ_ACTIVE, RJ_CRITICAL, RJ_GRACE = 0, 3, 4, 5
local EB_ACTIVE, IGN_PERFECT, IGN_POST, INPUT_AI = 3, 2, 3, 2
local TAU = 2 * math.pi
local clamp, clamp01, rotate, unrotate, noise = V.clamp, V.clamp01, V.rotate, V.unrotate, V.noise

-------------------------------------------------------------------------------- state
local st = {
    posOff = { 0, 0, 0 }, sp = { 0, 0, 0 }, sv = { 0, 0, 0 }, accLP = { 0, 0, 0 }, prevVel = nil,
    prevAB = -1, prevRJ = -1, prevEB = -1, prevIgn = -1, burst = 0, burstDecay = K.BURST_DECAY_AB,
    revSmooth = 0, phase = 0, phase2 = 0, lowPhase = 0, push = 0, pushDecay = K.AFTERBURNER_PUSH_DECAY,
    pushZ = 0, pushZDecay = K.LAND_PUSH_DECAY, jp = 0, jv = 0, lastVz = nil, lastLandT = -10,
    prevLS = 0, airPeak = 0, liftZ = 0, jumpQuiet = 0, rp = 0, rv = 0, rotPitch = 0,
    hp = 0, hpv = 0, hr = 0, hrv = 0, rotHeadP = 0, rotHeadR = 0,   -- head hit (pitch / roll spring)
    abArmed = false, lastABLunge = -10, abL = 0, abLunging = false, abLHold = 0, abLastEnd = -100, abWasBurning = false,
    gate = 1, gateWhy = '', prevPos = nil, frozenTicks = 0, clockStill = 0, lastGameT = nil,
    -- body follow on jumps
    pilotMesh = nil, nextMeshFind = 0, headBase = nil, follow = { 0, 0, 0 }, followW = 0, followUntil = nil,
}
V.feelDown, V.feelFwd, V.air = 0, 0, 0
V.feelInfo = { mph = 0, last = '-' }

-- warp: VR_WorldScale pulse on ramjet ignition / launch
local warp = { active = false, base = 1, t0 = 0 }
local function setWorldScale(x) pcall(function() vr.set_mod_value('VR_WorldScale', string.format('%.4f', x)) end) end
local function warpStop() if warp.active then setWorldScale(warp.base); warp.active = false end end
local function warpStart()
    if cfg.warp == 0 then return end
    if not warp.active then
        local ok, b = pcall(function() return vr:get_mod_value('VR_WorldScale') end)
        warp.base = (ok and tonumber(b) and tonumber(b) > 0) and tonumber(b) or 1
        warp.active = true
    end
    warp.t0 = V.t
end

-- hit-stop: the game runs slow for a moment (SetGlobalTimeDilation), then snaps back. Real-time,
-- always restores the dilation it found.
local hs = { active = false, t = 0, slow = 1, base = 1, last = nil }
local function gsCall(fn)
    local gs = api:find_uobject('Class /Script/Engine.GameplayStatics')
    local ctx = api:get_player_controller(0)
    if not gs or not ctx then return nil end
    return fn(gs:get_class_default_object(), ctx)
end
local function setDilation(x)
    if hs.last and math.abs(hs.last - x) < 0.005 then return end
    hs.last = x
    local ok, err = pcall(gsCall, function(cdo, ctx) cdo:SetGlobalTimeDilation(ctx, x) end)
    if not ok then log('time dilation failed: '..tostring(err)); hs.active = false end
end
local function hitstopEnd()
    -- (hs.last cleared first: the ramp's last step can be within setDilation's 0.005 skip window)
    if hs.active then hs.active = false; hs.last = nil; setDilation(hs.base); hs.last = nil end
end
local function hitstop(strength)
    if strength <= 0 or cfg.hitstopTime <= 0 then return end
    if not hs.active then
        local ok, cur = pcall(gsCall, function(cdo, ctx) return cdo:GetGlobalTimeDilation(ctx) end)
        hs.base = (ok and tonumber(cur) and tonumber(cur) > 0) and tonumber(cur) or 1
    end
    hs.active, hs.t, hs.last = true, 0, nil
    hs.slow = hs.base * math.max(0.1, 1 - 0.75 * math.min(1, strength))
end
local function hitstopTick(dt)
    if not hs.active then return end
    hs.t = hs.t + dt
    local d = cfg.hitstopTime
    if hs.t < d then setDilation(hs.slow)
    elseif hs.t < d + K.HS_RAMP then setDilation(hs.slow + (hs.base - hs.slow) * ((hs.t - d) / K.HS_RAMP))
    else hitstopEnd() end
end

-------------------------------------------------------------------------------- shake along with the vehicle (test)
-- The shake moves only your view, inside a vehicle that stays still: in VR that looks as if the
-- vehicle trembles around you (the cockpit is close, so it seems to move; the world far away hardly
-- does). Measured in the game (2026-10-16): the body, the pilot and the seat move exactly with the
-- vehicle, nothing of it trembles by itself. With "Shake along with the vehicle" the trembling (engine,
-- road, boost hum, heat shudder, slipstream, the landing hit) moves the vehicle body too, by the
-- same amount: the part that carries the seat and the body (in this game CustomisationRoot is the
-- vehicle's root, the physics body: the child of it the seat hangs under is moved). The view follows the
-- seat, so the cockpit stays put in front of you and the world outside shakes: you and the vehicle
-- shake together. The slower movements (corner push, bobbing on the road and over hills, the landing
-- press) go to the body too (their own amount); the boost lunges stay in the view. Landings: the body (with you) slams down, dips its nose, rolls a little to one side,
-- bounces back on its springs and shudders for a moment (its own amount, up to 500 %). The body's
-- trembling stops while airborne. A cm of trembling is hardly seen against the world far away, so the body also
-- tilts with it (alongTilt degrees per cm: up / down -> pitch, sideways -> roll) and the view turns
-- by the same angles: the world visibly shakes, the cockpit stays put. The lunges, sways and the
-- landing press stay in the view (your body moving in the seat). The body is moved right before the
-- frame is drawn and the seat is read (after the game's own tick, so nothing overwrites it and the
-- view and the body move in the same frame).
V.tunable('feel', 'alongTilt', 0.5, 0, 2, 'Ride shake: tilt',
    'With "Ride shake": how much the world also tilts with the trembling it gets. 0 = no tilting.')
-- the ride shake amounts (%): values per vehicle like the fine tuning (changed while driving a
-- vehicle = saved for it); shared values until the per-type defaults are set
V.tunable('feel', 'shakeAlong', 100, 0, 100, 'Ride shake: trembling (world share)',
    'Share of the engine, road, afterburner and ramjet trembling that shakes the world (you move with the vehicle) instead of the cockpit. 0 = only the cockpit trembles, 100 = only the world.').main = true
V.tunable('feel', 'shakeAlongSmooth', 0, 0, 300, 'Ride shake: smooth (driving)',
    'Softens the trembling and the sways while you just drive. The afterburner, the ramjet and landings stay sharp. 0 = off, 300 = most.').main = true
V.tunable('feel', 'shakeAlongSmooth2', 0, 0, 300, 'Ride shake: smooth (boosts and hits)',
    'Softens the afterburner and ramjet rumble, the push in corners and the landing slam. 0 = off, 300 = most.').main = true
V.tunable('feel', 'shakeAlongAir', 50, 0, 100, 'Ride shake: trembling in the air',
    'How much of the world\'s trembling stays while you are in the air. 0 = a calm flight, 100 = the same as on the ground.').main = true
V.tunable('feel', 'shakeAlongMove', 100, 0, 100, 'Ride shake: sways (world share)',
    'Share of the bobbing on the road and over hills, the push in corners and the landing press that goes to the world instead of the cockpit. 0 = only the cockpit, 100 = only the world. Afterburner and ramjet lunges always stay with the cockpit.').main = true
V.tunable('feel', 'shakeAlongLand', 100, 0, 300, 'Ride shake: landing slam',
    'How hard you slam down with the vehicle when you land: bigger after higher drops, longer flights and at speed. 0 = off, 100 = default.').main = true
-- (older versions kept them in the settings for every vehicle: those become the shared values, once)
if not V.cfg.shakeAlongPerVehicle then
    for _, key in ipairs({ 'shakeAlong', 'shakeAlongSmooth', 'shakeAlongSmooth2', 'shakeAlongAir', 'shakeAlongMove' }) do
        local old, item = tonumber(V.cfg[key]), V.TUNE_INDEX[key]
        if old and item and math.abs(old - item.base) > 0.001 then V.cfg.detail[key] = old end
    end
    V.cfg.shakeAlongPerVehicle = true
    V.save()
end
-- (the landing slam amount changed meaning on 2026-10-17: 100 = the new design, the old one needed
-- 500 to be felt at all. Values saved with the old meaning are dropped, once.)
if not V.cfg.landSlamV2 then
    V.cfg.detail.shakeAlongLand = nil
    for m in pairs(V.veh.detail) do V.clearOwnVal('detail', m, 'shakeAlongLand') end
    V.cfg.landSlamV2 = true
    V.save(); V.saveVeh()
end
local car = { pawn = nil, comp = nil, parent = nil, base = nil, last = nil, failed = nil, moved = false, hit = nil, loc = nil, rot = nil, free = false }
local POD_MOVE, POD_TILT = 6, 4            -- podracer pod mesh: at most this far (cm) / this much tilt (degrees)
local carT = { 0, 0, 0 }                   -- the part of the shake the vehicle body takes (vehicle axes, cm)
-- landing slam of the body: down (cm), nose (deg), roll (deg) on springs that overshoot (a bounce), and
-- a short hard shudder right after the touchdown. How hard: the falling speed the ground stops,
-- f = cm/s / REF (up to MAX_F) - a high drop slams, a small hop or a landing along a slope barely -, the
-- time in the air (a short flight over a small ledge only AIR_MIN of it, full from AIR_T1 s: the game
-- lets even small ledges fall fast) and a little the driving speed. The drop grows faster than f
-- (f ^ DROP_EXP), and the shape follows the size: small = a quick light tap (stiff spring, short
-- shudder), big = deeper and slower (soft spring), a bigger bounce and a longer shudder. Logged falls
-- (2026-10-17, Beluga): 470 .. 2800 cm/s, most 900 .. 1400, even after half a second in the air.
local slam = { z = 0, zv = 0, p = 0, pv = 0, r = 0, rv = 0, zr = 0, pr = 0, rr = 0, shud = 0, ph = 0, hz = 3, shudT = 0.2 }
-- boosting: the vehicle (with you) rumbles all the time the ramjet / afterburner burns (cm, at full
-- "Trembling"; the afterburner 70 %)
local SA_BOOST, SA_BOOST_HZ = 1.2, 10
local SLAM = {
    REF = 1000, MAX_F = 3.5, WIN = 0.2, PEAK_T = 0.6,   -- falling speed (cm/s) of strength 1; touchdown window (s); fall look-back (s)
    DROP = 20, DROP_EXP = 1.3,                          -- cm down at strength 1 (100 %), growing as strength ^ DROP_EXP
    DROP_KNEE = 15, DROP_MAX = 42,                      -- as is up to KNEE cm, then easing off toward MAX (at 100 %)
    NOSE = 0.3, ROLL = 0.14,                            -- degrees of nose dip / roll per cm down
    SPEED = 0.4,                                        -- the driving speed: x (0.8 .. 1.2) from standing to top speed
    AIR_MIN = 0.15, AIR_T0 = 0.5, AIR_T1 = 2.0,         -- time in the air: x AIR_MIN up to AIR_T0 s, x 1 from AIR_T1 s (rising slowly first)
    SIZE_SMALL = 8, SIZE_BIG = 35,                      -- cm down (at 100 %) of a small / big landing, for its shape
    HZ_SMALL = 3.4, HZ_BIG = 2.0, PHZ = 1.23, DAMP = 0.28,   -- the springs: small / big landing (Hz), nose and roll x PHZ
    SHUD = 0.9, SHUD_P = 0.5, SHUD_HZ = 24,             -- shudder: cm and degrees per unit, its speed
    SHUD_PER = 0.1, SHUD_MAX = 6, SHUD_T_SMALL = 0.15, SHUD_T_BIG = 0.4,   -- units per cm down (eases off to MAX), how long
    Z_KNEE = 40, Z_MAX = 70, P_KNEE = 10, P_MAX = 18, R_KNEE = 5, R_MAX = 8,   -- as is up to KNEE, then easing off to MAX
    NOSE_KNEE = 12, NOSE_MAX = 20 }                     -- the body's whole nose (with the driving tilt)
-- (a spring of this damping kicked with speed v0 goes down v0 / w * SLAM_PEAK at most)
local SLAM_PEAK = (function(d) local q = math.sqrt(1 - d * d); return math.exp(-d / q * math.atan(q / d)) end)(SLAM.DAMP)
local function softLim(x, lim) local q = x / lim; return x / math.sqrt(1 + q * q) end
-- as it is up to knee, beyond that easing off toward max
local function kneeLim(x, knee, max)
    local a = math.abs(x)
    if a <= knee then return x end
    local r = knee + softLim(a - knee, max - knee)
    return x < 0 and -r or r
end
-- the body's nose: as it is up to NOSE_KNEE degrees (all the driving), beyond that easing off toward
-- NOSE_MAX (big landings), so a high drop still dips more than a medium one
local function noseLim(x) return kneeLim(x, SLAM.NOSE_KNEE, SLAM.NOSE_MAX) end
-- the springs and the shudder for a landing of d cm (at 100 %): stiff and short when small, soft and long when big
local function slamSize(d)
    local b = clamp01((d - SLAM.SIZE_SMALL) / (SLAM.SIZE_BIG - SLAM.SIZE_SMALL))
    slam.hz = SLAM.HZ_SMALL + (SLAM.HZ_BIG - SLAM.HZ_SMALL) * b
    slam.shudT = SLAM.SHUD_T_SMALL + (SLAM.SHUD_T_BIG - SLAM.SHUD_T_SMALL) * b
end
-- kicks the springs so the body goes about dDrop cm further down (nose and roll with it)
local function slamKick(dDrop, sign)
    local w, wp = TAU * slam.hz, TAU * slam.hz * SLAM.PHZ
    slam.zv = slam.zv - dDrop * w / SLAM_PEAK
    slam.pv = slam.pv - dDrop * SLAM.NOSE * wp / SLAM_PEAK
    slam.rv = slam.rv + sign * dDrop * SLAM.ROLL * wp / SLAM_PEAK
end
-- the downward speed (cm/s) of the last frames, to know how fast the vehicle fell before it landed
local FALL_N = 160
local fallT, fallV, fallI = {}, {}, 0
local function fallPush(t, v) fallI = fallI % FALL_N + 1; fallT[fallI], fallV[fallI] = t, v end
local function fallPeak(t, span)
    local m = 0
    for i = 1, FALL_N do
        local ti = fallT[i]
        if ti and t - ti <= span and fallV[i] > m then m = fallV[i] end
    end
    return m
end
local function slamStep(dt)
    local steps = math.max(1, math.ceil(dt / 0.004))
    local h = dt / steps
    local w, wp = TAU * slam.hz, TAU * slam.hz * SLAM.PHZ
    for _ = 1, steps do
        slam.zv = slam.zv + (-w * w * slam.zr - 2 * SLAM.DAMP * w * slam.zv) * h; slam.zr = slam.zr + slam.zv * h
        slam.pv = slam.pv + (-wp * wp * slam.pr - 2 * SLAM.DAMP * wp * slam.pv) * h; slam.pr = slam.pr + slam.pv * h
        slam.rv = slam.rv + (-wp * wp * slam.rr - 2 * SLAM.DAMP * wp * slam.rv) * h; slam.rr = slam.rr + slam.rv * h
    end
    slam.z = kneeLim(slam.zr, SLAM.Z_KNEE, SLAM.Z_MAX)
    slam.p = kneeLim(slam.pr, SLAM.P_KNEE, SLAM.P_MAX)
    slam.r = kneeLim(slam.rr, SLAM.R_KNEE, SLAM.R_MAX)
    slam.shud = slam.shud * math.exp(-dt / slam.shudT)
    slam.ph = slam.ph + dt * SLAM.SHUD_HZ
end
local function slamReset()
    slam.z, slam.zv, slam.p, slam.pv, slam.r, slam.rv, slam.shud = 0, 0, 0, 0, 0, 0, 0
    slam.zr, slam.pr, slam.rr = 0, 0, 0
    st.slamWin = nil
end
local carTilt = { 0, 0 }                   -- and its tilt (pitch, roll degrees), the view turns the same
-- the part to move: up from the seat mesh, the last parent before the vehicle's root (the root is the
-- physics body); CustomisationRoot itself if it is not the root
local function carFind(p)
    local seat = nil
    for _, c in ipairs(V.components(p, 'Engine.StaticMeshComponent')) do
        local a = c.StaticMesh
        if a and S.anchor and a:get_full_name() == S.anchor.model then seat = c; break end
    end
    if not seat then return nil, 'no seat mesh' end
    local root = p.RootComponent
    local rootId = root and root:get_address()
    local chain, c, below = { seat:get_fname():to_string() }, seat, nil
    for _ = 1, 16 do
        local up = c:GetAttachParent()
        if not up then break end
        local n = up:get_fname():to_string()
        chain[#chain + 1] = n
        if up:get_address() == rootId then
            if c == seat then return nil, 'the seat mesh hangs right under the root ('..table.concat(chain, ' < ')..')' end
            local okP, sim = pcall(function() return c:IsSimulatingPhysics() end)
            if okP and sim then return nil, 'the part under the root simulates physics' end
            return c, c:get_fname():to_string()..' ('..table.concat(chain, ' < ')..')'
        end
        if n == 'CustomisationRoot' then return up, n..' ('..table.concat(chain, ' < ')..')' end
        below, c = c, up
    end
    -- No root above: the topmost part hangs on nothing - a podracer's pod container on its cables. The
    -- game works the pod's next place out from where the container is: moving the container added up,
    -- pod and engines flew apart and the game wrecked the vehicle (tried 2026-10-16). So the container
    -- stays as it is and the part right under it (the pod's own mesh, carrying the seat) is moved
    -- against it instead - by a little only (car.free: limited, see carMove).
    if not below or below == seat then return nil, 'the seat mesh hangs right under the free pod container ('..table.concat(chain, ' < ')..')' end
    local okP, sim = pcall(function() return below:IsSimulatingPhysics() end)
    if okP and sim then return nil, 'the pod mesh simulates physics' end
    return below, below:get_fname():to_string()..' in the free pod container ('..table.concat(chain, ' < ')..')', true
end
local function carSet(x, y, z, pitch, yaw, roll)
    car.loc = car.loc or StructObject.new(api:find_uobject('ScriptStruct /Script/CoreUObject.Vector'))
    car.rot = car.rot or StructObject.new(api:find_uobject('ScriptStruct /Script/CoreUObject.Rotator'))
    car.hit = car.hit or StructObject.new(api:find_uobject('ScriptStruct /Script/Engine.HitResult'))
    car.loc.X, car.loc.Y, car.loc.Z = x, y, z
    car.rot.Pitch, car.rot.Yaw, car.rot.Roll = pitch, yaw, roll
    -- (no sweep, teleport: no physics from this)
    car.comp:K2_SetRelativeLocationAndRotation(car.loc, car.rot, false, car.hit, true)
    car.last = { x, y, z, pitch, yaw, roll }
end
local function carStop()
    car.want = false
    local b = car.base
    -- (a free-standing part is placed by the game every frame: nothing to put back)
    if car.moved and car.comp and b and car.parent then pcall(carSet, b[1], b[2], b[3], b[4], b[5], b[6]) end
    car.moved, car.base = false, nil
    carT[1], carT[2], carT[3], carTilt[1], carTilt[2] = 0, 0, 0, 0, 0
    slamReset()
end
local function wrap180(a) return (a + 180) % 360 - 180 end
-- quaternions { x, y, z, w }: product, inverse (unit), and the engine's rotator <-> quaternion
local function qmul(a, b)
    return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2], a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
             a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4], a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end
local function qinv(a) return { -a[1], -a[2], -a[3], a[4] } end
local function rotQ(pitch, yaw, roll)
    local h = math.pi / 360
    local sp, cp, sy, cy, sr, cr = math.sin(pitch * h), math.cos(pitch * h), math.sin(yaw * h), math.cos(yaw * h), math.sin(roll * h), math.cos(roll * h)
    return { cr * sp * sy - sr * cp * cy, -cr * sp * cy - sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy }
end
local function qRot(q)
    local x, y, z, w = q[1], q[2], q[3], q[4]
    return math.deg(math.asin(math.max(-1, math.min(1, 2 * (z * x - w * y))))),
        math.deg(math.atan(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))),
        math.deg(math.atan(-2 * (w * x + y * z), 1 - 2 * (x * x + y * y)))
end
-- how much of the trembling (0..1) and of the landing hit (0..3) the vehicle body takes now; finds
-- the body once per vehicle
local function carAmount(p)
    local k = math.max(0, math.min(1, (V.rideVal('shakeAlong') or 0) / 100))
    local kl = math.max(0, math.min(3, (V.rideVal('shakeAlongLand') or 0) / 100))
    local km = math.max(0, math.min(1, (V.rideVal('shakeAlongMove') or 0) / 100))
    local id = p and p:get_address()
    if id ~= car.pawn then carStop(); car.pawn, car.comp, car.parent, car.failed = id, nil, nil, nil end
    if not V.cfg.shakeAlongOn or (k <= 0 and kl <= 0 and km <= 0) or not p or car.failed or S.yielding() then return 0, 0, 0 end
    if not car.comp then
        local ok, c, why, free = pcall(carFind, p)
        if not ok or not c then
            car.failed = ok and why or tostring(c)
            log('shake along with the vehicle not possible: '..car.failed)
            return 0, 0, 0
        end
        car.comp, car.parent, car.free = c, c:GetAttachParent(), free == true
        log('shake along with the vehicle: moves '..why)
    end
    return k, kl, km
end
-- put this tick's part on the body (its parent's axes: the offset is turned from the vehicle's; the
-- tilt is turned on top of the resting rotation, in the parent's axes)
local function carMove(q)
    if not car.comp then return end
    local l, r, last = car.comp.RelativeLocation, car.comp.RelativeRotation, car.last
    -- the resting place: taken when it starts; if the game moved the body itself, its new place
    local movedByGame = last and (math.abs(l.X - last[1]) + math.abs(l.Y - last[2]) + math.abs(l.Z - last[3]) > 0.05
        or math.abs(wrap180(r.Pitch - last[4])) + math.abs(wrap180(r.Yaw - last[5])) + math.abs(wrap180(r.Roll - last[6])) > 0.05)
    if not car.base or movedByGame then car.base = { l.X, l.Y, l.Z, r.Pitch, r.Yaw, r.Roll } end
    local b = car.base
    -- (the pod: a little only - its mesh may be what the game checks collisions with)
    local lim, limT = car.free and POD_MOVE or 1e9, car.free and POD_TILT or 1e9
    local wx, wy, wz = rotate(q, clamp(carT[1], lim), clamp(carT[2], lim), clamp(carT[3], lim))
    local pq = car.parent and V.quat(car.parent:K2_GetComponentToWorld().Rotation)
    local rx, ry, rz = wx, wy, wz
    if pq then rx, ry, rz = unrotate(pq, wx, wy, wz) end
    local pitch, yaw, roll = b[4], b[5], b[6]
    if carTilt[1] ~= 0 or carTilt[2] ~= 0 then
        -- the tilt turns about the vehicle's own axes (pitch: its right, roll: its forward), put on top of
        -- the resting rotation and written in the parent's axes: rel' = P^-1 * (Q * T * Q^-1) * P * rel
        local P = pq or { 0, 0, 0, 1 }
        local turnW = qmul(qmul(q, rotQ(clamp(carTilt[1], limT), 0, clamp(carTilt[2], limT))), qinv(q))
        pitch, yaw, roll = qRot(qmul(qmul(qmul(qinv(P), turnW), P), rotQ(b[4], b[5], b[6])))
    end
    carSet(b[1] + rx, b[2] + ry, b[3] + rz, pitch, yaw, roll)
    car.moved = true
end
V.shakeAlongInfo = car                     -- (menu: why it is not possible)
V.beforeSeat = function()
    if not car.want then return end
    local ok, err = pcall(carMove, car.q)
    if not ok then car.failed, car.want = tostring(err), false; log('shake along with the vehicle turned off: '..car.failed); carStop() end
end

local function reset()
    pcall(carStop)
    hitstopEnd()
    st.abL, st.abLunging = 0, false
    for i = 1, 3 do st.sp[i], st.sv[i], st.accLP[i] = 0, 0, 0 end
    st.prevVel, st.burst, st.push = nil, 0, 0
    st.jp, st.jv, st.lastVz, st.pushZ = 0, 0, nil, 0
    st.rp, st.rv, st.rotPitch = 0, 0, 0
    st.hp, st.hpv, st.hr, st.hrv, st.rotHeadP, st.rotHeadR = 0, 0, 0, 0, 0, 0
    st.abEnv, st.launchUntil, st.saEnv = 0, nil, 0
    st.liftT, st.air0T = nil, nil
    warpStop()
end
local function event(name)
    V.feelInfo.last = name
    log(string.format('%s at %.0f mph', name, V.feelInfo.mph or 0))
end
local function kick(x, y, z) st.sv[1], st.sv[2], st.sv[3] = st.sv[1] + x, st.sv[2] + y, st.sv[3] + z end

-------------------------------------------------------------------------------- body follow
-- On jumps (bikes) the rider animation stands up into the fixed eye. A visible chest bone is
-- measured in the rendered seat frame against its resting place (learned on the ground) and, only
-- while airborne (+1 s), the eye moves with it.
local function findPilotMesh(p)
    local animCls = V.class('Griffin.VehicleAnimationComponent')
    for _, m in ipairs(V.components(p, 'Engine.SkeletalMeshComponent')) do
        local owner = m:get_outer()
        if owner and (not animCls or owner:is_a(animCls)) then
            local ok, idx = pcall(function() return m:GetBoneIndex('Head') end)
            if ok and idx and idx >= 0 then return m end
        end
    end
    return nil
end
local function pilotFollow(p, q, dt, grounded, airborne)
    local f = st.follow
    local fc = V.followFor()
    local kUp, kFwd, kSide, kMax = fc[1] or 0, fc[2] or 0, fc[3] or 0, fc[4] or 30
    if not V.cfg.bodyFollow or (kUp <= 0 and kFwd == 0 and kSide == 0) then f[1], f[2], f[3] = 0, 0, 0; return end
    if not st.pilotMesh or V.t > st.nextMeshFind then
        st.nextMeshFind = V.t + 1.0                      -- re-find every second (vehicle swaps)
        local ok, m = pcall(findPilotMesh, p)
        if ok and m ~= st.pilotMesh then st.pilotMesh = m; st.headBase = nil end
    end
    local seat = S.renderSeat
    if not st.pilotMesh or not seat then return end
    local ok, hx, hy, hz = pcall(function()
        local h = st.pilotMesh:GetSocketLocation(K.FOLLOW_BONE)
        local o, sq = seat.origin, seat.quaternion
        local sx, sy, sz = unrotate(sq, h.X - o[1], h.Y - o[2], h.Z - o[3])   -- seat local
        local wx, wy, wz = rotate(sq, sx, sy, sz)                                -- back to world axes
        return unrotate(q, wx, wy, wz)                                           -- vehicle local axes
    end)
    if not ok then st.pilotMesh = nil; return end
    if not st.headBase then st.headBase = { hx, hy, hz } end
    local b = st.headBase
    if airborne then st.followUntil = V.t + K.FOLLOW_AFTER end
    local inAir = st.followUntil ~= nil and V.t < st.followUntil
    st.followW = st.followW + ((inAir and 1 or 0) - st.followW) * (1 - math.exp(-dt / (inAir and 0.05 or 0.15)))
    if grounded and not inAir then                      -- learn the resting body position on the ground
        local a = 1 - math.exp(-dt / 1.0)
        b[1] = b[1] + (hx - b[1]) * a; b[2] = b[2] + (hy - b[2]) * a; b[3] = b[3] + (hz - b[3]) * a
    end
    local w = st.followW
    local tx = clamp((hx - b[1]) * kFwd, kMax) * w
    local ty = clamp((hy - b[2]) * kSide, kMax) * w
    local tz = clamp((hz - b[3]) * kUp, kMax) * w
    local a = 1 - math.exp(-dt / 0.05)                  -- light smoothing against bone jitter
    f[1] = f[1] + (tx - f[1]) * a; f[2] = f[2] + (ty - f[2]) * a; f[3] = f[3] + (tz - f[3]) * a
end

-------------------------------------------------------------------------------- update
local function paused(p, v, body, dt)
    local why = ''
    local okP, isPaused = pcall(function() return api:get_player_controller(0):IsPaused() end)
    if okP and isPaused then why = 'paused' end
    -- a moving car that doesn't move = game frozen (pause menu)
    local tr = body.Translation
    if st.prevPos and tr.X == st.prevPos[1] and tr.Y == st.prevPos[2] and tr.Z == st.prevPos[3]
        and (tonumber(v.SpeedMPH) or 0) > 1 then st.frozenTicks = st.frozenTicks + 1 else st.frozenTicks = 0 end
    st.prevPos = { tr.X, tr.Y, tr.Z }
    if st.frozenTicks >= 3 then why = 'paused' end
    -- standing still: the game clock stops while paused
    local okT, gameT = pcall(function() return gsCall(function(cdo, ctx) return cdo:GetTimeSeconds(ctx) end) end)
    gameT = okT and tonumber(gameT) or nil
    if gameT then
        if st.lastGameT and gameT == st.lastGameT then st.clockStill = st.clockStill + 1 else st.clockStill = 0 end
        st.lastGameT = gameT
        if st.clockStill >= 3 then why = 'paused' end
    end
    local okS, src = pcall(function() return tonumber(p.InputSource) end)
    if okS and src == INPUT_AI then why = 'AI driving' end
    if why ~= st.gateWhy then log('effects '..(why == '' and 'on' or ('off: '..why))); st.gateWhy = why end
    st.gate = st.gate + ((why == '' and 1 or 0) - st.gate) * (1 - math.exp(-dt / 0.15))
end

local function update(dt)
    local po = st.posOff
    po[1], po[2], po[3] = 0, 0, 0
    st.rotPitch = 0
    V.feelDown, V.feelFwd = 0, 0
    computeCfg()
    if not V.cfg.extras or not V.cfg.feelOn or not S.enabled or not S.anchor then reset(); return end
    local p, v = V.pawnAndVehicle()
    if not p then reset(); return end
    if dt <= 0 then return end
    dt = math.min(dt, 0.05)
    local body = v.VehicleTransform
    local vtype = V.vtype or 'Other'
    paused(p, v, body, dt)
    local r = body.Rotation
    local q = { r.X, r.Y, r.Z, r.W }
    local mph, top = tonumber(v.SpeedMPH) or 0, tonumber(v.TopSpeedMph) or 0
    local spd = top > 1 and clamp01(mph / top) or 0
    local air = tonumber(v.TimeInAir) or 0
    local ground = clamp01(v.OnGroundScale)
    local rpm, thr = clamp01(v.RPMScale), clamp01(v.Throttle)
    local ign = tonumber(v.IgnitionStatus) or -1
    V.feelInfo.mph = mph
    local M = MASTER
    local sp, sv, accLP = st.sp, st.sv, st.accLP

    -- velocity change -> acceleration (vehicle local) and impacts
    local vel = v.Velocity
    local vx, vy, vz = vel.X, vel.Y, vel.Z
    if st.prevVel then
        local pv = st.prevVel
        local dx, dy, dz = vx - pv[1], vy - pv[2], vz - pv[3]
        local dv = math.sqrt(dx * dx + dy * dy + dz * dz)
        local lx, ly, lz = unrotate(q, dx / dt, dy / dt, dz / dt)
        if dv > K.IMPACT_MIN_DV and dv < 20000 then         -- hit (huge = respawn teleport, ignore)
            local ix, iy, iz = unrotate(q, dx, dy, dz)
            local k = math.min(K.IMPACT_KICK_MAX, (dv - K.IMPACT_MIN_DV) * 0.15 + 40) * cfg.impact * M / dv
            kick(-ix * k, -iy * k, -iz * k)
            event(string.format('impact %.0f', dv))
            lx, ly, lz = 0, 0, 0                            -- don't feed the spike into the lag
        end
        local a = 1 - math.exp(-dt / 0.08)
        accLP[1] = accLP[1] + (lx - accLP[1]) * a
        accLP[2] = accLP[2] + (ly - accLP[2]) * a
        accLP[3] = accLP[3] + (lz - accLP[3]) * a
    end
    st.prevVel = { vx, vy, vz }

    -- boost events
    local dir = cfg.lungeForward and 1 or -1           -- +X = forward
    local ab = tonumber(v.AfterburnerState) or -1
    local rj = tonumber(v.RamjetState) or -1
    local heat = clamp01(v.RamjetHeat)
    if rj == RJ_ACTIVE and st.prevRJ ~= -1 and st.prevRJ < RJ_ACTIVE then
        kick(K.RAMJET_KICK * cfg.ramjet * M * dir, 0, 0)
        st.push, st.pushDecay = math.max(st.push, K.RAMJET_PUSH * cfg.ramjet), K.RAMJET_PUSH_DECAY
        st.burst, st.burstDecay = math.max(st.burst, K.BURST_RAMJET * cfg.ramjet), K.BURST_DECAY_RJ
        st.rv = st.rv + K.NOD_KICK_RJ * cfg.nod * M
        warpStart()
        hitstop(cfg.hitstop)
        event('ramjet')
    end
    -- afterburner: lunge only once Shift has been held a moment (AB_MIN_HOLD), not again within
    -- AB_REPEAT; a first use after a rest (AB_FRESH) snaps, quick re-use eases in
    local abTime = tonumber(v.AfterburningTime) or 0
    if ab == AB_ACTIVE and st.prevAB ~= -1 and st.prevAB ~= AB_ACTIVE then st.abArmed = true end
    if ab ~= AB_ACTIVE then st.abArmed = false end
    if st.abArmed and abTime >= K.AB_MIN_HOLD then
        st.abArmed = false
        if V.t - st.lastABLunge > K.AB_REPEAT then
            if V.t - st.abLastEnd >= K.AB_FRESH then
                kick(K.AFTERBURNER_KICK * cfg.afterburner * M * dir, 0, 0)
                st.push, st.pushDecay = math.max(st.push, K.AFTERBURNER_PUSH * cfg.afterburner), K.AFTERBURNER_PUSH_DECAY
                st.rv = st.rv + K.NOD_KICK_AB * cfg.nod * M
            else
                st.abLunging, st.abLHold = true, 0
            end
            st.burst, st.burstDecay = math.max(st.burst, K.BURST_AFTERBURNER * cfg.afterburner), K.BURST_DECAY_AB
            st.lastABLunge = V.t
            hitstop(cfg.hitstopAB)
            event('afterburner')
        end
    end
    st.prevAB, st.prevRJ = ab, rj

    -- energy brake: thrown forward
    local eb = tonumber(v.EnergyBrakeState) or -1
    if eb == EB_ACTIVE and st.prevEB ~= -1 and st.prevEB ~= EB_ACTIVE then
        kick(K.EBRAKE_KICK * cfg.ebrake * M, 0, 0)
        st.burst, st.burstDecay = math.max(st.burst, 0.3 * cfg.ebrake), K.BURST_DECAY_AB
    end
    st.prevEB = eb

    -- race start launch (bigger with a better perfect start). The start itself only arms it: it fires
    -- when you really go - throttle down or already moving - within LAUNCH_WAIT s; standing at the
    -- start without accelerating gives no lunge (2026-10-17)
    local ignPhase = tonumber(v.IgnitionPhase) or -1
    if ignPhase == IGN_POST and st.prevIgn == IGN_PERFECT then st.launchUntil = V.t + K.LAUNCH_WAIT end
    if st.launchUntil and V.t > st.launchUntil then st.launchUntil = nil end
    if st.launchUntil and (thr > 0.3 or mph > 15) then
        st.launchUntil = nil
        local s0 = clamp01(v.PerfectStartStrength)
        kick(dir * (K.LAUNCH_KICK + (K.LAUNCH_KICK_PERFECT - K.LAUNCH_KICK) * s0) * cfg.launch * M, 0, 0)
        st.push, st.pushDecay = math.max(st.push, (K.LAUNCH_PUSH + (K.LAUNCH_PUSH_PERFECT - K.LAUNCH_PUSH) * s0) * cfg.launch), K.RAMJET_PUSH_DECAY
        st.burst, st.burstDecay = math.max(st.burst, (0.6 + 0.3 * s0) * cfg.launch), 0.8
        st.rv = st.rv + K.NOD_KICK_RJ * cfg.nod * cfg.launch * M
        warpStart()
        hitstop(cfg.hitstop)
        event('launch')
    end
    st.prevIgn = ignPhase

    -- landing: the vertical velocity suddenly stops falling while airborne (or LandingState -> 2);
    -- TimeInAir resets ~0.7 s before touchdown, so airPeak keeps the air time until the touchdown
    if air > st.airPeak then st.airPeak = air end
    -- (the whole flight, take-off to touchdown, for the body's slam: TimeInAir is 0 again before the
    -- touchdown, so the take-off time is kept; forgotten after 1.5 s back on the ground without a landing)
    if air > 0 then
        if not st.liftT then st.liftT = V.t - air end
        st.air0T = nil
    else
        st.air0T = st.air0T or V.t
        if st.liftT and V.t - st.air0T > 1.5 then st.liftT = nil end
    end
    fallPush(V.t, -vz)
    local ls = tonumber(v.LandingState) or 0
    local dvz = st.lastVz and (vz - st.lastVz) or 0
    st.lastVz = vz
    local airborne = ls == 1 or st.airPeak > 0.2
    local hit = airborne and dvz > K.TOUCH_DVZ
    local complete = ls == 2 and st.prevLS ~= 2
    st.prevLS = ls
    if (hit or complete) and V.t - st.lastLandT > 1.0 then
        st.lastLandT = V.t
        local airT = st.airPeak > 0.2 and st.airPeak or 0.5
        local a = math.min(airT, 1.5) / 1.5
        local L = cfg.landing
        st.jv = st.jv - K.JOLT_TAP * cfg.landHit * M * (0.6 + 0.8 * a)   -- the hit at contact, harder after longer jumps
        if V.cfg.shakeAlongOn then
            local kl = math.max(0, math.min(3, (V.rideVal('shakeAlongLand') or 0) / 100)) * V.feelPct('landing') / 100
            local flight = st.liftT and V.t - st.liftT or airT
            if flight > 10 then flight = airT end
            local ax = clamp01((flight - SLAM.AIR_T0) / (SLAM.AIR_T1 - SLAM.AIR_T0))
            local airK = SLAM.AIR_MIN + (1 - SLAM.AIR_MIN) * ax * ax   -- (1 s about x 0.24, 1.5 s about x 0.53)
            st.slamWin = { endT = V.t + SLAM.WIN, peak = fallPeak(V.t, SLAM.PEAK_T), k = kl,
                size = (1 - SLAM.SPEED / 2 + SLAM.SPEED * spd) * airK, flight = flight, airK = airK,
                shudK = 0.5 + spd, drop = 0, lost = 0, sign = math.random() < 0.5 and -1 or 1 }
        end
        kick(K.LAND_KICK * (0.5 + 0.5 * a) * L * M * cfg.landLean, 0, -K.LAND_KICK * (0.5 + 0.5 * a) * L * M)
        st.pushZ, st.pushZDecay = math.max(st.pushZ, (K.LAND_PUSH_MIN + (K.LAND_PUSH_MAX - K.LAND_PUSH_MIN) * a) * L), K.LAND_PUSH_DECAY
        st.burst, st.burstDecay = math.max(st.burst, (0.4 + 0.3 * a) * L), 0.6
        st.rv = st.rv - K.LAND_NOD * (0.5 + 0.5 * a) * cfg.nod * M
        if V.cfg.headHit then
            -- a velocity kick of v gives a peak of about 0.67 * v / w on this spring
            local k = (0.6 + 0.8 * a) * V.feelPct('landing') / 100 * TAU * math.max(1, cfg.headHitHz) / 0.67
            st.hpv = st.hpv - cfg.headHitPitch * k
            st.hrv = st.hrv + (math.random() < 0.5 and -1 or 1) * cfg.headHitRoll * k
        end
        event(string.format('landing %.1fs', airT))
        st.airPeak, st.liftT = 0, nil
    end
    -- the body's slam over the touchdown: the falling speed stopped so far (the fastest it fell just
    -- before, less what it still falls) gives the strength; it grows while the ground is still stopping
    -- the vehicle (WIN s), each frame kicking only what was added
    local sw = st.slamWin
    if sw then
        local lost = math.max(0, sw.peak - math.max(0, -vz))
        if lost > sw.lost then
            sw.lost = lost
            local f = math.min(lost / SLAM.REF, SLAM.MAX_F)
            local d = SLAM.DROP * f ^ SLAM.DROP_EXP * sw.size     -- (cm at 100 %)
            sw.raw = math.max(sw.raw or 0, d)
            -- (the biggest landings ease off toward DROP_MAX: the whole slam - drop, bounce, nose, roll,
            -- shudder - stays in proportion; 2026-10-17: up to ~68 cm down and ~45 cm back up was too much)
            if d > SLAM.DROP_KNEE then
                local room = SLAM.DROP_MAX - SLAM.DROP_KNEE
                d = SLAM.DROP_KNEE + room * (1 - math.exp(-(d - SLAM.DROP_KNEE) / room))
            end
            local drop = d * sw.k
            if drop > sw.drop then
                slamSize(d)
                slamKick(drop - sw.drop, sw.sign)
                sw.drop = drop
                slam.shud = math.max(slam.shud, softLim(drop * SLAM.SHUD_PER * sw.shudK, SLAM.SHUD_MAX))
            end
        end
        if V.t >= sw.endT then
            log(string.format('landing slam: fell %.0f cm/s, the ground stopped %.0f, %.1f s in the air (x %.2f), %.1f cm down (%.1f before the limit), spring %.1f Hz',
                sw.peak, sw.lost, sw.flight, sw.airK, sw.drop, (sw.raw or 0) * sw.k, slam.hz))
            st.slamWin = nil
        end
    end
    -- the view rises a little while airborne and drops with the touchdown
    local liftOn = (air > 0.2 or (airborne and st.airPeak > 0.2)) and cfg.airLift or 0
    st.liftZ = st.liftZ + (liftOn - st.liftZ) * (1 - math.exp(-dt / (liftOn > st.liftZ and K.LIFT_RISE or K.LIFT_DROP)))

    -- spring toward the acceleration lag target (semi-implicit Euler, substeps for stability)
    local w = TAU * math.max(0.5, cfg.springHz)
    local z = math.max(0.05, cfg.damping)
    st.push = st.push * math.exp(-dt / st.pushDecay)
    st.pushZ = st.pushZ * math.exp(-dt / st.pushZDecay)
    -- afterburner lunge envelope: eases out ~0.2 s, settles to 40 % while burning, eases back ~0.6 s
    local burningNow = ab == AB_ACTIVE and abTime > 0
    if st.abWasBurning and not burningNow then st.abLastEnd = V.t end
    st.abWasBurning = burningNow
    if not burningNow then st.abLunging = false end
    local abTarget = 0
    if st.abLunging then
        st.abLHold = st.abLHold + dt
        abTarget = 0.4 + 0.6 * math.exp(-st.abLHold / 1.0)
    end
    local abTau = abTarget > st.abL and K.AB_LUNGE_RISE or (st.abLunging and 0.5 or K.AB_LUNGE_FALL)
    st.abL = st.abL + (abTarget - st.abL) * (1 - math.exp(-dt / abTau))
    local tx = clamp(-accLP[1] * K.ACCEL_LAG * cfg.accel * M, K.LAG_MAX) + st.push * M * dir
        + st.abL * K.AFTERBURNER_PUSH * cfg.afterburner * M * dir
        + st.pushZ * cfg.landLean * M                   -- landing: lean forward with the press, out of the pilot body
    local ty = clamp(-accLP[2] * K.ACCEL_LAG * cfg.corner * M, K.LAG_MAX)
    -- vertical acceleration lag muted in the air and 0.4 s around jumps (take-off kick, free fall)
    if air > 0.05 then st.jumpQuiet = 0.4 end
    st.jumpQuiet = math.max(0, st.jumpQuiet - dt)
    local bumpScale = (air > 0.05 or st.jumpQuiet > 0) and 0 or 1
    local tz = clamp(-accLP[3] * K.ACCEL_LAG * cfg.bumps * 0.5 * M * bumpScale, K.LAG_MAX) - st.pushZ * M
    local target = { tx, ty, tz }
    local steps = math.max(1, math.ceil(dt / 0.004))
    local h = dt / steps
    for _ = 1, steps do
        for i = 1, 3 do
            local acc = -w * w * (sp[i] - target[i]) - 2 * z * w * sv[i]
            sv[i] = sv[i] + acc * h
            sp[i] = sp[i] + sv[i] * h
        end
    end
    sp[1] = math.max(-25, math.min(150, sp[1]))       -- forward: limited after the forward scale (lungeMax)
    sp[2], sp[3] = clamp(sp[2], 25), clamp(sp[3], 25)
    -- landing jolt spring (vertical only)
    local jw = TAU * math.max(2, cfg.landHitHz)
    for _ = 1, steps do
        local acc = -jw * jw * st.jp - 2 * K.JOLT_DAMP * jw * st.jv
        st.jv = st.jv + acc * h
        st.jp = st.jp + st.jv * h
    end
    st.jp = clamp(st.jp, 15)

    -- nose lift (pitch spring)
    local rjLit = rj >= RJ_ACTIVE and rj <= RJ_GRACE
    local pTarget = (rjLit and K.NOD_HOLD_RJ or 0) * cfg.nod * M + st.abL * K.NOD_AB_PEAK * cfg.nod * M
    local pw, pz = TAU * K.NOD_HZ, K.NOD_DAMP
    for _ = 1, steps do
        local acc = -pw * pw * (st.rp - pTarget) - 2 * pz * pw * st.rv
        st.rv = st.rv + acc * h
        st.rp = st.rp + st.rv * h
    end
    st.rp = clamp(st.rp, 6)
    st.rotPitch = st.rp * st.gate

    -- head hit: stiff pitch / roll spring back to level
    local hw, hz = TAU * math.max(1, cfg.headHitHz), 0.3
    for _ = 1, steps do
        st.hpv = st.hpv + (-hw * hw * st.hp - 2 * hz * hw * st.hpv) * h
        st.hp = st.hp + st.hpv * h
        st.hrv = st.hrv + (-hw * hw * st.hr - 2 * hz * hw * st.hrv) * h
        st.hr = st.hr + st.hrv * h
    end
    st.hp, st.hr = clamp(st.hp, 20), clamp(st.hr, 20)
    st.rotHeadP, st.rotHeadR = st.hp * st.gate, st.hr * st.gate

    -- warp pulse
    if warp.active then
        local wt = V.t - warp.t0
        if wt > K.WARP_LEN or cfg.warp == 0 then
            warpStop()
        else
            local env = (1 - math.exp(-wt / K.WARP_RISE)) * math.exp(-wt / K.WARP_FALL)
            setWorldScale(warp.base * (1 + K.WARP_AMOUNT * cfg.warp * env))
        end
    end

    -- rumble: road (ground only), engine idle / driving, boost bursts, ramjet hold
    st.burst = st.burst * math.exp(-dt / st.burstDecay)
    local standing = 1 - clamp01((mph - 10) / 30)
    local revNow = math.max(rpm, thr)
    local engineOn = ign >= 1 or revNow > 0.02 or mph > 1   -- IgnitionStatus 0 off, 2 / 3 running
    local tau = revNow > st.revSmooth and K.REV_RISE or K.REV_FALL
    st.revSmooth = st.revSmooth + (revNow - st.revSmooth) * (1 - math.exp(-dt / tau))
    local rev = st.revSmooth
    local road = K.ROAD_MAX * spd ^ 1.5 * ground * cfg.road
    local idle = engineOn and (standing * (K.IDLE_HUM * cfg.idle + K.IDLE_REV * rev * cfg.idleRev)
        + (1 - standing) * (K.CRUISE_HUM + K.CRUISE_REV * rev) * cfg.cruise) or 0
    local hold = 0
    if rjLit then
        hold = K.RAMJET_HOLD * (0.5 + heat) * cfg.ramjet
        if rj == RJ_CRITICAL then hold = hold + K.RAMJET_CRITICAL * cfg.ramjet end
    end
    if burningNow then hold = hold + K.AFTERBURNER_HOLD * cfg.afterburner end
    local drift = v.Drifting and K.DRIFT_RUMBLE * (0.5 + 0.5 * clamp01(v.DriftScale)) * cfg.drift or 0
    -- (shake along: on the ground; fades out fast after take-off, back in at the touchdown)
    local inAir = air > 0.05 or ls == 1 or ground < 0.5
    st.groundW = (st.groundW or 1) + ((inAir and 0 or 1) - (st.groundW or 1)) * (1 - math.exp(-dt / (inAir and 0.05 or 0.12)))
    local amp = (road + idle + hold + st.burst + drift) * M

    -- heavy layer: ramjet heat / afterburner shudder, revving while standing, slipstream buffet
    local heavy = 0
    if rjLit then
        heavy = K.RJ_HEAVY * heat ^ 1.5
        if rj == RJ_CRITICAL then heavy = heavy + K.RJ_HEAVY_CRITICAL end
        heavy = heavy * cfg.heatShake
    elseif burningNow then
        local depleted = 1 - clamp01(v.AfterburnerEnergy)
        heavy = K.AB_HEAVY * depleted ^ 1.5 * cfg.heatShake * cfg.afterburner
    end
    heavy = (heavy + (engineOn and standing * rev * 0.35 * cfg.idleRev or 0)) * M
    local ds = tonumber(v.DraftingState) or 0
    local buffet = (K.DRAFT_BUFFET[ds] or 0) * cfg.draft * M
    st.phase2 = st.phase2 + dt * (3.5 + 3.5 * heat)
    local hx = noise(st.phase2, 7) * (0.4 * heavy + 0.2 * buffet)
    local hy = noise(st.phase2, 8) * (0.8 * heavy + 1.0 * buffet)
    local hz = noise(st.phase2, 9) * (1.0 * heavy + 0.3 * buffet)
    -- afterburner rumble: while it burns, a heavier and slower shudder than the road (mostly up and
    -- down, throbbing a little), in quickly when it fires, out after; part of the trembling
    local abT = burningNow and 1 or 0
    st.abEnv = (st.abEnv or 0) + (abT - (st.abEnv or 0)) * (1 - math.exp(-dt / (abT > (st.abEnv or 0) and K.AB_RUMBLE_IN or K.AB_RUMBLE_OUT)))
    st.abPhase = (st.abPhase or 0) + dt * K.AB_RUMBLE_HZ
    local abA = K.AB_RUMBLE * cfg.abRumble * st.abEnv * M * (0.75 + 0.25 * math.sin(TAU * st.abPhase * 0.3))
    hx = hx + noise(st.abPhase, 31) * 0.3 * abA
    hy = hy + noise(st.abPhase, 32) * 0.5 * abA
    hz = hz + noise(st.abPhase, 33) * abA
    local freq = 9 + 9 * spd + 8 * rev * standing + 6 * clamp01(st.burst / 0.5)     -- Hz, below 30
    st.phase = st.phase + dt * freq
    local nx = noise(st.phase, 1) * 0.35
    local ny = noise(st.phase, 2) * 0.6
    local nz = noise(st.phase, 3)
    local low = 0
    if rjLit then low = K.RJ_LOW * (0.6 + 0.4 * heat) * cfg.lowHum * M
    elseif burningNow then
        low = K.RJ_LOW * K.AB_LOW * (0.6 + 0.4 * (1 - clamp01(v.AfterburnerEnergy))) * cfg.lowHum * cfg.afterburner * M
    end
    st.lowPhase = st.lowPhase + dt * K.RJ_LOW_HZ
    local lowZ = math.sin(TAU * st.lowPhase) * 0.7 + noise(st.lowPhase * 1.7, 11) * 0.3
    local lowX = noise(st.lowPhase, 12) * 0.3
    local lx = sp[1] + nx * amp + hx + lowX * low
    local ly = sp[2] + ny * amp + hy
    local lz = sp[3] + nz * amp + hz + lowZ * low
    if lx > 0 then lx = math.min(lx * (cfg['fwd'..vtype] or 1), cfg.lungeMax) end   -- forward scaled (dashboard close), limited
    pcall(pilotFollow, p, q, dt, ground > 0.9 and air < 0.05, air > 0.05)
    local f = st.follow
    lx, ly, lz = lx + f[1], ly + f[2], lz + f[3] + st.liftZ
    -- floor: never more than landFloor cm below the normal eye (soft, ~1 cm further at most)
    if lz < -cfg.landFloor then
        local e = -cfg.landFloor - lz
        lz = -cfg.landFloor - e * 0.3 / (1 + e * 0.3)
    end
    lz = lz + st.jp                                     -- the landing hit is not limited by the floor
    local g = st.gate
    lx, ly, lz = lx * g, ly * g, lz * g
    -- (test) the trembling and the landing hit: the vehicle body takes this part and carries you
    -- along (the view follows the seat), the view keeps the rest
    local k, kl, km = carAmount(p)
    if k > 0 or kl > 0 or km > 0 then
        -- the trembling: the view gives up the body's part; in the air the body does only its "in the
        -- air" share of it (the rest of that part is simply gone, the rest of the shake is as before)
        local rx, ry, rz = (nx * amp + hx + lowX * low) * g, (ny * amp + hy) * g, (nz * amp + hz + lowZ * low) * g
        local tx, ty, tz = rx * k, ry * k, rz * k
        -- the slower movements (spring: corner push, bobbing on the road and over hills, the landing
        -- press, impacts): what is left of the view's offset without the trembling, the pilot follow,
        -- the lift in the air and the old landing hit; the body takes km of it, the view gives that up.
        -- Not forward / back: the boost and start lunges stay in the view (the dashboard comes at you -
        -- carried by the body they got lost in the shaking world, 2026-10-17)
        local mx = 0
        local my = (ly - ry - f[2] * g) * km
        local mz = (lz - rz - (f[3] + st.liftZ + st.jp) * g) * km
        -- (in the air the body keeps shakeAlongAir of its trembling: none = a calm flight, all = speed)
        local airK = math.max(0, math.min(1, (tonumber(V.val('shakeAlongAir')) or 0) / 100))
        local gw = (st.groundW or 1) + (1 - (st.groundW or 1)) * airK
        slamStep(dt)
        local sh = slam.shud * g
        local shZ = noise(slam.ph, 21) * SLAM.SHUD * sh
        -- (smooth, above 0: the body does the driving part of its trembling -
        -- engine idle / revs, road, drift - slower and softer; the boost hold, the bursts of boosts and
        -- landings and the heavy / low layers stay as sharp as before. The view gives up the same as
        -- before. At 0 these are the very values from before.)
        local bx, by, bz = tx, ty, tz
        local sm = math.max(0, math.min(3, (tonumber(V.val('shakeAlongSmooth')) or 0) / 100))   -- (up to 300 %)
        local drive = (road + idle + drift) * M
        local drvX, drvY, drvZ = nx * drive * g * k, ny * drive * g * k, nz * drive * g * k   -- (the driving part of bx..)
        if sm > 0 then
            local boostPart = amp - drive
            -- (up to 100 %: slower down to a quarter, softer down to 60 %; beyond it on to about 4 % /
            -- 30 % at 300 %)
            local slow = sm <= 1 and (1 - 0.75 * sm) or 0.25 * 0.4 ^ (sm - 1)
            local weak = sm <= 1 and (1 - 0.4 * sm) or 0.6 * 0.7 ^ (sm - 1)
            st.phaseB = (st.phaseB or 0) + dt * freq * slow
            local soft = drive * weak
            drvX, drvY, drvZ = noise(st.phaseB, 41) * 0.35 * soft * g * k, noise(st.phaseB, 42) * 0.6 * soft * g * k, noise(st.phaseB, 43) * soft * g * k
            bx = (noise(st.phaseB, 41) * 0.35 * soft + nx * boostPart + hx + lowX * low) * g * k
            by = (noise(st.phaseB, 42) * 0.6 * soft + ny * boostPart + hy) * g * k
            bz = (noise(st.phaseB, 43) * soft + nz * boostPart + hz + lowZ * low) * g * k
        end
        -- (boosting: the body rumbles steadily the whole time the ramjet / afterburner burns - in the
        -- middle of a ramjet and through a long afterburner the shaking along was too weak, the speed
        -- felt gone (2026-10-17). New motion of the body only, sharp; half of it even at low "Trembling")
        local bt = rjLit and 1 or (burningNow and 0.7 or 0)
        st.saEnv = (st.saEnv or 0) + (bt - (st.saEnv or 0)) * (1 - math.exp(-dt / (bt > (st.saEnv or 0) and 0.12 or 0.4)))
        if st.saEnv > 0.001 then
            st.saPh = (st.saPh or 0) + dt * SA_BOOST_HZ
            local a = SA_BOOST * st.saEnv * (0.5 + 0.5 * k) * g
            bx = bx + noise(st.saPh, 51) * 0.3 * a
            by = by + noise(st.saPh, 52) * 0.5 * a
            bz = bz + noise(st.saPh, 53) * a
        end
        -- (smooth also softens the bobbing up and down (road, hills, the landing press) the body does:
        -- a low-pass from about 8 Hz (a little smooth) to 1.5 Hz (full); the view gives up the same as
        -- before. At 0 the body takes mz itself, as before.)
        local mzB = mz
        if sm > 0 then
            local fc = math.max(0.4, 8 * (1.5 / 8) ^ sm)      -- (1.5 Hz at 100 %, 0.4 Hz from about 190 %)
            st.mzS = st.mzS or mz
            st.mzS = st.mzS + (mz - st.mzS) * (1 - math.exp(-dt * TAU * fc))
            mzB = st.mzS
        else
            st.mzS = nil
        end
        carT[1], carT[2] = bx * gw + mx, by * gw + my
        carT[3] = bz * gw + mzB + (slam.z + shZ) * g
        local tilt = V.val('alongTilt')
        local rawP = (bz * gw + mzB) * tilt + (slam.p + noise(slam.ph, 22) * SLAM.SHUD_P * sh) * g
        local rawR = (by * gw + my) * tilt + slam.r * g
        carTilt[1], carTilt[2] = noseLim(rawP), clamp(rawR, 10)
        -- (second smooth, above 0: everything the body does that the first smooth leaves alone - boost /
        -- ramjet rumble and bursts, overheating, slipstream, the steady boost rumble, the corner push,
        -- the landing slam - goes through a low-pass, from about 5 Hz at 100 % to 1 Hz at 300 %, a
        -- little louder so it is still felt. The driving trembling and the bobbing stay as the first
        -- smooth makes them; the view gives up the same as before. At 0 nothing here runs.)
        local sm2 = math.max(0, math.min(3, (tonumber(V.val('shakeAlongSmooth2')) or 0) / 100))
        if sm2 > 0 then
            local dX, dY, dZ = drvX * gw + mx, drvY * gw, drvZ * gw + mzB
            local dP, dR = (drvZ * gw + mzB) * tilt, drvY * gw * tilt
            local rest = { carT[1] - dX, carT[2] - dY, carT[3] - dZ, rawP - dP, rawR - dR }
            local a = 1 - math.exp(-dt * TAU * 12 * (1 / 12) ^ (sm2 / 3))
            local gain = 1 + 0.3 * sm2
            if not st.r2 then st.r2 = { rest[1], rest[2], rest[3], rest[4], rest[5] } end
            for i = 1, 5 do st.r2[i] = st.r2[i] + (rest[i] - st.r2[i]) * a end
            carT[1], carT[2], carT[3] = dX + st.r2[1] * gain, dY + st.r2[2] * gain, dZ + st.r2[3] * gain
            carTilt[1], carTilt[2] = noseLim(dP + st.r2[4] * gain), clamp(dR + st.r2[5] * gain, 10)
        else
            st.r2 = nil
        end
        if car.free then
            -- (the pod mesh moves only a little: the view gives up just what it really does, the old
            -- landing hit stays in the view)
            local m = POD_MOVE
            -- (what the view gives up: the pod's share as it is without smoothing - with smooth the pod
            -- mesh does it softer, the view still gives up the sharp one; at 0 both are the same)
            local vx, vy, vz = carT[1], carT[2], carT[3]
            if bx ~= tx or by ~= ty or bz ~= tz or mzB ~= mz or sm2 > 0 then
                vx, vy, vz = tx * gw + mx, ty * gw + my, tz * gw + mz + (slam.z + shZ) * g
            end
            carT[1], carT[2], carT[3] = clamp(carT[1], m), clamp(carT[2], m), clamp(carT[3], m)
            lx, ly, lz = lx - clamp(vx, m), ly - clamp(vy, m), lz - clamp(vz, m)
        else
            -- (the old landing hit moved only the view: with the body slamming, the view gives it up)
            lx, ly, lz = lx - tx - mx, ly - ty - my, lz - tz - mz - st.jp * g * math.min(kl, 1)
        end
        car.q, car.want = q, true                      -- (moved right before the frame is drawn)
    else
        car.want = false
        if car.moved then carStop() end
    end
    V.feelDown, V.feelFwd, V.air = -lz, lx, air       -- (the eye against the cockpit)
    po[1], po[2], po[3] = rotate(q, lx, ly, lz)
end

V.hooks.feel = function(view, position, rotation)
    local po = st.posOff
    position.x, position.y, position.z = position.x + po[1], position.y + po[2], position.z + po[3]
    if st.rotPitch ~= 0 then rotation.x = rotation.x + st.rotPitch end
    if st.rotHeadP ~= 0 then rotation.x = rotation.x + st.rotHeadP end
    if st.rotHeadR ~= 0 then rotation.z = rotation.z + st.rotHeadR end
    -- (shake along with the vehicle: the view turns with the body)
    if car.moved then rotation.x, rotation.z = rotation.x + carTilt[1], rotation.z + carTilt[2] end
end
V.onTick('feel', function(dt)
    local ok, err = pcall(update, dt)
    if not ok then
        st.posOff[1], st.posOff[2], st.posOff[3] = 0, 0, 0
        reset()
        if V.t > (st.nextErr or 0) then st.nextErr = V.t + 5; log('error: '..tostring(err)) end
    end
    -- hit-stop on its own, so it always finishes whatever update() does
    local okH, errH = pcall(hitstopTick, math.min(dt, 0.1))
    if not okH then log('hit-stop error: '..tostring(errH)); pcall(hitstopEnd) end
end)
V.onReset(function() warpStop(); hitstopEnd(); pcall(carStop) end)
