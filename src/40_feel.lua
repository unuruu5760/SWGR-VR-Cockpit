-- Cockpit feel: designed, event-driven head motion on a damped spring ("head on a spring" in the
-- seat); only pitch is ever rotated (nose lift / nod). Triggers come from the game's VehicleState:
--   afterburner (AfterburnerState -> 0 Active, burned >= 0.12 s, max once per 1 s) -> forward lunge
--   ramjet (RamjetState -> 3 Active = real ignition) -> big lunge, nose lift, warp, hum + heat shudder
--   race start (IgnitionPhase 2 PerfectStart -> 3 PostPerfectStart) -> launch
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
local function T(key, base, hi, en, kr, tipEn, tipKr) V.tunable('feel', key, base, 0, hi, en, kr, tipEn, tipKr); return key end
local GROUPS = {
    engine = {
        T('idle', 0.594, 3, 'Engine idle (standing)', '공회전 (정지 중)', 'How much the cockpit trembles from the engine while you stand still (before the start). 0 = no trembling.', '멈춰 서 있을 때(출발 전 등) 엔진 때문에 콕핏이 잔잔하게 떨리는 정도. 0 = 안 떨림.'),
        T('idleRev', 1.0, 3, 'Revving with W (standing)', '정지 중 부릉 (W)', 'The heavy throb when you press W while standing still (revving before the start). 0 = no throb.', '서 있는 상태에서 W를 밟아 엔진을 부릉부릉할 때 굵게 떨리는 정도 (출발 전 공회전). 0 = 안 떨림.'),
        T('cruise', 1.041, 3, 'Engine while driving', '주행 중 엔진', 'Engine trembling while you drive. 0 = none.', '달리는 동안 엔진 때문에 잔잔하게 떨리는 정도. 0 = 안 떨림.'),
    },
    road = {
        T('road', 0.731, 3, 'Road rumble', '노면 진동', 'Fine rumble from the ground while driving: grows with speed, stops in the air. Too buzzy at high speed: lower it. 0 = none.', '땅 위를 달릴 때 바닥에서 올라오는 잔진동. 빠를수록 커지고 공중에선 없어요. 고속에서 너무 자글거리면 낮추세요. 0 = 없음.'),
        T('bumps', 0.96, 3, 'Ups and downs (terrain)', '위아래 출렁임 (지형)', 'When the track goes up and down, your head lags a little behind and bobs, like in a real vehicle. Feels floaty or sickening: lower it. 0 = the head moves exactly with the vehicle.', '길이 오르락내리락할 때 머리가 살짝 늦게 따라가며 위아래로 출렁이는 정도 (진짜 차처럼). 울렁거리거나 멀미 나면 낮추세요. 0 = 차와 똑같이 움직임.'),
    },
    motion = {
        T('accel', 0.0, 3, 'Acceleration push', '가속 쏠림', 'Your head is pushed back when you speed up and forward when you slow down. Off by default (0).', '가속하면 머리가 뒤로, 감속하면 앞으로 쏠리는 정도. 기본값은 0(꺼짐).'),
        T('corner', 0.2, 3, 'Corner push', '코너 쏠림', 'Your head is pushed to the outside in corners. Higher = bigger sway in turns. 0 = none.', '코너를 돌 때 머리가 바깥쪽으로 쏠리는 정도. 높을수록 코너에서 크게 휘청. 0 = 없음.'),
        T('drift', 3.0, 3, 'Drift rumble', '드리프트 떨림', 'The cockpit rattles while you drift (Space). 0 = none.', '드리프트(스페이스바)하는 동안 콕핏이 드르륵 떨리는 정도. 0 = 없음.'),
        T('draft', 2.334, 3, 'Slipstream buffeting', '슬립스트림 난기류', 'Right behind another racer (slipstream) the air makes you sway left and right. 0 = none.', '다른 레이서 바로 뒤(슬립스트림)에 붙었을 때 공기 때문에 좌우로 휘청이는 정도. 0 = 없음.'),
    },
    boost = {
        T('afterburner', 1.427, 3, 'Afterburner', '애프터버너', 'Afterburner (Shift): how hard the view lunges forward when it fires, and the hum / shaking while it burns. 0 = no afterburner effect.', '애프터버너(Shift)를 켤 때 시점이 앞으로 튀어나가는 돌진과, 켜진 동안의 웅웅·흔들림 세기. 0 = 애프터버너 때 아무 연출 없음.'),
        T('ramjet', 2.466, 3, 'Ramjet', '램젯', 'Ramjet (C): the big forward lunge and long rumble when it ignites. 0 = no ramjet lunge / rumble.', '램젯(C)이 점화될 때 크게 앞으로 튀어나가고 길게 우르릉 울리는 세기. 0 = 램젯 때 돌진·울림 없음.'),
        T('launch', 1.0, 3, 'Race start launch', '출발 런치', 'The forward lunge at the moment the race starts, bigger with a perfect start. 0 = no start lunge.', '레이스 출발 순간 앞으로 튀어나가는 세기. 퍼펙트 스타트일수록 크게. 0 = 출발 연출 없음.'),
        T('nod', 3.0, 3, 'Nose lift', '기수 들림', 'On boosts the view tilts up a little (the nose lifts), on landings it nods down. 0 = the view angle never changes (only the position moves).', '부스터 때 시점이 살짝 위로 들리고(차 앞이 들리는 느낌), 착지 때 아래로 꾸벅하는 정도. 0 = 시점 각도는 안 바뀜 (위치만 움직임).'),
        T('lowHum', 1.013, 3, 'Low hum while boosting', '부스터 저음 웅웅', 'A deep, slow hum you feel while the ramjet / afterburner is burning. 0 = none.', '램젯·애프터버너가 켜져 있는 동안 묵직하게 웅웅 울리는 느린 떨림. 0 = 없음.'),
        T('heatShake', 1.0, 3, 'Overheating shudder', '과열 흔들림', 'Heavy shaking that grows the hotter the ramjet gets (wild at the warning stage). 0 = none.', '램젯을 오래 써서 과열될수록 커지는 굵은 흔들림 (경고 단계에서 크게 요동). 0 = 없음.'),
        T('ebrake', 0.0, 3, 'Energy brake', '에너지 브레이크', 'Thrown forward when you use the energy brake. Off by default (0).', '에너지 브레이크를 쓸 때 앞으로 쏠리는 정도. 기본값은 0(꺼짐).'),
    },
    landing = {
        T('landing', 0.562, 3, 'Landing', '착지', 'After a jump the view is pressed down when you land, then comes back up; deeper after longer jumps (never below "Lowest point below normal"). 0 = not pressed down.', '점프 후 착지할 때 시점이 아래로 쿵 눌렸다가 올라오는 깊이. 오래 날았을수록 깊게 ("착지 때 최대 깊이"보다 깊이는 안 내려가요). 0 = 안 눌림.'),
        T('impact', 1.0, 3, 'Impacts', '충돌', 'When you hit a wall or another racer the view is knocked the other way. 0 = none.', '벽이나 다른 차에 부딪힐 때 시점이 반대쪽으로 덜컥 튕기는 세기. 0 = 없음.'),
        T('landHit', 3.83, 6, 'Landing hit (thud at touchdown)', '착지 순간 쿵',
          'The short sharp hit at the moment you touch down, harder after longer jumps. Not limited by the lowest point, so it is always felt.',
          '땅에 닿는 순간의 짧고 강한 충격. 오래 날았을수록 세게. "착지 때 최대 깊이" 제한을 받지 않아서 항상 느껴져요.'),
    },
}
V.FEEL_GROUPS = { 'engine', 'road', 'motion', 'boost', 'landing' }
-- values not in a group (fine tuning only)
V.tunable('feel', 'springHz', 3.888, 1, 8, 'Spring speed (Hz)', '스프링 속도 (Hz)', 'All the shaking moves your head on a "spring". This is how fast that spring is: low = big slow sways, high = short tight jolts. Usually no need to touch it.', '흔들림 연출은 전부 머리를 "스프링"처럼 움직여요. 그 스프링의 빠르기: 낮으면 크고 느리게 출렁, 높으면 짧고 단단하게 툭. 보통은 건드릴 필요 없어요.')
V.tunable('feel', 'landHitHz', 5.5, 4, 20, 'Landing hit sharpness (Hz)', '착지 쿵 날카로움 (Hz)', 'The feel of the "Landing hit": higher = a short sharp thud, lower = a softer, longer thump.', '"착지 순간 쿵"의 느낌. 높을수록 짧고 날카로운 쿵, 낮을수록 부드럽고 길게 꿀렁.')
-- Landing head hit (menu: Cockpit shake): a landing hits your head. Moving the view's position reads in
-- VR as the vehicle moving (your real head stays still); turning the view's angle reads as your
-- head moving (like the nose lift). So at touchdown the view angle snaps down and back and wobbles
-- sideways a little, on a stiff spring of its own, on top of the usual press down.
V.tunable('feel', 'headHitPitch', 3.0, 0, 12, 'Head hit: snap down (degrees)', '머리 충격: 아래로 숙여짐 (도)',
    'How far your view snaps down at the moment you land, harder after longer jumps and with a higher "Landings and hits". 0 = no snap.',
    '착지 순간 시점이 아래로 툭 숙여지는 각도. 오래 날수록, "착지·충돌"이 높을수록 커요. 0 = 안 숙여짐.')
V.tunable('feel', 'headHitRoll', 1.5, 0, 8, 'Head hit: side wobble (degrees)', '머리 충격: 좌우 흔들림 (도)',
    'How much your view wobbles sideways at the landing (a different side each time). 0 = none.',
    '착지 순간 시점이 좌우로 흔들리는 각도 (매번 방향이 달라요). 0 = 없음.')
V.tunable('feel', 'headHitHz', 7.0, 3, 15, 'Head hit: sharpness (Hz)', '머리 충격: 빠르기 (Hz)',
    'Higher = a short sharp knock, lower = a slower, heavier sway.',
    '높을수록 짧고 날카롭게 탁, 낮을수록 느리고 묵직하게 휘청.')
V.tunable('feel', 'damping', 0.387, 0.1, 1, 'Spring damping', '스프링 감쇠', 'How quickly the spring settles: low = after a move the head bounces a few more times, high = it stops at once. Usually no need to touch it.', '스프링이 얼마나 빨리 멈추는지. 낮으면 한 번 움직인 뒤 통통 몇 번 더 튀고, 높으면 한 번에 멈춰요. 보통은 건드릴 필요 없어요.')
V.tunable('feel', 'fwdScale', 0.5, 0, 1.5, 'Forward lunges (dashboard close)', '앞으로 돌진 배율', 'How far boost and start lunges move the view forward, toward the dashboard. You end up in the dashboard (bikes): lower it. 0 = never forward (only the other movements).', '부스터·출발 돌진 때 시점이 앞(계기판 쪽)으로 다가가는 정도. 바이크처럼 계기판에 박히면 낮추세요. 0 = 앞으로는 안 감 (다른 움직임만).')
V.tunable('feel', 'landLean', 0.286, 0, 1.5, 'Lean forward on landings', '착지 때 앞으로 숙이기', 'While a landing presses the view down it also leans forward by this much. You sink into the pilot body on landings: raise it (the eye dodges forward). 0 = straight down only.', '착지로 시점이 눌릴 때 앞으로도 같이 숙이는 정도. 착지 때 조종사 몸통 속으로 들어가면 올리세요 (눈이 앞으로 피함). 0 = 아래로만 눌림.')
V.tunable('feel', 'airLift', 5.0, 0, 15, 'Rise in the air (cm)', '공중에서 시점 올리기 (cm)', 'While airborne the view rises by this much, then comes down with the landing, so the landing feels bigger. 0 = stays at the normal height in the air.', '공중에 떠 있는 동안 시점을 이만큼 살짝 올렸다가, 착지할 때 같이 내려와요 (착지 느낌이 커짐). 0 = 공중에서도 평소 높이 그대로.')
V.tunable('feel', 'lungeMax', 12.5, 5, 60, 'Lunges: farthest forward (cm)', '돌진 최대 거리 (cm)',
    'How far forward the view may go on boost and start lunges (and when it leans forward on landings). The lunge goes out to here and stays a moment, so this is how far the boost throws you. Raise it for a bigger lunge; lower it if you end up in the dashboard. 12.5 = as before.',
    '부스터·출발 돌진 때 (착지 때 앞으로 숙일 때도) 시점이 앞으로 갈 수 있는 최대 거리. 돌진은 여기까지 나가서 잠깐 머물러서, 이 값이 곧 부스터가 앞으로 밀어주는 거리예요. 더 크게 하려면 올리고, 계기판에 박히면 낮추세요. 12.5 = 예전과 같음.')
V.tunable('feel', 'landFloor', 8.29, 0, 15, 'Lowest point below normal (cm)', '착지 때 최대 깊이 (cm)', 'How far below your normal eye height a landing may press the view. You see inside the pilot body or it is too deep: lower it. Landings feel weak: raise it. 0 = never below the normal height.', '착지로 눌릴 때 평소 눈 높이보다 최대 몇 cm까지 내려갈지. 몸통 안쪽이 보이거나 너무 깊으면 낮추고, 착지가 약하게 느껴지면 올리세요. 0 = 평소 높이 아래로는 안 내려감.')
V.tunable('boost', 'hitstopStrength', 0.333, 0, 1, 'Hit-stop strength (ramjet / start)', '순간 멈칫 세기 (램젯·출발)', 'At ramjet ignition and the race start the whole game slows down for a split second (when "Hit-stop" is ticked). 1 = down to about a quarter speed. 0 = no slow-down.', '램젯 점화·레이스 출발 순간 게임 전체가 아주 잠깐 느려지는 세기 ("순간 멈칫" 체크가 켜져 있을 때). 1 = 약 4분의 1 속도까지. 0 = 안 느려짐.')
V.tunable('boost', 'hitstopAB', 0.077, 0, 1, 'Hit-stop strength (afterburner)', '순간 멈칫 세기 (애프터버너)', 'The same split-second slow-down for the afterburner lunge; very light by default. 0 = none.', '애프터버너 돌진 때의 순간 멈칫 세기. 기본은 아주 약하게. 0 = 없음.')
V.tunable('boost', 'hitstopTime', 0.164, 0.05, 0.4, 'Hit-stop length (s)', '순간 멈칫 길이 (초)', 'How long the slow-down lasts (seconds). Longer = a longer "freeze".', '순간 멈칫으로 느려져 있는 시간(초). 길수록 멈칫이 길게 느껴져요.')
V.tunable('boost', 'warpAmount', 3.0, -5, 5, 'Warp pulse strength (+ / -)', '세상 출렁 세기 (+ / -)', 'At ramjet ignition and the race start the size of the world pulses for a moment (when "Warp pulse" is ticked). Plus = the world briefly shrinks and moves away, minus = it briefly grows and rushes at you. Further from 0 = stronger. 0 = no pulse.', '램젯 점화·출발 순간 세상 크기가 잠깐 출렁이는 세기 ("세상 출렁" 체크가 켜져 있을 때). 플러스 = 세상이 잠깐 작아지며 멀어지는 쪽, 마이너스 = 세상이 잠깐 커지며 확 다가오는 쪽. 0에서 멀수록 세게. 0 = 안 출렁임.')

-- % of a group for the current vehicle: its own value if it has one, else the shared one
function V.feelPct(group) return V.pctFor(V.model, group) end
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
    JOLT_HZ = 9, JOLT_DAMP = 0.35, JOLT_TAP = 120,   -- landing: stiff spring, short tap at contact
    LAND_KICK = 90, LAND_PUSH_MIN = 6, LAND_PUSH_MAX = 14, LAND_PUSH_DECAY = 0.6, LAND_NOD = 14,
    TOUCH_DVZ = 250,                                 -- cm/s upward change in one tick = hit the ground
    NOD_KICK_RJ = 18, NOD_KICK_AB = 8, NOD_HOLD_RJ = 0.8, NOD_HZ = 2.0, NOD_DAMP = 0.55, NOD_AB_PEAK = 1.2,
    WARP_AMOUNT = 0.12, WARP_RISE = 0.06, WARP_FALL = 0.45, WARP_LEN = 2.0,
    RJ_LOW = 0.5, RJ_LOW_HZ = 2.6, AB_LOW = 0.8, AB_HEAVY = 0.6,
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

local function reset()
    hitstopEnd()
    st.abL, st.abLunging = 0, false
    for i = 1, 3 do st.sp[i], st.sv[i], st.accLP[i] = 0, 0, 0 end
    st.prevVel, st.burst, st.push = nil, 0, 0
    st.jp, st.jv, st.lastVz, st.pushZ = 0, 0, nil, 0
    st.rp, st.rv, st.rotPitch = 0, 0, 0
    st.hp, st.hpv, st.hr, st.hrv, st.rotHeadP, st.rotHeadR = 0, 0, 0, 0, 0, 0
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

    -- race start launch (bigger with a better perfect start)
    local ignPhase = tonumber(v.IgnitionPhase) or -1
    if ignPhase == IGN_POST and st.prevIgn == IGN_PERFECT then
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
        st.airPeak = 0
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
    V.feelDown, V.feelFwd, V.air = -lz, lx, air
    po[1], po[2], po[3] = rotate(q, lx, ly, lz)
end

V.hooks.feel = function(view, position, rotation)
    local po = st.posOff
    position.x, position.y, position.z = position.x + po[1], position.y + po[2], position.z + po[3]
    if st.rotPitch ~= 0 then rotation.x = rotation.x + st.rotPitch end
    if st.rotHeadP ~= 0 then rotation.x = rotation.x + st.rotHeadP end
    if st.rotHeadR ~= 0 then rotation.z = rotation.z + st.rotHeadR end
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
V.onReset(function() warpStop(); hitstopEnd() end)
