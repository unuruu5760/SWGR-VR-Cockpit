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
-- (the hit-stop: since 2026-10-27 only the picture stops short and shoots on - see "hit-stop" below - with
-- new defaults for every vehicle; the old ones were 0.333 / 0.077 / 0.164 (.before: one saved equal to them
-- by an older version was never the user's own), cars 0.53 / 0.33 / 0.16 (00_core))
V.tunable('boost', 'hitstopStrength', 0.7, 0, 1, 'Hit-stop strength (ramjet / start)', 'How hard what you see stops short at ramjet ignition and the race start (when the hit-stop is ticked). 1 = the strongest (about a quarter speed), 0 = no stop. Only your picture: the game keeps its full speed.').before = 0.333
V.tunable('boost', 'hitstopAB', 0.5, 0, 1, 'Hit-stop strength (afterburner)', 'The same stop for the afterburner. 0 = none.').before = 0.077
V.tunable('boost', 'hitstopTime', 0.1, 0.05, 0.4, 'Hit-stop length (s)', 'How long the stop lasts (seconds) before it shoots on to catch up. The faster you go, the shorter a long one is cut: what you see can only be drawn so far behind.').before = 0.164
V.tunable('boost', 'warpAmount', 3.0, -5, 5, 'Warp pulse strength (+ / -)', 'At ramjet ignition and the race start the size of the world pulses for a moment (when "Warp pulse" is ticked). Plus = the world briefly shrinks and moves away, minus = it briefly grows and rushes at you. Further from 0 = stronger. 0 = no pulse.')

-- % of a group for the current vehicle: its own value if it has one, else the shared one. On top, per
-- vehicle type: one overall % for the amounts saved for a vehicle, one for all the others (its default
-- or the shared value), so the defaults can be turned up or down without touching what was set by hand.
-- (Older versions had one pair for every type: it becomes each type's, once.)
if V.cfgFormat < 2 and not V.old.shakeMasterByType then
    for _, ty in ipairs({ 'Bike', 'Car', 'Skimmer', 'Plane' }) do
        V.cfg['shakeDefault_'..ty] = tonumber(V.old.shakeDefault) or 100
        V.cfg['shakeSaved_'..ty] = tonumber(V.old.shakeSaved) or 100
    end
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

-- the hit-stop's state (see "hit-stop" below)
local fh = { active = false, t = 0, slow = 1, hold = 0.16, D = 0, Dpeak = 0, ownLag = nil, ownOk = nil, ownWhy = nil,
    others = {}, lags = {}, leftSet = {}, found = {}, prep = {}, checking = {}, fx = {}, fxS = nil, checked = {}, freeze = 0, freezeL = nil,
    lagMost = 0, mph = 0, applied = false, broken = {}, othersFailed = nil, info = { used = false }, told = {}, failedParts = {} }
local hsStart, hsEnd
local checkStart                           -- (the hit-stop check, below)
-- The hit-stop's own settings: fixed, no menu - only the hit-stop on / off, its strengths and its length
-- are the player's (2026-10-27, the user: the rest was for working it out). The tests change them.
--   view / others / fx: your vehicle, the 6 nearest you see, their effects are slowed; pods (podsOnline:
--   online too): podracers; sling: it shoots on right after the stall; freeze: the cockpit shake held
--   (off: the old hit-stop never held it); maxLag: cm drawn behind at most; catch: s to catch up;
--   catchMax: without sling, catching up at most this many in 100 faster; check / log: the hit-stop
--   check and the per-event lines (only for working on it - failures are always said).
V.fhOpt = { view = true, others = true, fx = true, pods = true, podsOnline = true, sling = true, freeze = false,
    maxLag = 3000, catch = 0.35, catchMax = 8, check = false, log = false }
-- (an object still there? never touched once gone; without UEVR's check (the tests) taken as there)
local function alive(o)
    if not o then return false end
    local hook = rawget(_G, 'UEVR_UObjectHook')
    if not hook then return true end
    local ok, yes = pcall(function() return hook.exists(o) end)
    return ok and yes == true
end                            -- (below)
local function gsCall(fn)
    local gs = api:find_uobject('Class /Script/Engine.GameplayStatics')
    local ctx = api:get_player_controller(0)
    if not gs or not ctx then return nil end
    return fn(gs:get_class_default_object(), ctx)
end
-- hit-stop: at ramjet ignition, the afterburner and the race start what you see stops short for a moment
-- and shoots on to catch up (see "hit-stop" below). Until 2026-10-27 it slowed the whole game
-- (SetGlobalTimeDilation): online that cost the race time for good, so now only the picture does it.
-- A failure to start stops it for the session (said in the log and the menu).
local function hitstop(strength)
    if strength <= 0 or cfg.hitstopTime <= 0 or not hsStart then return end
    local okS, errS = pcall(hsStart, strength)
    if not okS then
        fh.broken.start, fh.info.stopped = tostring(errS), true
        log('hit-stop: starting it failed, it stops: '..fh.broken.start)
        pcall(hsEnd)
    end
    if checkStart and V.fhOpt.check then
        local why = (not fh.active and 'it did not start') or (not fh.ownOk and fh.ownWhy) or nil
        pcall(checkStart, 'picture', fh.active and fh.slow or 1, fh.active and fh.hold or cfg.hitstopTime, why)
    end
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
if V.cfgFormat < 2 and not V.old.shakeAlongPerVehicle then
    for _, key in ipairs({ 'shakeAlong', 'shakeAlongSmooth', 'shakeAlongSmooth2', 'shakeAlongAir', 'shakeAlongMove' }) do
        local old, item = tonumber(V.old[key]), V.TUNE_INDEX[key]
        if old and item and math.abs(old - item.base) > 0.001 then V.cfg.detail[key] = old end
    end
end
-- (the landing slam amount changed meaning on 2026-10-17: 100 = the new design, the old one needed
-- 500 to be felt at all. Values saved with the old meaning are dropped, once.)
if V.cfgFormat < 2 and not V.old.landSlamV2 then
    V.cfg.detail.shakeAlongLand = nil
    for m in pairs(V.veh.detail) do V.clearOwnVal('detail', m, 'shakeAlongLand') end
    V.saveVeh()
end
-- (an older settings file: written again in today's shape, its old keys gone)
if V.cfgFormat < 2 then V.save() end
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
local partOf                               -- (below: the part over a given seat mesh)
local function carFind(p)
    local seat = nil
    for _, c in ipairs(V.components(p, 'Engine.StaticMeshComponent')) do
        local a = c.StaticMesh
        if a and S.anchor and a:get_full_name() == S.anchor.model then seat = c; break end
    end
    if not seat then return nil, 'no seat mesh' end
    return partOf(p, seat)
end
partOf = function(p, seat)
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
    car.moved, car.base, car.lagged = false, nil, false
    carT[1], carT[2], carT[3], carTilt[1], carTilt[2] = 0, 0, 0, 0, 0
    slamReset()
end
-- another vehicle (or none): its body is found anew, and what the hit-stop found was for the old one
local function carNewPawn(id)
    if fh.active and hsEnd then pcall(hsEnd) end
    carStop()
    car.pawn, car.comp, car.parent, car.failed = id, nil, nil, nil
    fh.checked, fh.told, fh.found, fh.foundKey, fh.ownNot, fh.ownFx, fh.prep, fh.checking = {}, {}, {}, nil, nil, {}, {}, {}
    fh.failedParts = {}
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
    if id ~= car.pawn then carNewPawn(id) end
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
    -- (the hit-stop: drawn behind - checked when it started: a pod only offline and free of collision)
    local lag = fh.ownLag
    car.lagged = lag ~= nil
    if lag then wx, wy, wz = wx + lag[1], wy + lag[2], wz + lag[3] end
    car.drawOff = { wx, wy, wz }                   -- (what the seat was moved by for this frame, world axes)
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
local fhMoveOthers                         -- (below)
V.beforeSeat = function()
    if fh.active and fhMoveOthers and not fh.othersFailed then
        local okO, errO = pcall(fhMoveOthers)
        if not okO then fh.othersFailed = tostring(errO); log('hit-stop: the other vehicles left alone from now on: '..fh.othersFailed) end
    end
    if not car.want then return end
    -- (only on your vehicle as it is now: leaving the race from the pause menu may have taken it away)
    local okP, p = pcall(function() return api:get_local_pawn(0) end)
    if not okP or not p or p:get_address() ~= car.pawn then car.want = false; return end
    local ok, err = pcall(carMove, car.q)
    if not ok then
        car.failed, car.want = tostring(err), false
        log((V.cfg.shakeAlongOn and 'shake along with the vehicle turned off: ' or 'hit-stop: your body part can not be moved, left alone: ')..car.failed)
        carStop()
        fh.ownOk, fh.ownLag, fh.ownWhy = false, nil, 'its body part can not be moved (see the log)'
    end
end

local function reset()
    if hsEnd then pcall(hsEnd) end
    pcall(carStop)
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

-------------------------------------------------------------------------------- hit-stop
-- 2026-10-27, a player: "the hit-stop costs time in online races, about 8.5 m per ramjet in an online
-- podrace". It did: it slowed the whole game on this PC (global time dilation), and online this PC works
-- out its own vehicle and sends it to the server (Server_UpdateAuthoritiveBodyState: pose, velocity,
-- time), so the time it slowed was lost for good - about 0.056 s per ramjet with the shared values,
-- 0.087 s on a landspeeder. Now it slows only what you see; the game runs on at full speed (fh):
--  - a time behind, D, grows as slowing the game would lose it through the hold, then is given back right
--    after it, over a short catch-up (V.fhOpt.catch; sling: a cubic that starts at the hold's speed);
--  - your vehicle's body part and the other vehicles near you are drawn behind where they are: each one's
--    way back is added up from its own velocity while it slows (a hit or a landing in the middle bends
--    it, never makes it jump), then given back with D; eased off toward V.fhOpt.maxLag;
--  - for the picture only: put back where the game had it first thing in the tick and drawn behind again
--    right before the frame (relative place, teleport), so the game never works with a moved part;
--  - their effects (flames, exhaust: Niagara) run slower by the same factor (their own time dilation).
--    (V.fhOpt.sling off - a ramp back, then the catch-up - and freeze on - the cockpit's shake held - were
--    tried while working it out and stay for that.)
-- The sound is left alone (lowering its pitch bent the music too, 2026-10-27, the user).
-- A part is moved only if nothing in it collides (no physics, no overlap events; checked once per part,
-- said in the log). Podracers' parts too (never the containers the game places them by - moving one
-- wrecked the vehicle, 2026-10-16), online as well (V.fhOpt.podsOnline: tried offline, the game never
-- works with a moved part). Worked out with a test menu against the old one (2026-10-27: the same look
-- through the stall, the frames as many as with the old one).
local FH_RANGE, FH_MAX = 15000, 6          -- cm, vehicles: the others drawn behind (12 cost late frames, 2026-10-27)
-- a part and everything under it: may it be drawn behind? Not if anything in it has physics collision
-- (ECollisionEnabled: 0 none, 1 query only, anything else with physics), simulates physics, or is a query
-- part that sends overlap events (it would enter and leave triggers)
local function checkNew(comp)
    local kids = {}
    if not pcall(function() comp:GetChildrenComponents(true, kids) end) then return nil end
    local w = { list = { comp }, i = 0, none = 0, query = 0, overlap = 0, phys = 0, unread = 0, raw = {}, bad = {} }
    for _, k in ipairs(kids) do w.list[#w.list + 1] = k end
    return w
end
local function checkOne(w, c, prim)
    local okA, isP = pcall(function() return prim ~= nil and c:is_a(prim) end)
    if not (okA and isP) then return end
    local ok, e = pcall(function() return tonumber(c:GetCollisionEnabled()) end)
    local okS, sim = pcall(function() return c:IsSimulatingPhysics() end)
    local was = w.phys + w.overlap + w.unread
    if not ok or not e then
        w.unread = w.unread + 1
    else
        w.raw[e] = (w.raw[e] or 0) + 1
        if okS and sim == true then w.phys = w.phys + 1
        elseif e == 0 then w.none = w.none + 1
        elseif e == 1 then
            local okO, ov = pcall(function() return c:GetGenerateOverlapEvents() end)
            if not okO or ov == nil then okO, ov = pcall(function() return c.bGenerateOverlapEvents end) end
            if not okO or ov == nil then w.unread = w.unread + 1
            elseif ov then w.overlap = w.overlap + 1
            else w.query = w.query + 1 end
        else w.phys = w.phys + 1 end
    end
    if w.phys + w.overlap + w.unread > was and #w.bad < 4 then
        local okN, n = pcall(function() return c:get_fname():to_string()..' ('..c:get_class():get_fname():to_string()..', '..tostring(e)..')' end)
        w.bad[#w.bad + 1] = okN and n or '?'
    end
end
local function checkVerdict(w)
    local vals = {}
    for e, n in pairs(w.raw) do vals[#vals + 1] = e..' x'..n end
    table.sort(vals)
    local text = string.format('%d parts: %d no collision, %d query only, %d query with overlap events, %d with physics, %d unreadable (collision values %s)',
        w.none + w.query + w.overlap + w.phys + w.unread, w.none, w.query, w.overlap, w.phys, w.unread, #vals > 0 and table.concat(vals, ', ') or 'none')
    if #w.bad > 0 then text = text..'; not free: '..table.concat(w.bad, ', ') end
    return w.phys == 0 and w.unread == 0 and w.overlap == 0 and w.none + w.query > 0, text
end
local function physicsFree(comp)
    local w = checkNew(comp)
    if not w then return false, 'its parts can not be listed' end
    local prim = V.class('Engine.PrimitiveComponent')
    for _, c in ipairs(w.list) do checkOne(w, c, prim) end
    return checkVerdict(w)
end
local function checkPart(comp)
    local id = comp:get_address()
    local chk = fh.checked[id]
    if not chk then
        local ok, safe, text = pcall(physicsFree, comp)
        chk = { ok and safe == true, ok and text or ('check failed: '..tostring(safe)) }
        fh.checked[id] = chk
        fh.checking[id] = nil
    end
    return chk[1], chk[2]
end
-- (the same check a piece at a time: up to n of its parts a call; the verdict once done, nil before -
-- a whole vehicle at once was an 18 ms frame, 2026-10-27)
local function checkPartStep(comp, n)
    local id = comp:get_address()
    local chk = fh.checked[id]
    if chk then return chk[1], chk[2] end
    local ok, safe, text = pcall(function()
        local w = fh.checking[id]
        if not w then
            w = checkNew(comp)
            if not w then return false, 'its parts can not be listed' end
            fh.checking[id] = w
            return nil
        end
        local prim = V.class('Engine.PrimitiveComponent')
        for _ = 1, n do
            if w.i >= #w.list then break end
            w.i = w.i + 1
            checkOne(w, w.list[w.i], prim)
        end
        if w.i < #w.list then return nil end
        return checkVerdict(w)
    end)
    if ok and safe == nil then return nil end
    fh.checking[id] = nil
    fh.checked[id] = { ok and safe == true, ok and text or ('check failed: '..tostring(safe)) }
    return fh.checked[id][1], fh.checked[id][2]
end
-- a way back, eased off toward the farthest (fhMaxLag): as it is up to 70 % of it
local function capLag(x, y, z)
    local most = math.max(0, tonumber(V.fhOpt.maxLag) or 1500)
    local n = math.sqrt(x * x + y * y + z * z)
    if n <= 0 or most <= 0 then return 0, 0, 0 end
    local k = kneeLim(n, 0.7 * most, most) / n
    return x * k, y * k, z * k
end
-- (still where we put it?)
local function at(l, p) return math.abs(l.X - p[1]) + math.abs(l.Y - p[2]) + math.abs(l.Z - p[3]) <= 0.05 end
-- Still there? UEVR's object check knows vehicles and effects, but not every part: 2026-10-27 it did not
-- know this game's body containers (CstVehicleContainer), so the hit-stop dropped your body as gone and
-- never moved it (the hit-stop check showed the seat at full speed). So a part is checked against its
-- vehicle's own list of parts (once per event, no call on the part itself), and only a vehicle goes
-- through UEVR's check - unless that does not know vehicles either (then said once, and taken as there).
local function pawnAlive(o)
    if fh.pawnBlind then return o ~= nil end
    return alive(o)
end
local function pawnKnown(o)
    if fh.pawnBlind or not rawget(_G, 'UEVR_UObjectHook') or alive(o) then return end
    fh.pawnBlind = true
    log('hit-stop: UEVR\'s object check does not know the vehicles: they are not checked while it runs')
end
local function partsOf(o)
    local set = {}
    for _, c in ipairs(V.components(o, 'Engine.SceneComponent')) do set[c:get_address()] = true end
    return set
end
-- (a vehicle's records found among its parts are marked; one of those no longer there - broken off, or its
-- parts made anew - and it is looked into again. A record that never was among them - a part of an actor
-- hung on it - or one that failed never counts)
local function markHad(recs, have)
    for _, r in ipairs(recs) do r.had = have[r.comp:get_address()] == true end
end
local function partGone(recs, have)
    for _, r in ipairs(recs) do if r.had and not r.failed and not have[r.comp:get_address()] then return true end end
    return false
end
local fhS = {}
-- (a part's place only - its rotation as it is; no sweep, teleport)
local function setLoc(r, x, y, z)
    fhS.loc = fhS.loc or StructObject.new(api:find_uobject('ScriptStruct /Script/CoreUObject.Vector'))
    fhS.hit = fhS.hit or StructObject.new(api:find_uobject('ScriptStruct /Script/Engine.HitResult'))
    fhS.loc.X, fhS.loc.Y, fhS.loc.Z = x, y, z
    r.comp:K2_SetRelativeLocation(fhS.loc, false, fhS.hit, true)
    r.last = { x, y, z }
end
-- What it costs, per event: the time of the put-back, the tick and the move before the frame (the
-- clock: os.clock - wall time in ms steps on Windows - or none). 2026-10-27, the user: "frame drops with
-- many opponents" - every other vehicle's parts and effects were moved twice a frame.
local clock = (type(os) == 'table' and type(os.clock) == 'function') and os.clock or function() return 0 end
local function costAdd(key, t0)
    local c = fh.cost
    if not c then return end
    local d = clock() - t0
    c[key], c.cur = c[key] + d, c.cur + d
end
-- offline: a game on this PC alone (standalone, no net driver). Not known counts as online.
local function fhOffline()
    if fh.broken.offline then return false end
    local world = nil
    local ok, yes = pcall(function()
        world = api:get_engine().GameViewport.World
        return api:find_uobject('Class /Script/Engine.KismetSystemLibrary'):get_class_default_object():IsStandalone(world)
    end)
    if not ok then
        fh.broken.offline = tostring(yes)
        log('hit-stop: offline or online can not be told ('..fh.broken.offline..'): podracers are left alone')
        return false
    end
    if yes ~= true then return false end
    local okN, nd = pcall(function() return world.NetDriver end)
    return not (okN and nd ~= nil)
end
-- A podracer (only with "Podracers too", 2026-10-27, the user: "do podracers too, I'll try it"): its
-- free containers (hanging on nothing: the pod, the engines) stay where the game puts them every frame;
-- what hangs right under each is drawn behind instead, if it does not collide. (The 2026-10-16 wreck
-- came from moving a container: the game places the pod's next place from it, so it added up.)
local function podParts(o, except)
    local root = o.RootComponent
    local rootId = root and root:get_address()
    local list = {}
    for _, c in ipairs(V.components(o, 'Engine.SceneComponent')) do
        local okP, par = pcall(function() return c:GetAttachParent() end)
        if okP and par == nil and c:get_address() ~= rootId then
            local kids = {}
            if pcall(function() c:GetChildrenComponents(false, kids) end) then
                for _, k in ipairs(kids) do
                    if k:get_address() ~= except then list[#list + 1] = k end
                end
            end
        end
    end
    return list
end
local function podRecords(o, except, who)
    local recs = {}
    for _, k in ipairs(podParts(o, except)) do
        local safe, text = checkPart(k)
        local id = k:get_address()
        if not fh.told[id] then
            fh.told[id] = true
            if (not safe and who == 'yours') or V.fhOpt.log then log('hit-stop, podracer ('..who..'): '..k:get_fname():to_string()..' - '..text..(safe and ': drawn behind' or ': left alone')) end
        end
        if safe then recs[#recs + 1] = { pawn = o, comp = k } end
    end
    return recs
end
-- Your effects that hang outside the parts drawn behind (on the vehicle's middle, or on a container that
-- stays): drawn behind with them, those free of collision (2026-10-27, the user: the laser between a
-- podracer's engines ran ahead and came back - it hangs on CustomisationRoot). Taken anew at each event:
-- effects come and go, so each frame only those still in the vehicle's list are touched (fhFxHere). An
-- effect whose particles live in the world may still not follow: the game makes them in its own tick,
-- where everything is in its real place. Said once per vehicle (name, system, what it hangs on).
local function fxFree(c)
    local ok, e = pcall(function() return tonumber(c:GetCollisionEnabled()) end)
    return ok and e == 0
end
-- (its system's name, and whether it is a beam - a line drawn between two places: the laser between a
-- podracer's engines (NS_PlasmaBeam), its cables (NS_CableBeam). Only those are drawn behind when they
-- hang outside the parts: the rest - hull, ground wake ... 22 of 25 on a podracer - were 80 % of the
-- cost, 2026-10-27 7-8 ms a frame with 4-6 podracers near, and nothing to see)
local function fxSystem(c)
    local ok, sys = pcall(function() local a = c.Asset; return a and a:get_fname():to_string() or '?' end)
    sys = ok and sys or '?'
    return sys, sys:lower():find('beam', 1, true) ~= nil
end
local function fhFxHere(pw)
    local set = {}
    for _, c in ipairs(V.components(pw, 'Niagara.NiagaraComponent')) do set[c:get_address()] = true end
    return set
end
local function fhLooseFx(p)
    local moved = {}
    if car.comp then moved[car.comp:get_address()] = true end
    for _, r in pairs(fh.others) do if r.mine then moved[r.comp:get_address()] = true end end
    local names, left = {}, 0
    fh.ownFx = fh.ownFx or {}
    for _, c in ipairs(V.components(p, 'Niagara.NiagaraComponent')) do
        local id = c:get_address()
        local v = fh.ownFx[id]
        if not v then
            -- (looked at once per effect: a beam, hanging outside what is drawn behind, free of collision)
            local sys, beam = fxSystem(c)
            local covered = true
            if beam then
                local x = c
                covered = false
                for _ = 1, 24 do
                    if not x then break end
                    if moved[x:get_address()] then covered = true; break end
                    local ok, up = pcall(function() return x:GetAttachParent() end)
                    x = ok and up or nil
                end
            end
            local okA, abs = pcall(function() return c:IsUsingAbsoluteLocation() end)
            v = { ok = beam and not covered and fxFree(c), abs = okA and abs == true, new = true, sys = sys, beam = beam }
            fh.ownFx[id] = v
        end
        if v.new and not v.beam then left = left + 1 end
        if v.ok and not fh.others[id] and not fh.failedParts[id] then
            fh.others[id] = { pawn = p, comp = c, mine = true, fx = true, abs = v.abs }
            if v.new and not fh.told.looseFx and #names < 30 then
                local okP, par = pcall(function() local u = c:GetAttachParent(); return u and u:get_fname():to_string() or 'nothing' end)
                names[#names + 1] = c:get_fname():to_string()..' ('..v.sys..') < '..(okP and par or '?')..(v.abs and ' [abs]' or '')
            end
        end
        v.new = false
    end
    if (#names > 0 or left > 0) and not fh.told.looseFx then
        fh.told.looseFx = true
        if V.fhOpt.log then log('hit-stop: your beams drawn behind with it too ('..#names..'): '..table.concat(names, ', ')..'; '..left..' other effects left as they are') end
    end
end
-- your own body part: the one ride shake moves (found here if ride shake is off). Gives ok and, if not,
-- a short reason for the menu (the details are in the log)
local CANT = 'its body part can not be moved (see the log)'
local function fhOwn(p)
    local id = p:get_address()
    if car.failed then return false, CANT end
    if car.comp and not partsOf(p)[car.comp:get_address()] then car.comp, car.parent, car.base, car.moved = nil, nil, nil, false end
    if not car.comp then
        if fh.ownNot == id then return false, CANT end
        local ok, c, why, free = pcall(carFind, p)
        if not ok or not c then
            fh.ownNot = id
            log('hit-stop: your body part not found: '..(ok and tostring(why) or tostring(c)))
            return false, CANT
        end
        car.comp, car.parent, car.free = c, c:GetAttachParent(), free == true
    end
    if car.free then
        if not V.fhOpt.pods then return false, 'Podracers too is off' end
        if not fh.offline then
            return false, fh.broken.offline and 'podracers: offline or online can not be told (see the log)' or 'podracers: offline only for now'
        end
    end
    local cid = car.comp:get_address()
    local safe, text = checkPart(car.comp)
    if not fh.told[cid] then
        fh.told[cid] = true
        if not safe or V.fhOpt.log then log('hit-stop: your '..(car.free and 'pod ' or 'body part ')..car.comp:get_fname():to_string()..' - '..text..(safe and ': drawn behind' or ': left alone')) end
    end
    if not safe then return false, 'its body part collides (see the log)' end
    if car.free then
        -- (the rest of it - the engines - drawn behind with it, those that do not collide)
        local f, have = fh.found[id], partsOf(p)
        if f and f.mine and partGone(f.mine, have) then f = nil end      -- (a part gone: looked into again)
        if not (f and f.mine) then f = { mine = podRecords(p, cid, 'yours') }; markHad(f.mine, have); fh.found[id] = f end
        for _, r in ipairs(f.mine) do
            local a = r.comp:get_address()
            if fh.failedParts[a] then r.failed = true end              -- (failed before it was looked into again)
            if not r.failed and have[a] then r.mine = true; fh.others[a] = r end
        end
    end
    pcall(fhLooseFx, p)
    return true, nil
end
-- another vehicle's body part (over its seat mesh, the mesh with the seat socket): a list of parts to
-- draw behind, or nil and why
local function fhOther(o)
    local seat = nil
    for _, c in ipairs(V.components(o, 'Engine.StaticMeshComponent')) do
        local ok, has = pcall(function() return c:DoesSocketExist('PilotSeat') end)
        if ok and has then seat = c; break end
    end
    if not seat then return nil, 'no seat mesh' end
    local comp, why, free = partOf(o, seat)
    if not comp then return nil, why end
    if free then
        if not V.fhOpt.pods then return nil, 'a podracer (Podracers too is off)' end
        if not fh.offline then return nil, 'a podracer (offline only for now)' end
        local recs = podRecords(o, nil, o:get_class():get_fname():to_string())
        if #recs == 0 then return nil, 'a podracer with no part free of collision' end
        recs.pod = true
        return recs
    end
    local safe, text = checkPart(comp)
    if safe then return { { pawn = o, comp = comp } } end
    -- (something in it collides - every other vehicle had one part with physics in it, 2026-10-27. If the
    -- part only holds others (no shape of its own), what hangs right under it is drawn behind one by one,
    -- each free of collision; what collides stays where it is)
    local prim = V.class('Engine.PrimitiveComponent')
    local okP, isPrim = pcall(function() return prim ~= nil and comp:is_a(prim) end)
    if not okP or isPrim then return nil, text end
    local kids, recs, kept = {}, {}, {}
    if not pcall(function() comp:GetChildrenComponents(false, kids) end) then return nil, text end
    for _, k in ipairs(kids) do
        if checkPart(k) then recs[#recs + 1] = { pawn = o, comp = k } else kept[#kept + 1] = k:get_fname():to_string() end
    end
    if #recs == 0 then return nil, text end
    if V.fhOpt.log then
        log('hit-stop: another vehicle ('..o:get_class():get_fname():to_string()..'): '..text..' - what hangs under '
            ..comp:get_fname():to_string()..' drawn behind one by one ('..#recs..'), left where it is: '..table.concat(kept, ', '))
    end
    return recs
end
-- Before another vehicle is looked into (fhOther), the collision checks it will need are done a piece a
-- call (FH_CHECK_STEP parts), so no frame does a whole vehicle: the seat search one call, then its body
-- part (and, if something in it collides, the parts right under it) or a podracer's parts. True once
-- fhOther finds them all ready.
local FH_CHECK_STEP = 30
local function fhPrepare(o, id)
    local pr = fh.prep[id]
    if not pr then
        local seat = nil
        for _, c in ipairs(V.components(o, 'Engine.StaticMeshComponent')) do
            local ok, has = pcall(function() return c:DoesSocketExist('PilotSeat') end)
            if ok and has then seat = c; break end
        end
        pr = { todo = {} }
        if seat then
            local comp, _, free = partOf(o, seat)
            if comp and free then
                if V.fhOpt.pods and fh.offline then pr.todo = podParts(o, nil) end
            elseif comp then
                pr.todo, pr.body = { comp }, comp:get_address()
            end
        end
        fh.prep[id] = pr
        return false
    end
    local c = pr.todo[#pr.todo]
    if not c then return true end
    local safe = checkPartStep(c, FH_CHECK_STEP)
    if safe == nil then return false end
    table.remove(pr.todo)
    if not safe and c:get_address() == pr.body then
        -- (something in it collides: the parts right under it next, as fhOther will look at them)
        pr.body = nil
        local prim = V.class('Engine.PrimitiveComponent')
        local okP, isPrim = pcall(function() return prim ~= nil and c:is_a(prim) end)
        local kids = {}
        if okP and not isPrim and pcall(function() c:GetChildrenComponents(false, kids) end) then
            for _, k in ipairs(kids) do pr.todo[#pr.todo + 1] = k end
        end
    end
    return #pr.todo == 0
end
-- another podracer's effects hanging right on its middle (its root - the laser between its engines, its
-- cables): drawn behind with it, as yours - only the FH_FX_NEAR nearest, and only podracers (where a
-- laser runs ahead; others' hull effects are too small to see). What each effect is, is kept with the
-- vehicle (one look at its parent per effect, ever).
local FH_FX_NEAR = 3
local function fhLooseFxOf(o, pawnId, f)
    local root = o.RootComponent
    local rootId = root and root:get_address()
    if not rootId then return end
    f.fxv = f.fxv or {}
    for _, c in ipairs(V.components(o, 'Niagara.NiagaraComponent')) do
        local id = c:get_address()
        local v = f.fxv[id]
        if v == nil then
            local _, beam = fxSystem(c)
            local okP, par = false, nil
            if beam then okP, par = pcall(function() return c:GetAttachParent() end) end
            v = beam and okP and par and par:get_address() == rootId and fxFree(c) or false
            if v then
                local okA, abs = pcall(function() return c:IsUsingAbsoluteLocation() end)
                v = { abs = okA and abs == true }
            end
            f.fxv[id] = v
        end
        if v and not fh.others[id] and not fh.failedParts[id] then
            fh.others[id] = { pawn = o, comp = c, fx = true, abs = v.abs, pawnId = pawnId }
        end
    end
end
-- the vehicles near you; what was found on each is kept (per vehicle, until yours changes). At most
-- `budget` vehicles are looked into per call - the rest on the next ticks (fh.findPending), so the race
-- start with every car near is not one long frame. A vehicle left alone is looked at again after 5 s
-- (parts load late); said in the log only when its reason changes. A vehicle found before is checked
-- against its list of parts (a part gone is never touched) - that too counts in the budget, at most once
-- in 3 s per vehicle.
local function fhCollectOthers(p, budget)
    fh.findPending = false
    if fh.broken.find then return end
    local gsC, vc = api:find_uobject('Class /Script/Engine.GameplayStatics'), V.class('Griffin.VehiclePawn')
    if not gsC or not vc then return end
    local out = {}
    local okA, errA = pcall(function() gsC:get_class_default_object():GetAllActorsOfClass(api:get_engine().GameViewport.World, vc, out) end)
    if not okA then
        fh.broken.find = tostring(errA)
        log('hit-stop: the other vehicles can not be listed, left alone from now on: '..fh.broken.find)
        return
    end
    local me, here = p:get_address(), p:K2_GetActorLocation()
    -- (the ones you can see first: ahead of you and beside you, nearest first; behind you - more than about
    -- 107 degrees off your heading - only after them. 2026-10-27, the user: "the ones behind are not
    -- needed, at most you look to the side")
    local fx, fy, fz = 0, 0, 0
    pcall(function()
        local _, v = V.pawnAndVehicle()
        local r = v.VehicleTransform.Rotation
        fx, fy, fz = rotate({ r.X, r.Y, r.Z, r.W }, 1, 0, 0)
    end)
    local near = {}
    for _, o in ipairs(out) do
        if o:get_address() ~= me then
            local l = o:K2_GetActorLocation()
            local dx, dy, dz = l.X - here.X, l.Y - here.Y, l.Z - here.Z
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 < FH_RANGE * FH_RANGE then
                local behind = (dx * fx + dy * fy + dz * fz) < -0.3 * math.sqrt(d2)
                near[#near + 1] = { o = o, d2 = d2, behind = behind }
            end
        end
    end
    table.sort(near, function(a, b)
        if a.behind ~= b.behind then return not a.behind end
        return a.d2 < b.d2
    end)
    local made = 0
    for i = 1, math.min(#near, FH_MAX) do
        local o = near[i].o
        local id = o:get_address()
        pawnKnown(o)                               -- (the engine just gave it: it is there)
        local f = fh.found[id]
        if f and not f.recs and V.t - (f.at or 0) >= 5 then f = nil end            -- (left alone: looked at again)
        local stale = f and f.recs and V.t - (f.seenAt or 0) >= 3
        local most = budget or FH_MAX
        if (stale or not f) and made >= most then
            fh.findPending, f = true, nil                                            -- (next tick)
        else
            if stale then
                made = made + 1
                f.seenAt = V.t
                -- (a part gone: dropped whole, so it is looked into again from the start - what came instead
                -- drawn behind, what is gone never touched)
                if partGone(f.recs, partsOf(o)) then f = nil; fh.prep[id], fh.found[id] = nil, nil end
            end
            if not f and made < most then
                made = made + 1
                local okP, ready = pcall(fhPrepare, o, id)
                if okP and not ready then
                    fh.findPending = true                                            -- (its checks go on next tick)
                else
                    local was = fh.found[id]
                    local ok, recs, why = pcall(fhOther, o)
                    f = { recs = ok and recs or nil, pod = ok and recs and recs.pod or false, why = ok and tostring(why) or tostring(recs), at = V.t, seenAt = V.t }
                    if f.recs then markHad(f.recs, partsOf(o)) end
                    fh.found[id], fh.prep[id] = f, nil
                    if V.fhOpt.log and not f.recs and not (was and was.why == f.why) then
                        log('hit-stop: another vehicle left alone ('..o:get_class():get_fname():to_string()..'): '..f.why)
                    end
                end
            elseif not f then
                fh.findPending = true
            end
        end
        if f then
            local any, mine = false, car.comp and car.comp:get_address()
            for _, r in ipairs(f.recs or {}) do
                -- (never a part of yours: that one is moved as your body)
                local a = r.comp:get_address()
                if fh.failedParts[a] then r.failed = true end          -- (failed before it was looked into again)
                if not r.failed and a ~= mine then r.pawnId, any = id, true; fh.others[a] = r end
            end
            if any then
                fh.lags[id] = fh.lags[id] or { pawn = o, acc = { 0, 0, 0 }, cur = { 0, 0, 0 } }
                if i <= FH_FX_NEAR then
                    fh.fxNear[id] = o                  -- (their effects slowed too: the nearest few)
                    if f.pod then pcall(fhLooseFxOf, o, id, f) end
                end
            else fh.leftSet[id] = true end
        end
    end
end
-- the others (and your podracer's other parts): drawn behind right before the frame is drawn, like your
-- body. The resting place is where the game has it now (put back before its tick: fhUndo). A part that
-- fails is put back and left alone from then on.
fhMoveOthers = function()
    local t0 = clock()
    local aliveOf, turnOf = {}, {}
    fh.fxNow = fh.fxNow or {}
    local fxNow = fh.fxNow
    for id, r in pairs(fh.others) do
        local L = r.mine and fh.ownLag or (fh.lags[r.pawnId] and fh.lags[r.pawnId].lag)
        if L and (r.mine or V.fhOpt.others) then
            local here = aliveOf[r.pawn]
            if here == nil then here = pawnAlive(r.pawn); aliveOf[r.pawn] = here end
            if here and r.fx then
                fxNow[r.pawn] = fxNow[r.pawn] or fhFxHere(r.pawn)
                here = fxNow[r.pawn][id] == true
            end
            if not here then
                fh.others[id] = nil
            elseif L[1] * L[1] + L[2] * L[2] + L[3] * L[3] >= 0.25 then     -- (half a centimetre or less: left as it is)
                local ok, err = pcall(function()
                    local l = r.comp.RelativeLocation
                    if not r.base or not r.last or not at(l, r.last) then r.base = { l.X, l.Y, l.Z } end
                    local lx, ly, lz = L[1], L[2], L[3]
                    if not r.abs then
                        if r.parent == nil then r.parent = r.comp:GetAttachParent() or false end
                        local par = r.parent
                        if par then
                            local pa = par:get_address()
                            local pq = turnOf[pa]
                            if pq == nil then pq = V.quat(par:K2_GetComponentToWorld().Rotation) or false; turnOf[pa] = pq end
                            if pq then lx, ly, lz = unrotate(pq, lx, ly, lz) end
                        end
                    end
                    setLoc(r, r.base[1] + lx, r.base[2] + ly, r.base[3] + lz)
                end)
                if ok then
                    r.moved, r.ever, fh.applied = true, true, true
                else
                    r.failed, fh.others[id], fh.failedParts[id] = true, nil, true
                    log('hit-stop: a part left alone from now on ('..tostring(err)..')')
                    if r.base then pcall(function() setLoc(r, r.base[1], r.base[2], r.base[3]) end) end
                end
            end
        end
    end
    costAdd('draw', t0)
end
-- first thing in the tick, before the game's own: what was drawn behind goes back where the game had it
-- (unless the game placed it itself since), so the game never works with a moved part
local function fhUndo()
    car.undone = nil
    fh.fxNow = {}                              -- (the vehicles' effect lists, read once this frame)
    -- (a new frame: the last one's cost done)
    local c = fh.cost
    if c and c.cur > 0 then c.frames, c.most, c.cur = c.frames + 1, math.max(c.most, c.cur), 0 end
    if not fh.applied and not car.lagged then return end
    local t0 = clock()
    fh.applied = false
    local fxNow, aliveOf = fh.fxNow, {}
    for id, r in pairs(fh.others) do
        if r.moved and r.base and r.last then
            local here = aliveOf[r.pawn]
            if here == nil then here = pawnAlive(r.pawn); aliveOf[r.pawn] = here end
            if here and r.fx then
                fxNow[r.pawn] = fxNow[r.pawn] or fhFxHere(r.pawn)
                here = fxNow[r.pawn][id] == true
            end
            if here and at(r.comp.RelativeLocation, r.last) then setLoc(r, r.base[1], r.base[2], r.base[3]) end
            r.moved = false                    -- (put back - or gone, or placed by the game since)
        end
    end
    if car.lagged and car.comp and car.base and car.last and at(car.comp.RelativeLocation, car.last) then
        local b = car.base
        carSet(b[1], b[2], b[3], b[4], b[5], b[6])
        car.undone = car.drawOff                   -- (the seat drawn last frame is this far off now: body follow)
    end
    car.lagged = false
    costAdd('undo', t0)
end
-- the effects of the vehicles slowed (fh.fxPawns): at each step taken from each vehicle's own list, so
-- one that just started is slowed too and one that is gone is never touched - UEVR's object check did
-- not know most of them (2026-10-27: 13 of 17, the new ones least of all). Their own speed is the base.
-- The first failure stops it for the session (said in the log and the menu), those already slowed back.
local function fhEachFx(fn, only)
    for _, pw in ipairs(only and { only } or fh.fxPawns or {}) do
        if pawnAlive(pw) then
            for _, c in ipairs(V.components(pw, 'Niagara.NiagaraComponent')) do
                if fn(c, c:get_address()) == false then return false end
            end
        end
    end
    return true
end
-- one vehicle's effects (pw) to speed s; back: only those slowed (to the game's speed)
local function fhSetFx(s, back, pw)
    if fh.broken.fx then return end
    local failed = nil
    fhEachFx(function(c, id)
        local f = fh.fx[id]
        if not f and not back then
            local okB, b = pcall(function() return tonumber(c.CustomTimeDilation) end)
            f = { base = (okB and b and b > 0) and b or 1 }
            fh.fx[id] = f
        end
        if not f or (back and not f.set) then return end
        local ok, err = pcall(function() c:SetCustomTimeDilation(f.base * s) end)
        if not ok then failed = { id = id, err = tostring(err) }; return false end
        f.set = s ~= 1
        if f.set and not f.ever then f.ever = true; fh.fxN = (fh.fxN or 0) + 1 end
    end, pw)
    if failed then
        fh.broken.fx = failed.err
        log('hit-stop: effects can not be slowed, left alone from now on: '..fh.broken.fx)
        -- (those already slowed: back once, stopping at the first that fails)
        fhEachFx(function(c, id)
            local g = fh.fx[id]
            if id ~= failed.id and g and g.set then
                if not pcall(function() c:SetCustomTimeDilation(g.base) end) then return false end
                g.set = false
            end
        end)
        return
    end
    if pw then fh.fxAt[pw] = s end
end
-- The parts of your vehicle not drawn behind, said once per vehicle at the end of its first
-- hit-stop: a part left at its real place looks like it runs ahead and comes back (2026-10-27, the user
-- saw one on a podracer's engine). Name (class) < what it hangs on, [abs] if it is placed in the world;
-- effects counted apart.
local function fhLeftParts(p)
    local moved = {}
    if car.comp and fh.ownOk then moved[car.comp:get_address()] = true end
    for _, r in pairs(fh.others) do if r.mine and r.moved then moved[r.comp:get_address()] = true end end
    local list, fx, n = {}, 0, 0
    for _, c in ipairs(V.components(p, 'Engine.SceneComponent')) do
        local x, covered = c, false
        for _ = 1, 24 do
            if not x then break end
            if moved[x:get_address()] then covered = true; break end
            local ok, up = pcall(function() return x:GetAttachParent() end)
            x = ok and up or nil
        end
        if not covered then
            n = n + 1
            local okC, cls = pcall(function() return c:get_class():get_fname():to_string() end)
            cls = okC and cls or '?'
            if cls:find('Niagara', 1, true) then
                fx = fx + 1
            elseif #list < 40 then
                local okP, par = pcall(function() local u = c:GetAttachParent(); return u and u:get_fname():to_string() or 'nothing' end)
                local okA, abs = pcall(function() return c:IsUsingAbsoluteLocation() end)
                list[#list + 1] = c:get_fname():to_string()..' ('..cls..') < '..(okP and par or '?')..((okA and abs == true) and ' [abs]' or '')
            end
        end
    end
    log('hit-stop: your parts not drawn behind ('..n..', '..fx..' of them effects): '..table.concat(list, ', '))
end
hsEnd = function()
    if not fh.active then return end
    -- (once per vehicle: what of it was not drawn behind)
    if V.fhOpt.log and fh.ownOk and not fh.told.leftParts then
        fh.told.leftParts = true
        local p = V.pawnAndVehicle()
        if p then pcall(fhLeftParts, p) end
    end
    fh.active = false
    fh.D, fh.Dpeak, fh.ownLag, fh.ownCur, fh.ownAcc, fh.ownPeak = 0, 0, nil, nil, nil, nil
    fh.freeze, fh.freezeL, fh.freezeShown, fh.findPending = 0, nil, nil, false
    local moved, fxNow, nParts, nFx = {}, {}, 0, 0
    for id, r in pairs(fh.others) do
        if r.ever and not r.mine and r.pawnId then moved[r.pawnId] = true end
        if r.ever then nParts = nParts + 1; if r.fx then nFx = nFx + 1 end end
        if r.moved and r.base and r.last then
            pcall(function()
                local here = pawnAlive(r.pawn)
                if here and r.fx then
                    fxNow[r.pawn] = fxNow[r.pawn] or fhFxHere(r.pawn)
                    here = fxNow[r.pawn][id] == true
                end
                if here and at(r.comp.RelativeLocation, r.last) then setLoc(r, r.base[1], r.base[2], r.base[3]) end   -- (else the game placed it since)
            end)
        end
        r.base, r.last, r.moved, r.ever = nil, nil, false, false
    end
    fh.others, fh.lags, fh.applied, fh.fxNear = {}, {}, false, {}
    local nMoved, nLeft = 0, 0
    for _ in pairs(moved) do nMoved = nMoved + 1 end
    for _ in pairs(fh.leftSet or {}) do nLeft = nLeft + 1 end
    for _, pw in ipairs(fh.fxPawns or {}) do
        if fh.fxAt[pw] and fh.fxAt[pw] ~= 1 then pcall(fhSetFx, 1, true, pw) end
    end
    fh.fx, fh.fxS, fh.fxPawns, fh.fxAt = {}, nil, {}, {}
    -- (the menu: what it did this time; the reasons are fixed texts, put in the player's language there)
    local i = fh.info
    i.used, i.mph = true, fh.mph
    i.ownCm = fh.ownOk and math.floor(fh.lagMost + 0.5) or nil
    i.ownWhy = (not fh.ownOk) and (fh.ownWhy or CANT) or nil
    i.moved, i.left = nMoved, nLeft
    i.othersWhy = (not V.fhOpt.others and 'turned off') or ((fh.othersFailed or fh.broken.find or fh.broken.velocity) and 'stopped after an error (see the log)') or nil
    i.fxN = fh.fxN or 0
    i.fxWhy = (not V.fhOpt.fx and 'turned off') or (fh.broken.fx and 'stopped after an error (see the log)') or nil
    if not V.fhOpt.log then return end
    local c, cost = fh.cost, ''
    if c then
        local n = math.max(1, c.frames)
        cost = string.format('; cost: %.1f ms a frame (put back %.1f, tick %.1f, move %.1f), most %.0f ms, start %.0f ms; %d parts moved (%d effects)',
            1000 * (c.undo + c.tick + c.draw) / n, 1000 * c.undo / n, 1000 * c.tick / n, 1000 * c.draw / n, 1000 * c.most, 1000 * c.start, nParts, nFx)
    end
    log(string.format('hit-stop at %.0f mph: you %s; others %s; effects %s', fh.mph,
        i.ownCm and ('drawn behind, up to '..i.ownCm..' cm') or ('left alone: '..tostring(i.ownWhy)),
        i.othersWhy or (nMoved..' drawn behind, '..nLeft..' left alone'), i.fxWhy or (i.fxN..' slowed'))..cost)
end
hsStart = function(strength)
    local t0 = clock()
    if fh.broken.undo or fh.broken.start then
        if not fh.told.undo then fh.told.undo = true; log('hit-stop: stopped after an error, nothing slows (see above)') end
        return
    end
    local p, v = V.pawnAndVehicle()
    if not p or not v then return end
    local id = p:get_address()
    if id ~= car.pawn then carNewPawn(id) end
    local slow = math.max(0.1, 1 - 0.75 * math.min(1, strength))
    local hold = math.max(0.02, tonumber(cfg.hitstopTime) or 0.164)
    if fh.active then
        -- (another boost while it runs: the stronger slow and the longer hold stay; each way back carries
        -- on from where it is now; the shake keeps holding where it held)
        if fh.t < fh.hold then slow, hold = math.min(slow, fh.slow), math.max(hold, fh.hold - fh.t)
        elseif not fh.sling and fh.t < fh.hold + K.HS_RAMP then slow = math.min(slow, fh.slow + (1 - fh.slow) * ((fh.t - fh.hold) / K.HS_RAMP)) end
        -- (the shake hold: in the hold it holds on; in the ramp from what is shown now; after it, anew)
        if fh.freeze <= 0 then fh.freezeL = nil elseif fh.freeze < 1 then fh.freezeL = fh.freezeShown end
        if fh.ownCur then fh.ownAcc = { fh.ownCur[1], fh.ownCur[2], fh.ownCur[3] } end
        fh.ownPeak = nil
        for _, L in pairs(fh.lags) do L.acc, L.peak = { L.cur[1], L.cur[2], L.cur[3] }, nil end
    else
        fh.D, fh.Dpeak, fh.lagMost, fh.fxN = 0, 0, 0, 0
        fh.ownAcc, fh.ownPeak, fh.ownCur, fh.ownLag = { 0, 0, 0 }, nil, nil, nil
        fh.others, fh.lags, fh.leftSet, fh.fx, fh.fxS, fh.fxNear = {}, {}, {}, {}, nil, {}
        fh.cost = V.fhOpt.log and { undo = 0, tick = 0, draw = 0, start = 0, frames = 0, most = 0, cur = 0 } or nil
        fh.fxAt = {}
        if fh.warm then fh.warm.raced = true end     -- (the looking ahead at the others ends here)
        fh.freezeL, fh.freezeShown, fh.findPending = nil, nil, false
        fh.sling = V.fhOpt.sling ~= false
        fh.mph = tonumber(v.SpeedMPH) or 0
        pawnKnown(p)
        fh.offline = V.fhOpt.pods == true and (V.fhOpt.podsOnline or fhOffline())
        if V.fhOpt.pods and not fh.offline and not fh.told.online then
            fh.told.online = true
            log('hit-stop: Podracers too is offline only for now, and this is not offline (or can not be told): podracers left alone')
        end
        local key = (not V.fhOpt.pods and 'plain') or (fh.offline and 'pods') or 'online'
        if fh.foundKey ~= key then fh.found, fh.foundKey, fh.prep = {}, key, {} end
        if V.fhOpt.view then fh.ownOk, fh.ownWhy = fhOwn(p) else fh.ownOk, fh.ownWhy = false, 'turned off' end
    end
    fh.active, fh.t, fh.slow, fh.hold, fh.C, fh.cut = true, 0, slow, hold, nil, false
    fh.freeze = V.fhOpt.freeze and 1 or 0
    if V.fhOpt.others and not fh.othersFailed then
        local ok, err = pcall(fhCollectOthers, p, 2)
        if not ok then fh.othersFailed = tostring(err); log('hit-stop: the other vehicles left alone from now on: '..fh.othersFailed) end
    end
    -- (the effects: yours and those of the nearest few vehicles drawn behind)
    fh.fxPawns = { p }
    for _, o in pairs(fh.fxNear) do fh.fxPawns[#fh.fxPawns + 1] = o end
    if fh.cost then fh.cost.start = fh.cost.start + (clock() - t0) end
end
-- each tick: how slow it looks now, how far behind, the effects, the shake hold, each way back
function V.hitstopTick(dt)
    if not fh.active then return end
    local t0 = clock()
    if not V.cfg.hitstop or not S.anchor or S.yielding() then hsEnd(); return end
    -- (the pause menu: the world stands still, so does this - it goes on afterwards)
    if st.gateWhy == 'paused' then return end
    fh.t = fh.t + dt
    local d, R = fh.hold, K.HS_RAMP
    local p, v = V.pawnAndVehicle()
    local s, slowing = 1, false
    if fh.sling then
        -- Right after the stall (fhSling, 2026-10-27, the user: "not stall, normal, then catch up - stall
        -- and catch up at once: more natural, and the vehicle feels fast"): after the hold what you see goes
        -- straight on from the slow speed past the game's, catches up and settles - one move, a slingshot.
        -- D goes on from where the hold left it as a cubic: its slope (1 - slow) carried on, so the speed
        -- never jumps, down to 0 with no slope after fhCatch.
        if fh.t < d then
            s, slowing = fh.slow, true
            fh.D = fh.D + (1 - s) * dt
            fh.Dpeak = fh.D
            -- (as far back as it can go - where the farthest starts easing it off, 70 % of it - the stall ends
            -- and the catch-up starts at once: held there it would look like normal speed and the catch-up
            -- like a second hit. 2026-10-27, Myth: afterburner 1.0 for 0.4 s at 430 mph wants 60 m, 15 m
            -- were reached in 0.1 s. The catch-up's cubic first goes on back a little more - at most
            -- 4/27 x its time x (1 - slow) of time - so that much is kept free.)
            local c = fh.ownCur
            if c and v then
                local u = v.Velocity
                local sp = math.sqrt((tonumber(u.X) or 0) ^ 2 + (tonumber(u.Y) or 0) ^ 2 + (tonumber(u.Z) or 0) ^ 2)
                local more = sp * (4 / 27) * math.max(0.1, tonumber(V.fhOpt.catch) or 0.35) * (1 - fh.slow)
                if math.sqrt(c[1] * c[1] + c[2] * c[2] + c[3] * c[3]) + more >= 0.7 * math.max(0, tonumber(V.fhOpt.maxLag) or 1500) then
                    fh.hold, fh.cut = fh.t, true
                end
            end
        else
            if not fh.C then fh.C, fh.D0, fh.m0 = math.max(0.1, tonumber(V.fhOpt.catch) or 0.35), fh.D, 1 - fh.slow end
            local T, u = fh.C, math.min(1, (fh.t - d) / fh.C)
            local u2, u3 = u * u, u * u * u
            fh.D = math.max(0, fh.D0 * (2 * u3 - 3 * u2 + 1) + T * fh.m0 * (u3 - 2 * u2 + u))
            -- (how fast it looks now: 1 - D'; the effects follow it back up to the game's speed)
            local dD = fh.D0 * (6 * u2 - 6 * u) / T + fh.m0 * (3 * u2 - 4 * u + 1)
            s = math.max(fh.slow, math.min(1, 1 - dD))
        end
    else
    if fh.t < d then s = fh.slow elseif fh.t < d + R then s = fh.slow + (1 - fh.slow) * ((fh.t - d) / R) end
    slowing = fh.t <= d + R
    if slowing then
        fh.D = fh.D + (1 - s) * dt
        fh.Dpeak = fh.D
    else
        -- (the catch-up's time, set once as it starts: at least fhCatch, and long enough that what you see
        -- never runs more than fhCatchMax in 100 faster than the game - smoothstep's top speed is 1.5 x
        -- its average. 2026-10-27, the user: a short one (0.35 s, up to 1.35 x) felt like "a second
        -- hit-stop half a beat later". Taken from how far you were really drawn behind: the farthest may
        -- have eased it off.)
        if not fh.C then
            local behind = fh.Dpeak
            if fh.ownOk and fh.ownLag and v then
                local u, l = v.Velocity, fh.ownLag
                local sp = math.sqrt((tonumber(u.X) or 0) ^ 2 + (tonumber(u.Y) or 0) ^ 2 + (tonumber(u.Z) or 0) ^ 2)
                if sp > 100 then behind = math.min(behind, math.sqrt(l[1] * l[1] + l[2] * l[2] + l[3] * l[3]) / sp) end
            end
            local most = math.max(0.01, (tonumber(V.fhOpt.catchMax) or 8) / 100)
            fh.C = math.max(math.max(0.05, tonumber(V.fhOpt.catch) or 0.35), 1.5 * behind / most)
        end
        local x = math.min(1, (fh.t - d - R) / fh.C)
        fh.D = fh.Dpeak * (1 - x * x * (3 - 2 * x))
    end
    end
    -- (after the slowing: how much of each way back is left - right after the stall it first grows on)
    local left = fh.Dpeak > 0 and fh.D / fh.Dpeak or 0
    fh.freeze = (not V.fhOpt.freeze and 0) or (fh.t < d and 1) or (fh.t < d + R and 1 - (fh.t - d) / R) or 0
    if V.fhOpt.fx and not fh.broken.fx then
        if fh.fxS == nil or math.abs(s - fh.fxS) >= 0.2 or (s == 1 and fh.fxS ~= 1) then fh.fxS = s end
        -- (one vehicle's effects a tick, yours first: no frame touches all of them)
        for _, pw in ipairs(fh.fxPawns) do
            if fh.fxAt[pw] ~= fh.fxS then fhSetFx(fh.fxS, false, pw); break end
        end
    end
    local k = (1 - s) * dt
    -- (the vehicles not looked into yet: a few more each tick while it slows; each starts from here)
    if not slowing then fh.findPending = false end
    if fh.findPending and p and V.fhOpt.others and not fh.othersFailed then
        local before = {}
        for id in pairs(fh.lags) do before[id] = true end
        local okC, errC = pcall(fhCollectOthers, p, 2)
        if not okC then fh.othersFailed = tostring(errC); log('hit-stop: the other vehicles left alone from now on: '..fh.othersFailed) end
        local fresh = 0
        for id, o in pairs(fh.fxNear) do
            if not before[id] then fh.fxPawns[#fh.fxPawns + 1] = o; fresh = fresh + 1 end
        end
        if fresh > 0 then fh.fxS = nil end             -- (their effects slowed at once too)
    end
    -- yours
    if fh.ownOk and v then
        local a = fh.ownAcc
        if slowing then
            local vel = v.Velocity
            a[1], a[2], a[3] = a[1] - (tonumber(vel.X) or 0) * k, a[2] - (tonumber(vel.Y) or 0) * k, a[3] - (tonumber(vel.Z) or 0) * k
            fh.ownPeak, fh.ownCur = nil, { a[1], a[2], a[3] }
        else
            fh.ownPeak = fh.ownPeak or { a[1], a[2], a[3] }
            local pk = fh.ownPeak
            fh.ownCur = { pk[1] * left, pk[2] * left, pk[3] * left }
        end
        local x, y, z = capLag(fh.ownCur[1], fh.ownCur[2], fh.ownCur[3])
        fh.ownLag = { x, y, z }
        fh.lagMost = math.max(fh.lagMost, math.sqrt(x * x + y * y + z * z))
    else
        fh.ownLag = nil
    end
    -- the others' (their velocity read once per vehicle; the first failure stops reading it)
    for _, L in pairs(fh.lags) do
        if slowing then
            if not fh.broken.velocity and pawnAlive(L.pawn) then
                local ok, u = pcall(function() local w = L.pawn:GetVelocity(); return { tonumber(w.X) or 0, tonumber(w.Y) or 0, tonumber(w.Z) or 0 } end)
                if ok then
                    L.acc[1], L.acc[2], L.acc[3] = L.acc[1] - u[1] * k, L.acc[2] - u[2] * k, L.acc[3] - u[3] * k
                else
                    fh.broken.velocity = tostring(u)
                    log('hit-stop: the speed of the other vehicles can not be read, they stop slowing: '..fh.broken.velocity)
                end
            end
            L.peak, L.cur = nil, { L.acc[1], L.acc[2], L.acc[3] }
        else
            L.peak = L.peak or { L.acc[1], L.acc[2], L.acc[3] }
            L.cur = { L.peak[1] * left, L.peak[2] * left, L.peak[3] * left }
        end
        local x, y, z = capLag(L.cur[1], L.cur[2], L.cur[3])
        L.lag = { x, y, z }
    end
    costAdd('tick', t0)
    if fh.C and fh.t >= d + (fh.sling and 0 or R) + fh.C then hsEnd() end
end
-- Before the first boost of a race your vehicle's parts and effects are looked into a piece at a time,
-- a small piece at a time once the cockpit is up (all of it is kept, so the boost finds it ready): the first
-- boost of each race was one long frame, 15-36 ms (2026-10-27). Then, until the first boost, the others
-- near you the same way, one a step (at the race start every car is near: the launch was 22-28 ms with
-- your vehicle ready, from them). Then nothing until the next vehicle.
local function fhWarm()
    if fh.active or not V.cfg.hitstop or not V.fhOpt.view or not S.anchor or S.yielding() then return end
    -- (only while a hit-stop can come: not with the add-on effects or the cockpit shake off, both strengths
    -- at 0, or after it stopped on an error - else it looked at the others all race for nothing)
    if not V.cfg.extras or not V.cfg.feelOn or not S.enabled or fh.broken.start or fh.broken.undo then return end
    if (tonumber(cfg.hitstop) or 0) <= 0 and (tonumber(cfg.hitstopAB) or 0) <= 0 then return end
    local p = V.pawnAndVehicle()
    if not p then return end
    local id = p:get_address()
    local w = fh.warm
    if not w or w.id ~= id then w = { id = id, step = 0, at = V.t + 0.5 }; fh.warm = w end
    if V.t < w.at then return end
    w.at = V.t + (w.done and 0 or 0.05)            -- (a piece each: yours every 0.05 s, then the others every tick)
    if id ~= car.pawn then carNewPawn(id) end
    if w.done then
        -- (the others: one looked into or checked again a step, what it set up for a boost dropped)
        if w.raced or not V.fhOpt.others or fh.othersFailed or fh.broken.find then return end
        pcall(fhCollectOthers, p, 1)
        fh.others, fh.lags, fh.leftSet, fh.fxNear, fh.findPending = {}, {}, {}, {}, false
        return
    end
    w.step = w.step + 1
    if w.step == 1 then
        if not car.comp and not car.failed and fh.ownNot ~= id then
            local ok, c, _, free = pcall(carFind, p)
            if ok and c then car.comp, car.parent, car.free = c, c:GetAttachParent(), free == true end
        end
    elseif w.step == 2 then
        if car.comp and checkPartStep(car.comp, FH_CHECK_STEP) == nil then w.step = 1 end     -- (more of it next step)
    elseif w.step == 3 then
        w.todo = (car.free and car.comp) and podParts(p, car.comp:get_address()) or {}
    elseif w.todo and #w.todo > 0 then
        if checkPartStep(w.todo[#w.todo], FH_CHECK_STEP) ~= nil then table.remove(w.todo) end   -- (a podracer's engines)
        w.step = 3
    else
        -- (all of it as a boost does - cheap now; what it set up for a boost is dropped)
        fh.offline = V.fhOpt.pods == true and (V.fhOpt.podsOnline or fhOffline())
        local key = (not V.fhOpt.pods and 'plain') or (fh.offline and 'pods') or 'online'
        if fh.foundKey ~= key then fh.found, fh.foundKey, fh.prep = {}, key, {} end
        pcall(fhOwn, p)
        fh.others, w.done = {}, true
    end
end
-- (the menu: what it did the last time)
function V.hitstopInfo() return fh.info, fh.active end

-------------------------------------------------------------------------------- hit-stop check (test)
-- 2026-10-27, the user: "check that it works the same as slowing the game did". For every hit-stop:
-- how fast your seat really moved on screen - its drawn place from one frame to the next, along the
-- vehicle's velocity, against real time - next to what slowing the game does (the game at s(t)).
-- One line in the log at its end. It should look the same through the hold and the ramp, then faster
-- while it catches up (slowing the game loses that time instead).
-- Also when the cockpit's lunge at you came (the eye against the cockpit, forward / back): 2026-10-27,
-- the user: "slowing the game, the vehicle comes at me at once; this way half a beat late" - slowing the
-- game never held the cockpit shake (it runs on real time), this held it with fhFreeze (now off).
-- Only reads what is there already (the drawn seat, the vehicle's velocity): no game calls of its own.
local hc = { on = false }
local function hcCurve(t, slow, hold)
    local R = K.HS_RAMP
    if t < hold then return slow elseif t < hold + R then return slow + (1 - slow) * ((t - hold) / R) end
    return 1
end
local function hcSeat()
    local s = S.renderSeat
    return s and s.origin and { s.origin[1], s.origin[2], s.origin[3] } or nil
end
local function hcVel()
    local _, v = V.pawnAndVehicle()
    local u = v and v.Velocity
    if not u then return nil end
    return { tonumber(u.X) or 0, tonumber(u.Y) or 0, tonumber(u.Z) or 0 }
end
-- (a time line: the value nearest to each of these moments after it started)
local HC_MARKS = { 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1.0, 1.5 }
local function hcLine(list, key, fmt)
    local out = {}
    for _, m in ipairs(HC_MARKS) do
        local best, bd = nil, 0.03
        for _, x in ipairs(list) do
            local d = math.abs(x.t - m)
            if d < bd then best, bd = x[key], d end
        end
        out[#out + 1] = best and string.format(fmt, best) or '-'
    end
    return table.concat(out, '/')
end
local function checkReport(cut)
    hc.on = false
    -- (the stall as it was really shown: cut short where it could go no further back; slower than the
    -- game anywhere = behind, faster = given back)
    local R, hold, slow = K.HS_RAMP, hc.cut or hc.hold, hc.slow
    local hN, hS, hT, rN, rS, rT, behind, given, top = 0, 0, 0, 0, 0, 0, 0, 0, 0
    for _, x in ipairs(hc.rows) do
        if x.t < hold then hN, hS, hT = hN + 1, hS + x.r, hT + x.want
        elseif x.t < hold + R then rN, rS, rT = rN + 1, rS + x.r, rT + x.want end
        if x.t >= hold then top = math.max(top, x.r) end
        if x.r < 1 then behind = behind + (1 - x.r) * x.dt else given = given + (x.r - 1) * x.dt end
    end
    local function avg(s, n) return n > 0 and string.format('%.2f', s / n) or '-' end
    local text = string.format('hit-stop check (%s) at %.0f mph, %d frames: hold looked %s (slowing the game: %s), ramp %s (%s); %.3f s behind (slowing the game: %.3f)',
        hc.kind, hc.mph, #hc.rows, avg(hS, hN), avg(hT, hN), avg(rS, rN), avg(rT, rN), behind, (1 - slow) * (hc.hold + R / 2))
    if hc.kind == 'picture' then
        text = text..string.format('; then caught up%s in %.2f s: looked up to %.2f, %.3f s given back (the game itself: never behind)',
            V.fhOpt.sling ~= false and ' right after the stall' or '', hc.catch or 0, top, given)
        if hc.raw - hc.drawn > 1 then text = text..string.format('; eased off: drawn %.0f of %.0f cm behind', hc.drawn, hc.raw) end
        if hc.why then text = text..'; your body: '..hc.why end
        if hc.cut then text = text..string.format('; the stall cut at %.2f s (as far back as it goes)', hc.cut) end
        text = text..'; your body drawn behind in '..hc.bodyN..' of '..hc.drawnN..' frames'
    else
        text = text..'; lost for good'
    end
    -- (the cockpit's lunge: when it got half way, and its most)
    local pk, half = math.abs(hc.fPeak), nil
    for _, x in ipairs(hc.fw) do if not half and math.abs(x.f) >= 0.5 * pk then half = x.t end end
    if pk < 0.3 or not half then text = text..'; the cockpit: no lunge'
    else text = text..string.format('; the cockpit came at you: half way at %.2f s, most %.1f cm at %.2f s', half, hc.fPeak, hc.fPeakT) end
    if hc.kind == 'picture' then text = text..(V.fhOpt.freeze and ' (its shake held)' or ' (its shake not held)') end
    -- (at 0.05 .. 0.5 s: how fast your seat looked, and the cockpit forward (+) / back (-) in cm)
    text = text..'; at '..table.concat(HC_MARKS, '/')..' s: seat speed '..hcLine(hc.rows, 'r', '%.2f')..', the cockpit '..hcLine(hc.fw, 'f', '%.1f')
    if hc.miss > 0 then text = text..'; '..hc.miss..' frames without the cockpit view' end
    text = text..string.format('; frames: %d, late %d (over 1.4 x the usual %.1f ms), longest %.1f ms', hc.frames, hc.late, 1000 * hc.usual, 1000 * hc.longest)
    if cut then text = text..'; cut short by '..cut end
    log(text)
end
local hcDt = 0                             -- (this tick's time: the game's next step)
-- (the frames: how long one usually takes outside a hit-stop, and during it how many came late - over
-- 1.4 x that - and the longest: both ways side by side, 2026-10-27, the user: "this way still drops
-- frames more than slowing the game")
local hcUsual = nil
checkStart = function(kind, slow, hold, why)
    if hc.on then checkReport('another boost') end
    hc = { on = true, kind = kind, slow = slow, hold = hold, why = why, mph = V.feelInfo.mph or 0, t = 0, rows = {}, miss = 0,
        usual = hcUsual or (1 / 90), frames = 0, late = 0, longest = 0,
        raw = 0, drawn = 0, bodyN = 0, drawnN = 0, prev = hcSeat(), vel = hcVel(), dtNext = hcDt, fwd0 = V.feelFwd or 0, fw = {}, fPeak = 0, fPeakT = 0 }
end
-- first thing each tick: the seat drawn last frame against the one before, over the time the game
-- stepped in between
local function checkTick(dt)
    hcDt = dt
    if not hc.on then
        if dt > 0 and dt < 0.1 then hcUsual = hcUsual and hcUsual + (dt - hcUsual) * 0.05 or dt end
        return
    end
    hc.frames, hc.longest = hc.frames + 1, math.max(hc.longest, dt)
    if dt > 1.4 * hc.usual then hc.late = hc.late + 1 end
    local pos, vel, d = hcSeat(), hcVel(), hc.dtNext or 0
    if d > 0 then
        hc.t = hc.t + d
        local a, b = hc.vel, vel
        if pos and hc.prev and a and b then
            local vx, vy, vz = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2
            local sp2 = vx * vx + vy * vy + vz * vz
            if sp2 > 500 * 500 then                    -- (above 5 m/s: standing still says nothing)
                local r = ((pos[1] - hc.prev[1]) * vx + (pos[2] - hc.prev[2]) * vy + (pos[3] - hc.prev[3]) * vz) / (sp2 * d)
                local tm = hc.t - d / 2
                hc.rows[#hc.rows + 1] = { t = tm, r = r, dt = d, want = hcCurve(tm, hc.slow, hc.hold) }
            end
        elseif not pos then
            hc.miss = hc.miss + 1
        end
        -- (the eye against the cockpit as drawn last frame, from where it was before)
        local f = (tonumber(V.feelFwd) or 0) - hc.fwd0
        hc.fw[#hc.fw + 1] = { t = hc.t, f = f }
        if math.abs(f) > math.abs(hc.fPeak) then hc.fPeak, hc.fPeakT = f, hc.t end
    end
    hc.prev, hc.vel, hc.dtNext = pos, vel, dt
    -- (how far behind it should be and how far it was drawn - the farthest eases it off)
    if hc.kind == 'picture' and fh.active then
        hc.drawnN = hc.drawnN + 1
        if fh.C then hc.catch = fh.C end
        if fh.cut then hc.cut = fh.hold end
        if car.lagged then hc.bodyN = hc.bodyN + 1 end           -- (drawn behind last frame: the undo comes after this)
    end
    if hc.kind == 'picture' and fh.active and fh.ownCur and fh.ownLag then
        local c, l = fh.ownCur, fh.ownLag
        hc.raw = math.max(hc.raw, math.sqrt(c[1] * c[1] + c[2] * c[2] + c[3] * c[3]))
        hc.drawn = math.max(hc.drawn, math.sqrt(l[1] * l[1] + l[2] * l[2] + l[3] * l[3]))
    end
    local catch = hc.kind == 'picture' and (hc.catch or math.max(0.05, tonumber(V.fhOpt.catch) or 0.35)) or 0
    if hc.t >= math.max(0.6, hc.hold + K.HS_RAMP + catch + 0.05) then checkReport() end
end

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
    -- (the seat is the one drawn last frame; the hit-stop moved the body for that frame and put it
    -- back before this tick, so the chest is read where it really is - that move taken off the seat too,
    -- or the body follow went wrong by metres during it, 2026-10-27, the user: "in jumps the view
    -- sometimes does not follow the rider")
    local off = car.undone
    local ok, hx, hy, hz = pcall(function()
        local h = st.pilotMesh:GetSocketLocation(K.FOLLOW_BONE)
        local o, sq = seat.origin, seat.quaternion
        if off then o = { o[1] - off[1], o[2] - off[2], o[3] - off[3] } end
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
    if grounded and not inAir and not fh.active then    -- learn the resting body position on the ground (not while the hit-stop runs)
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
    local p, v = V.pawnAndVehicle()
    -- (no vehicle - the menus between races: what was found is for the old one, also if the next one
    -- comes at the same address)
    if not p and car.pawn ~= nil then reset(); carNewPawn(nil); fh.warm = nil end
    if not V.cfg.extras or not V.cfg.feelOn or not S.enabled or not S.anchor then reset(); return end
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
    elseif (fh.ownLag or (fh.active and fh.ownOk)) and not car.failed then
        -- (the hit-stop alone moves the body: no shake on it)
        carT[1], carT[2], carT[3], carTilt[1], carTilt[2] = 0, 0, 0, 0, 0
        car.q, car.want = q, true
    else
        car.want = false
        if car.moved then carStop() end
    end
    -- (the hit-stop: the cockpit's shake holds where it was (in the vehicle's axes) while time
    -- stands nearly still, and eases back over the ramp)
    if fh.active and fh.freeze > 0 then
        fh.freezeL = fh.freezeL or { lx, ly, lz }
        local a, fz = fh.freeze, fh.freezeL
        lx, ly, lz = lx + (fz[1] - lx) * a, ly + (fz[2] - ly) * a, lz + (fz[3] - lz) * a
        fh.freezeShown = { lx, ly, lz }
    elseif not fh.active then
        fh.freezeL = nil
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
    local okF, errF = pcall(V.hitstopTick, math.min(dt, 0.1))
    if not okF then log('hit-stop error: '..tostring(errF)); pcall(hsEnd) end
end)
V.onReset(function() warpStop(); pcall(hsEnd); pcall(carStop) end)
-- (the hit-stop: before anything else in the tick, what it drew behind goes back where the game had
-- it; a failure stops it for the session, said in the log and the menu)
table.insert(V.ticks, 1, { name = 'hit-stop', fn = function(dt)
    local okW, errW = pcall(fhWarm)
    if not okW then fh.warm = { id = fh.warm and fh.warm.id, done = true, raced = true, at = 0 }; if not fh.told.warm then fh.told.warm = true; log('hit-stop: looking at your vehicle ahead failed (done at the boost): '..tostring(errW)) end end
    local okC, errC = pcall(checkTick, tonumber(dt) or 0)
    if not okC then hc.on = false; if not fh.told.check then fh.told.check = true; log('hit-stop check failed: '..tostring(errC)) end end
    local ok, err = pcall(fhUndo)
    if not ok then
        fh.broken.undo, fh.info.stopped = tostring(err), true
        log('hit-stop: putting back failed, it stops: '..fh.broken.undo)
        fh.othersFailed = fh.othersFailed or fh.broken.undo
        pcall(hsEnd)
    end
end })
