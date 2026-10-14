-- The menu (UEVR > Script UI): a few big groups, amounts in % (100 = recommended).
local log = V.logger('menu')
local S = V.cam
local tr, tip = V.tr, V.tip

-- Widget width: ImGui sliders / combos fill the line and push their label off the right edge.
-- They are given "full width minus LABEL_W" so the label stays readable: per widget with
-- set_next_item_width if this UEVR build has it, else push_item_width around the whole menu, else
-- the label is written on its own line above the widget.
local LABEL_W = 270
local widthMode = nil                      -- 'next' / 'push' / 'above'
local function detectWidthMode()
    local okN, fnN = pcall(function() return imgui.set_next_item_width end)
    if okN and type(fnN) == 'function' then return 'next' end
    local okP, fnP = pcall(function() return imgui.push_item_width end)
    local okQ, fnQ = pcall(function() return imgui.pop_item_width end)
    if okP and okQ and type(fnP) == 'function' and type(fnQ) == 'function' then return 'push' end
    return 'above'
end
-- call right before a slider / combo; returns the label to use
local function sized(label)
    if widthMode == 'next' then
        pcall(function() imgui.set_next_item_width(-LABEL_W) end)
    elseif widthMode == 'above' then
        imgui.text(label:match('^(.-)##') or label)
        return '##'..(label:match('##(.*)$') or label)
    end
    return label
end

-- slider with a value format when this UEVR build supports it (falls back to the plain slider)
local fmtOK = nil
local function slider(label, value, lo, hi, fmt)
    label = sized(label)
    if fmt and fmtOK ~= false then
        local ok, c, v = pcall(imgui.slider_float, label, value, lo, hi, fmt)
        if ok then fmtOK = true; return c, v end
        fmtOK = false
    end
    return imgui.slider_float(label, value, lo, hi)
end
local function round(x) return math.floor(x + 0.5) end
-- percent slider bound to a table field; returns true when changed
local function pctSlider(label, tbl, key, id, tipEn, tipKr)
    local c, v = slider(label..'##'..id, tonumber(tbl[key]) or 100, 0, 200, '%.0f %%')
    if tipEn then tip(tipEn, tipKr) end
    if c then tbl[key] = round(v); return true end
    return false
end
local function checkbox(label, value, id, tipEn, tipKr)
    local c, v = imgui.checkbox(label..'##'..id, value)
    if tipEn then tip(tipEn, tipKr) end
    return c, v
end
local function combo(label, list, current, id, tipEn, tipKr)
    local idx = 1
    for i, item in ipairs(list) do if item[1] == current then idx = i end end
    local names = {}
    for i, item in ipairs(list) do names[i] = tr(item[2], item[3]) end
    local c, v = imgui.combo(sized(label..'##'..id), idx, names)
    if tipEn then tip(tipEn, tipKr) end
    if c and list[v] then return list[v][1] end
    return nil
end
local function typeName(ty)
    local n = V.TYPE_NAMES[ty or '']
    return n and tr(n[1], n[2]) or tostring(ty)
end
-- a group (tree node) with a description on hover; named by its id alone, so the label may change
-- (counts, markers) without the group closing
local function section(label, id, tipEn, tipKr)
    local open = imgui.tree_node(label..'###'..id)
    if tipEn then tip(tipEn, tipKr) end
    return open
end
local function button(label, id, tipEn, tipKr)
    local c = imgui.button(label..'##'..id)
    if tipEn then tip(tipEn, tipKr) end
    return c
end
-- greyed-out widgets (shown, can't be changed) when this UEVR build has begin_disabled; without
-- it the widgets look normal but their changes are ignored by the caller
local disabledApi = nil
local function disabledBegin()
    if disabledApi == nil then
        local ok1, f1 = pcall(function() return imgui.begin_disabled end)
        local ok2, f2 = pcall(function() return imgui.end_disabled end)
        disabledApi = ok1 and ok2 and type(f1) == 'function' and type(f2) == 'function'
    end
    if not disabledApi then return false end
    return (pcall(function() imgui.begin_disabled(true) end))
end
local function disabledEnd(started) if started then pcall(function() imgui.end_disabled() end) end end
-- an explanation written into the menu (wrapped, for things nobody can guess)
local function help(en, kr)
    for line in (V.wrap(tr(en, kr))..'\n'):gmatch('(.-)\n') do imgui.text('  '..line) end
end
-- (no "%" in imgui.text / tooltips: some UEVR builds treat that text as a format string)

local CAMERA_MODES = {
    { 'cockpit', 'VR cockpit', 'VR 콕핏' },
    { 'game', 'Game cameras (third person / bonnet)', '게임 카메라 (3인칭 / 보닛)' },
}
local LOCKS = {
    { 'track', 'Level horizon (most comfortable)', '수평 고정 (가장 편함)' },
    { 'hills', 'Follow hills (up / down only)', '언덕만 따라가기 (오르내림만)' },
    { 'smooth', 'Follow the vehicle, smoothed (recommended)', '차를 부드럽게 따라가기 (추천)' },
    { 'light', 'Follow the vehicle, lightly smoothed', '차를 거의 그대로 따라가기' },
    { 'pilot', 'Exactly like the vehicle (motion sickness!)', '차체 그대로 (멀미 주의)' },
}
local PILOT = {
    { 'head', 'Hide the head (hands and body stay)', '머리만 숨기기 (손·몸은 보임)' },
    { 'hidden', 'Hide the whole pilot', '조종사 전부 숨기기' },
    { 'visible', 'Show the whole pilot', '조종사 전부 보이기' },
}
local FEEL = {
    { 'engine', 'Engine vibration', '엔진 진동',
      'Engine hum while standing and driving, and the heavy throb when you rev with W. 100 = recommended, 0 = off, 200 = double.',
      '서 있을 때와 달릴 때의 엔진 떨림, W를 밟을 때의 부릉부릉. 100 = 추천값, 0 = 끔, 200 = 두 배.' },
    { 'road', 'Road rumble and bumps', '노면 진동·출렁임',
      'Fine rumble from the ground that grows with speed, and the head bobbing up and down over the terrain.',
      '속도가 빠를수록 커지는 바닥 잔진동과, 지형을 따라 머리가 위아래로 출렁이는 것.' },
    { 'motion', 'Push in corners / drifts', '쏠림 (코너·드리프트·슬립스트림)',
      'Pushed sideways in corners, rumble while drifting, buffeting right behind other racers.',
      '코너에서 옆으로 쏠림, 드리프트하는 동안의 떨림, 다른 레이서 바로 뒤에서의 흔들림.' },
    { 'boost', 'Boost punch', '부스터 손맛',
      'Afterburner, ramjet and race start: the view lunges forward, the nose lifts, a low hum while it burns, shaking as the ramjet overheats.',
      '애프터버너·램젯·레이스 출발 때 시점이 앞으로 튀어나가고, 앞이 살짝 들리고, 켜진 동안 웅웅 울리고, 램젯이 과열될수록 흔들립니다.' },
    { 'landing', 'Landings and hits', '착지·충돌',
      'Pressed down when you land after a jump (deeper after longer jumps), knocked when you hit something.',
      '점프 후 착지할 때 아래로 쿵 눌림 (오래 날수록 깊게), 부딪힐 때 덜컥.' },
}
local BANK = { 'roll', 'Banking', '기울기',
    'How much the view leans sideways with the vehicle in turns. 100 = recommended, 50 = half, 0 = always level, 200 = double. Bikes and planes lean very hard (up to 90 degrees when drifting): lower it if that is too much.',
    '코너에서 시점이 차를 따라 옆으로 기우는 정도. 100 = 추천값, 50 = 절반, 0 = 항상 수평, 200 = 두 배. 바이크·비행기형은 드리프트 때 90도까지 기울어서, 너무 심하면 낮추세요.' }
local FOLLOW_KEYS = { 'followUp', 'followFwd' }
local VEH_KEYS = { 'followUp', 'followFwd', 'near' }   -- shown in each saved vehicle

-- Values saved per vehicle. m = the vehicle (the one driven, or one in "Saved vehicles"). Without a
-- vehicle the widget is greyed out, shows the shared value and can't be changed. Only a value the
-- user changes is stored for the vehicle ("[vehicle]"); the others keep following the shared value.
local function ownMark(own) return own and tr('[vehicle] ', '[이 차량] ') or '' end
-- builtin: this vehicle's built-in default as text (nil = none, it uses the shared value)
local function ownTip(tipEn, tipKr, m, own, shared, rec, builtin)
    local en, kr
    if not m then
        en, kr = 'Get into a vehicle to change it (saved for that vehicle).', '차에 타면 바꿀 수 있어요 (그 차량에 저장돼요).'
    elseif own then
        en = 'Saved for this vehicle. Default: '..(builtin or shared)..(builtin and ' (this vehicle)' or ' (shared)')..', recommended: '..rec
        kr = '이 차량에 저장한 값. 기본값: '..(builtin or shared)..(builtin and ' (이 차량 기본값)' or ' (공용 값)')..', 추천값: '..rec
    elseif builtin then
        en = 'This vehicle\'s own default (shared value: '..shared..'). Touch it and your value is saved for this vehicle. Recommended: '..rec
        kr = '이 차량 기본값이에요 (공용 값: '..shared..'). 만지면 이 차량에 저장돼요. 추천값: '..rec
    else
        en, kr = 'Not changed for this vehicle: follows the shared value. Touch it and it is saved for this vehicle. Recommended: '..rec,
                 '이 차량은 안 바꿈: 공용 값을 따라가요. 만지면 이 차량에 저장돼요. 추천값: '..rec
    end
    tip(tipEn ~= '' and tipEn..'\n'..en or en, tipKr ~= '' and tipKr..'\n'..kr or kr)
end
local function ownReset(own, kind, m, key, id)
    if not own then return end
    imgui.same_line()
    if button(tr('default', '기본값으로'), id..'x', 'Forgets the value you set for this vehicle: back to its default (the vehicle\'s own default if it has one, else the shared value).',
        '이 차량에 저장한 값을 지우고 기본값으로 돌아가요 (이 차량 기본값이 있으면 그것, 없으면 공용 값).') then V.clearOwnVal(kind, m, key) end
end
-- one fine-tuning value of vehicle m; true if the vehicle has its own
local function tuneSlider(item, m, id, label)
    local own = V.ownVal('detail', m, item.key)
    local dis = not m and disabledBegin()
    local c, v = slider(ownMark(own)..(label or tr(item.en, item.kr))..'###'..id, V.valFor(m, item.key), item.lo, item.hi, '%.2f')
    disabledEnd(dis)
    local b = V.builtinVal('detail', m, item.key)
    ownTip(item.tipEn or '', item.tipKr or '', m, own, string.format('%.2f', V.sharedVal(item.key)), string.format('%.2f', item.base), b and string.format('%.2f', b))
    if c and m then V.setOwnVal('detail', m, item.key, v) end
    ownReset(own, 'detail', m, item.key, id)
    return own ~= nil
end
-- body follow of vehicle m with character c (saved for that pair; else the vehicle's value)
local function followSlider(item, m, c, id, label)
    local own = V.followOwn(m, c, item.key)
    local cv, v = slider((own and tr('[vehicle+character] ', '[차량·캐릭터] ') or '')..(label or tr(item.en, item.kr))..'###'..id,
        V.followVal(m, c, item.key), item.lo, item.hi, '%.2f')
    local d = string.format('%.2f', V.pilotBuiltin(m, c, item.key) or V.valFor(m, item.key))
    if own then
        tip((item.tipEn or '')..'\nSaved for this vehicle and character. Default: '..d,
            (item.tipKr or '')..'\n이 차량·캐릭터 조합에 저장한 값. 기본값: '..d)
    else
        tip((item.tipEn or '')..'\nNot changed for this character: uses the default '..d..'. Touch it and it is saved for this vehicle and character.',
            (item.tipKr or '')..'\n이 캐릭터로는 안 바꿈: 기본값 '..d..'을 써요. 만지면 이 차량·캐릭터 조합에 저장돼요.')
    end
    if cv then V.setFollowVal(m, c, item.key, v) end
    if own then
        imgui.same_line()
        if button(tr('default', '기본값으로'), id..'x', 'Forgets the value for this vehicle and character.',
            '이 차량·캐릭터 조합에 저장한 값을 지우고 기본값으로 돌아가요.') then V.clearFollowVal(m, c, item.key) end
    end
    return own ~= nil
end
-- a % amount of vehicle m (banking or a shake group: { key, en, kr, tipEn, tipKr }); true if own
local function pctOwnSlider(p, m, id)
    local own = V.ownVal('feel', m, p[1])
    local dis = not m and disabledBegin()
    local c, v = slider(ownMark(own)..tr(p[2], p[3])..'###'..id, V.pctFor(m, p[1]), 0, 200, '%.0f %%')
    disabledEnd(dis)
    local b = V.builtinVal('feel', m, p[1])
    ownTip(p[4], p[5], m, own, tostring(round(V.sharedPct(p[1]))), '100', b and tostring(round(b)))
    if c and m then V.setOwnVal('feel', m, p[1], round(v)) end
    ownReset(own, 'feel', m, p[1], id)
    return own ~= nil
end
-- Fine tuning by topic, so everything about one thing (e.g. landings) is in one place, roughly in
-- the order it happens. A value not listed here still shows up, under "Other".
local TUNE_LAYOUT = {
    { 'engine', 'Engine', '엔진', { 'idle', 'idleRev', 'cruise' } },
    { 'road', 'Road and corners', '노면·코너', { 'road', 'bumps', 'corner', 'accel', 'drift', 'draft' } },
    { 'lunge', 'Boost lunge and nose lift', '부스터 돌진·기수 들림',
      { 'ramjet', 'afterburner', 'launch', 'ebrake', 'lungeMax', 'fwdScale', 'nod', 'lowHum', 'heatShake' } },
    { 'boostfx', 'Boost screen, hit-stop, warp', '부스터 화면·순간 멈칫·세상 출렁',
      { 'flashRJ', 'flashAB', 'satRJ', 'satAB', 'vigRJ', 'vigAB', 'fadeOut', 'hitstopStrength', 'hitstopAB', 'hitstopTime', 'warpAmount' } },
    { 'landing', 'Landings and hits', '착지·충돌',
      { 'airLift', 'landing', 'landFloor', 'landLean', 'landHit', 'landHitHz', 'headHitPitch', 'headHitRoll', 'headHitHz', 'nearLow', 'impact' } },
    { 'view', 'View (banking)', '시점 (기울기)', { 'rollAmount', 'rollMax' } },
    { 'spring', 'All shaking: head spring', '흔들림 전체 (머리 스프링)', { 'springHz', 'damping' } },
    { 'start', 'Race start', '레이스 시작', { 'leaveDelay', 'blendTime', 'carIdle', 'carRev' } },
}
local tuneGroups = nil
local function buildTuneGroups()
    local groups, listed = {}, {}
    for _, g in ipairs(TUNE_LAYOUT) do
        local items = {}
        for _, key in ipairs(g[4]) do
            local item = V.TUNE_INDEX[key]
            if item and not item.main then items[#items + 1] = item; listed[key] = true end
        end
        if #items > 0 then groups[#groups + 1] = { g[1], g[2], g[3], items } end
    end
    local rest = {}
    for _, item in ipairs(V.TUNABLES) do
        if not item.main and not listed[item.key] then rest[#rest + 1] = item end
    end
    if #rest > 0 then groups[#groups + 1] = { 'other', 'Other', '기타', rest } end
    return groups
end
-- every fine-tuning value of vehicle m, by topic (body follow / cut distance are in the View menu)
local function tuneTree(m, idp)
    tuneGroups = tuneGroups or buildTuneGroups()
    for _, g in ipairs(tuneGroups) do
        if section(tr(g[2], g[3]), idp..'g_'..g[1]) then
            local any = false
            for _, item in ipairs(g[4]) do any = tuneSlider(item, m, idp..item.key) or any end
            if any and button(tr('All of this group back to default', '이 묶음 전부 기본값으로'), idp..'all'..g[1],
                'Forgets the values you set for this vehicle in this group.', '이 묶음에서 이 차량에 저장한 값을 전부 지워요.') then
                for _, item in ipairs(g[4]) do V.clearOwnVal('detail', m, item.key) end
            end
            imgui.tree_pop()
        end
    end
end

local armReset = 0
local function drawMenu()
    local title = tr('STAR WARS Galactic Racer VR', '스타워즈 갤럭틱 레이서 VR')..'  v'..V.VERSION
    if not section(title, 'swgrvr', 'VR cockpit for Galactic Racer. Hover over anything in this menu for an explanation.',
        '갤럭틱 레이서 VR 콕핏. 메뉴의 어떤 항목이든 마우스를 올리면 설명이 나와요.') then return end
    if V.oldScriptsFound then
        help('!! The old swgr_cockpit_*.lua scripts are still installed. Delete them from the scripts folder, then press Reset scripts.',
             '!! 예전 swgr_cockpit_*.lua 스크립트가 아직 scripts 폴더에 있어요. 지우고 Reset scripts를 누르세요.')
    end
    local ch = false

    -- all add-on effects on / off ----------------------------------------------------------------
    local cx, vx = checkbox(tr('Add-on effects on', '추가 기능 켜기'), V.cfg.extras, 'extras',
        'The original cockpit script only puts you in the seat. Everything this package adds is switched by this box: cockpit shake and boost effects, banking limit, body follow on jumps, near clip, screen colours, the engine start shot and car body hum. Off = exactly like the original cockpit, handy to compare. (Eye position per vehicle, hotkeys and menu screen positions keep working.)',
        '원본 콕핏은 조종석에 앉혀 주는 것까지만 해요. 이 패키지가 더한 기능은 이 체크 하나로 전부 켜고 꺼요: 흔들림과 부스터 연출, 기울기 제한, 점프 때 몸 따라가기, 가까운 곳 안 그리기, 화면 색감, 시동 장면, 차체 떨림. 끄면 원본 콕핏과 똑같아서 비교할 때 좋아요. (차량별 눈 위치, 단축키, 메뉴 화면 위치는 그대로 작동해요.)')
    if cx then V.cfg.extras = vx; ch = true end
    if not V.cfg.extras then
        help('-> Add-on effects are OFF: the cockpit works like the original script.', '-> 추가 기능 꺼짐: 원본 콕핏과 똑같이 동작하는 중이에요.')
    end
    if V.hotkeyText('Extras') ~= tr('none', '없음') then
        imgui.text(string.format(tr('  On / off key: %s', '  켜기/끄기 단축키: %s'), V.hotkeyText('Extras')))
    end

    -- camera mode, hotkeys, recenter ---------------------------------------------------------
    local m = combo(tr('View', '시점'), CAMERA_MODES, S.cameraMode, 'mode',
        'VR cockpit = you sit in the vehicle. Game cameras = the game\'s own third person / bonnet cameras (the cockpit effects are off there). The hotkey below switches too.',
        'VR 콕핏 = 차 안 조종석에 앉은 시점. 게임 카메라 = 게임 원래의 3인칭 / 보닛 카메라 (콕핏 효과는 꺼짐). 아래 단축키로도 바꿀 수 있어요.')
    if m then S.setCameraMode(m) end
    imgui.text(string.format(tr('  Switch: %s    Next game camera: %s', '  전환: %s    다음 게임 카메라: %s'),
        V.hotkeyText('Toggle'), V.hotkeyText('Cycle')))
    tip('Change the keys in "Hotkeys" below.', '키는 아래 "단축키"에서 바꿀 수 있어요.')
    if button(tr('Recenter head at the seat', '머리 위치를 좌석에 맞추기'), 'recenter',
        'If you sit off-centre or too far forward / back: sit straight in your real chair and press this. Your current head position becomes the middle of the seat.',
        '몸이 한쪽으로 치우치거나 너무 앞·뒤에 앉은 것 같으면: 실제 의자에 바르게 앉아서 누르세요. 지금 머리 위치가 좌석 한가운데가 됩니다.') then S.recenter() end
    -- per-vehicle values: what you change while driving is saved for that vehicle only
    if V.model then
        imgui.text(string.format(tr('Vehicle: %s (%s)', '지금 차량: %s (%s)'), V.model, typeName(V.vtype))
            ..(V.pilot and string.format(tr('   Character: %s', '   캐릭터: %s'), V.pilotLabel(V.pilot)) or ''))
        tip('The vehicle you are driving now (type / model).', '지금 타고 있는 차량 (종류 / 모델).')
        help(string.format('-> What you change now (eye position, banking, body follow, cut distance, shake, fine tuning) is saved for %s only. What you don\'t touch keeps its default.', V.model),
             string.format('-> 지금 바꾸는 값(눈 위치, 기울기, 몸 따라가기, 안 그리는 거리, 흔들림, 세부 조절)은 %s 에만 자동 저장돼요. 안 만진 값은 기본값을 그대로 써요.', V.model))
    else
        help('-> No vehicle: the vehicle settings (eye position, banking, body follow, cut distance, shake, fine tuning) only show the defaults and can\'t be changed. Get into a vehicle to change them for it, or change a saved vehicle in "Saved vehicles" at the bottom.',
             '-> 차에 안 탄 상태: 차량 관련 값(눈 위치, 기울기, 몸 따라가기, 안 그리는 거리, 흔들림, 세부 조절)은 기본값만 보여주고 바꿀 수 없어요. 차에 타면 그 차량 값으로 바꿀 수 있고, 저장된 차량은 맨 아래 "저장된 차량"에서 고칠 수 있어요.')
    end
    imgui.separator()

    -- view ---------------------------------------------------------------------------------------
    if section(tr('View and eye position', '시점·눈 위치'), 'view',
        'Where your eyes sit in the vehicle and how the view moves with it.',
        '차 안에서 눈이 어디에 있는지, 시점이 차를 얼마나 따라 움직이는지.') then
        do
            local locked = not V.model
            local e, ownEye = V.eyeFor(V.model)
            if locked then
                help('No vehicle yet: showing the default eye position. Get into a vehicle to adjust it; your change is saved for that vehicle.',
                     '아직 차량이 없어서 기본 눈 위치를 보여주는 중이에요. 차에 타면 조절할 수 있고, 바꾼 값은 그 차량에 자동 저장돼요.')
            else
                imgui.text(string.format(tr('Eye position (%s): %s', '눈 위치 (%s): %s'), V.model,
                    ownEye and tr('saved for this vehicle', '이 차량에 저장됨') or tr('default', '기본값')))
                tip('Saved automatically for the vehicle you drive as soon as you move a slider.',
                    '슬라이더를 움직이는 순간 지금 타는 차량에 자동 저장돼요.')
            end
            local x, y, z = e[1], e[2], e[3]
            local dis = locked and disabledBegin()
            local c1, v1 = slider(tr('Sideways (cm)', '좌우 (cm)')..'##eyeX', x, -60, 60, '%.1f')
            tip('Moves your eyes left / right in the seat. Saved for this vehicle.', '눈을 좌석에서 좌우로 옮깁니다. 지금 차량에 저장돼요.')
            local c2, v2 = slider(tr('Forward / back (cm)', '앞뒤 (cm)')..'##eyeY', y, -100, 100, '%.1f')
            tip('Moves your eyes forward / back. Use it if the dashboard is too close or too far.', '눈을 앞뒤로 옮깁니다. 계기판이 너무 가깝거나 멀면 이걸로.')
            local c3, v3 = slider(tr('Up / down (cm)', '위아래 (cm)')..'##eyeZ', z, 0, 150, '%.1f')
            tip('Moves your eyes up / down. Use it if you feel you sit too low or too high.', '눈을 위아래로 옮깁니다. 너무 낮거나 높게 앉은 느낌이면 이걸로.')
            disabledEnd(dis)
            if not locked and (c1 or c2 or c3) then V.setEye(c1 and v1 or x, c2 and v2 or y, c3 and v3 or z) end
            if ownEye and button(tr('Default eye for this vehicle', '이 차량 눈 위치 기본값으로'), 'eyeReset',
                'Forgets the eye position saved for this vehicle.', '이 차량에 저장된 눈 위치를 지우고 기본값으로 돌아갑니다.') then V.resetEye() end
        end
        local l = combo(tr('Follow the vehicle', '시점 따라가기'), LOCKS, S.cameraLock, 'lock',
            'How much the view tilts with the vehicle when it pitches over hills and leans in turns. Higher in the list = more comfortable, lower = more alive. If you get motion sick, pick "Level horizon".',
            '차가 언덕에서 숙이고 코너에서 기울 때 시점이 얼마나 같이 기울지. 목록 위쪽일수록 편하고, 아래쪽일수록 생생합니다. 멀미가 나면 "수평 고정".')
        if l then S.cameraLock = l; V.cfg.cameraLock = l; ch = true end
        pctOwnSlider(BANK, V.model, 'v_roll')
        local p = combo(tr('Pilot', '조종사'), PILOT, S.pilotVisibility == 'visible' and V.cfg.pilot or S.pilotVisibility, 'pilot',
            'How much of your pilot you see in the cockpit. The head is in the same place as your eyes, so it is usually hidden.',
            '콕핏에서 내 조종사를 얼마나 보여줄지. 머리는 내 눈과 같은 자리라 보통 숨겨요.')
        if p then S.setPilotMode(p) end
        local c, v = checkbox(tr('Show the race intro flyover', '레이스 소개 장면 보기'), S.showCinematics, 'cine',
            'Before a race the game flies the camera over the track. On: you watch it with the game camera, then the cockpit takes over. Off: cockpit from the start.',
            '레이스 전에 게임이 트랙을 날아다니며 보여주는 장면. 켜면 그 장면을 게임 카메라로 보고 끝나면 콕핏으로. 끄면 처음부터 콕핏.')
        if c then S.showCinematics = v; V.cfg.showCinematics = v; ch = true end
        c, v = checkbox(tr('Outside view when crashing', '충돌할 때 바깥 카메라'), S.showCrashCamera, 'crash',
            'On: when you crash or tumble, the game\'s crash camera shows the wreck from outside. Off: you stay in the cockpit (can be wild).',
            '켜면 크게 충돌하거나 구를 때 게임의 충돌 장면(밖에서 보는 카메라)으로 바뀝니다. 끄면 콕핏 그대로 (많이 흔들릴 수 있어요).')
        if c then S.showCrashCamera = v; V.cfg.showCrashCamera = v; ch = true end
        c, v = checkbox(tr('Follow the pilot on jumps', '점프 때 조종사 몸 따라가기'), V.cfg.bodyFollow, 'follow',
            'On jumps (mostly bikes) the rider stands up in the air. Your eyes stay at the seat, so you would end up inside the rider\'s body. On: your eyes move with the body while airborne.',
            '점프하면 (주로 바이크) 공중에서 조종사가 몸을 일으켜요. 눈은 좌석에 그대로라 조종사 몸통 속으로 들어가게 됩니다. 켜면 공중에 있는 동안 눈이 몸을 따라 움직여요.')
        if c then V.cfg.bodyFollow = v; ch = true end
        if V.cfg.bodyFollow then
            if V.model and V.pilot then
                imgui.text(string.format(tr('  Saved for this vehicle and character (%s)', '  이 차량 + 이 캐릭터(%s) 조합으로 저장'), V.pilotLabel(V.pilot)))
                tip('Characters differ in build and posture, so the same vehicle can need other values for each character.',
                    '캐릭터마다 체격과 자세가 달라서, 같은 차량이어도 캐릭터별로 따로 저장돼요.')
            end
            for _, key in ipairs(FOLLOW_KEYS) do
                local item = V.TUNE_INDEX[key]
                if V.model and V.pilot then followSlider(item, V.model, V.pilot, 'v_'..key, '  '..tr(item.en, item.kr))
                else tuneSlider(item, V.model, 'v_'..key, '  '..tr(item.en, item.kr)) end
            end
        end
        c, v = checkbox(tr('Cut what is right at the eye', '눈앞 가까운 것 안 그리기'), V.cfg.nearClip, 'near',
            'The pilot body is right next to your eyes. On landings and jumps it can fill your view from the inside. On: anything a few centimetres from your eyes is not drawn, so you see past it. Hands and handlebars further out stay.',
            '조종사 몸통은 눈 바로 옆에 있어요. 착지·점프 때 몸통 안쪽이 시야를 가릴 수 있어요. 켜면 눈에서 몇 cm 안쪽은 그리지 않아서 그 너머가 보여요. 더 멀리 있는 손·핸들은 그대로 보여요.')
        if c then V.cfg.nearClip = v; ch = true end
        if V.cfg.nearClip then
            local item = V.TUNE_INDEX.near
            tuneSlider(item, V.model, 'v_near', '  '..tr(item.en, item.kr))
        end
        imgui.tree_pop()
    end

    -- shake --------------------------------------------------------------------------------------
    if section(tr('Cockpit shake', '흔들림'), 'feel',
        'The view moves like your head would in a real racer: engine, road, corners, boosts, landings. Five amounts: 100 = recommended, 0 = off, 200 = double. Each one is explained when you hover over it.',
        '진짜 레이서에 탄 것처럼 시점이 움직여요: 엔진, 노면, 코너, 부스터, 착지. 다섯 가지 세기: 100 = 추천값, 0 = 끔, 200 = 두 배. 마우스를 올리면 각각 설명이 나와요.') then
        local c, v = checkbox(tr('On', '켜기'), V.cfg.feelOn, 'feelOn',
            'All cockpit shake and boost punch at once. Off = a perfectly still cockpit. If you feel motion sick, try this first.',
            '콕핏 흔들림과 부스터 손맛 전체. 끄면 전혀 흔들리지 않는 콕핏. 멀미가 나면 이것부터 꺼 보세요.')
        if c then V.cfg.feelOn = v; ch = true end
        local vm, anyOwn = V.model, false
        for _, f in ipairs(FEEL) do anyOwn = pctOwnSlider(f, vm, 'f'..f[1]) or anyOwn end
        c, v = checkbox(tr('Landing hits your head', '착지 때 머리 충격'), V.cfg.headHit, 'headHit',
            'The usual landing moves your view down, which feels like the vehicle jolts while your head stays still. This also snaps the view angle down and back with a little sideways wobble at touchdown, so it feels like your head takes the hit. Fine tuning > Landings and hits has its values.',
            '원래 착지 효과는 시점 위치를 아래로 내려서 "내 머리는 가만있고 차만 툭" 느낌이에요. 이걸 켜면 땅에 닿는 순간 보는 각도도 툭 숙여졌다 튕기고 좌우로 살짝 흔들려서 "내 머리가 충격을 받은" 느낌이 나요. 세기는 세부 조절 > 착지·충돌에서.')
        if c then V.cfg.headHit = v; ch = true end
        if anyOwn and button(tr('This vehicle: all shake back to default', '이 차량 흔들림 전부 기본값으로'), 'feelShared',
            'Forgets the shake amounts you set for this vehicle; back to its defaults.',
            '이 차량에 저장한 흔들림 값을 지우고 기본값으로 돌아가요.') then
            for _, g in ipairs(V.FEEL_GROUPS) do V.clearOwnVal('feel', vm, g) end
        end
        imgui.tree_pop()
    end

    -- boost effects ------------------------------------------------------------------------------
    if section(tr('Boost effects', '부스터 연출'), 'boostfx',
        'Extra effects when you fire the afterburner or the ramjet, or at the race start.',
        '애프터버너·램젯을 켤 때와 레이스 출발 때의 추가 연출.') then
        ch = pctSlider(tr('Screen colours and flash', '화면 색감·섬광'), V.cfg, 'screen', 'screen',
            'While boosting the colours get stronger and the screen edges darker, with a short flash when it starts; then it eases back. 0 = off, 100 = recommended.',
            '부스터를 쓰는 동안 색이 진해지고 화면 가장자리가 어두워지며, 켜는 순간 살짝 번쩍입니다. 끝나면 서서히 원래대로. 0 = 끔, 100 = 추천값.') or ch
        local c, v = checkbox(tr('Hit-stop at ramjet / race start', '램젯·출발 때 순간 멈칫'), V.cfg.hitstop, 'hitstop',
            'The trick of action games: at ramjet ignition and the race start the whole game slows down for a split second, then snaps back to full speed. Feels like a punch.',
            '액션 게임에서 쓰는 연출: 램젯 점화·레이스 출발 순간 게임 전체가 아주 잠깐 느려졌다가 확 원래 속도로 풀립니다. 한 방 맞는 느낌.')
        if c then V.cfg.hitstop = v; ch = true end
        c, v = checkbox(tr('Warp pulse at ramjet / race start', '램젯·출발 때 세상 출렁'), V.cfg.warp, 'warp',
            'At ramjet ignition and the race start the size of the world pulses for a moment (VR world scale), like the speed kick the flat game does by widening the screen.',
            '램젯 점화·레이스 출발 순간 세상 크기가 잠깐 출렁입니다 (VR 월드 스케일). 일반 화면 게임이 화면을 넓혀서 주는 속도감 대신.')
        if c then V.cfg.warp = v; ch = true end
        imgui.tree_pop()
    end

    -- race start ---------------------------------------------------------------------------------
    if section(tr('Race start', '레이스 시작'), 'intro',
        'What happens before the race: the engine start shot and how you get into the cockpit.',
        '레이스 전: 시동 장면과 콕핏으로 들어가는 방법.') then
        local c, v = checkbox(tr('Show the engine start, then move into the cockpit', '시동 장면 보고 콕핏으로 이동'), V.cfg.intro, 'intro',
            'Before the race the game shows your engine starting from outside. On: you watch it, and shortly after the engine starts the view flies smoothly into your seat. Off: cockpit the whole time.',
            '레이스 전에 게임이 엔진에 시동이 걸리는 모습을 밖에서 보여줘요. 켜면 그 장면을 보고, 시동이 걸리고 잠시 뒤 시점이 부드럽게 날아서 좌석으로 들어갑니다. 끄면 처음부터 콕핏.')
        if c then V.cfg.intro = v; ch = true end
        ch = pctSlider(tr('Car body engine hum (game cameras)', '차체 엔진 떨림 (게임 카메라)'), V.cfg, 'carShake', 'carShake',
            'Seen from outside (the engine start shot, third person) the vehicle body sits perfectly still even with the engine running. This makes it hum and shake when you rev. 0 = off.',
            '밖에서 볼 때 (시동 장면, 3인칭) 게임은 시동이 걸려도 차체가 꼼짝 안 해요. 이걸 켜면 차체가 부르르 떨고, W를 밟으면 더 떨려요. 0 = 끔.') or ch
        imgui.tree_pop()
    end

    -- fine tuning (every single value) -------------------------------------------------------------
    if section(tr('Fine tuning (advanced)', '세부 조절 (고급)'), 'fine',
        'For people who want to go deeper: every single value behind the simple settings above. You don\'t need this.',
        '더 깊이 만지고 싶은 사람용: 위의 간단한 설정 뒤에 있는 값 하나하나. 몰라도 괜찮아요.') then
        help('Every single value. The amounts in "Cockpit shake" and "Banking" are applied on top of these (they multiply). 0 turns an effect off. Hover for details and the recommended value.',
             '값 하나하나를 직접 조절합니다. "흔들림"과 "기울기" 세기가 이 값들에 곱해져요. 0이면 그 효과는 꺼져요. 마우스를 올리면 설명과 추천값이 나와요.')
        if V.model then
            help(string.format('Driving %s: a value you change is saved for this vehicle only ("[vehicle]"); the others keep their defaults.', V.model),
                 string.format('%s 를 타는 중: 바꾸는 값은 이 차량에만 저장되고 ("[이 차량]" 표시), 안 바꾼 값은 기본값을 따라가요.', V.model))
        end
        tuneTree(V.model, 'fine_')
        imgui.tree_pop()
    end

    -- saved vehicles: everything of a vehicle, changeable without driving it ----------------------
    local names, seen = {}, {}
    local D = V.VEH_DEFAULTS
    for _, tbl in ipairs({ V.veh.eyes, V.veh.feel, V.veh.detail, V.veh.pilotFollow, D.eyes, D.feel, D.detail }) do
        for name in pairs(tbl) do if not seen[name] then seen[name] = true; names[#names + 1] = name end end
    end
    table.sort(names)
    if section(string.format(tr('Saved vehicles (%d)', '저장된 차량 (%d대)'), #names), 'vehicles',
        'Every vehicle with something saved. Open one to see and change all its values without driving it: untouched values keep their defaults, a value you touch is saved for that vehicle.',
        '무언가 저장된 차량 목록. 차량을 열면 그 차를 타지 않아도 값을 전부 보고 고칠 수 있어요. 안 만진 값은 기본값을 따라가고, 만진 값만 그 차량에 저장돼요.') then
        local AX = { { 'Sideways (cm)', '좌우 (cm)', -60, 60 }, { 'Forward / back (cm)', '앞뒤 (cm)', -100, 100 }, { 'Up / down (cm)', '위아래 (cm)', 0, 150 } }
        for _, name in ipairs(names) do
            if section(name..(name == V.model and tr('  (driving now)', '  (지금 타는 중)') or ''), 'veh'..name) then
                local e, ownEye = V.eyeFor(name)
                imgui.text(ownEye and tr('Eye position (saved for this vehicle):', '눈 위치 (이 차량에 저장됨):') or tr('Eye position (default):', '눈 위치 (기본값):'))
                for i, a in ipairs(AX) do
                    local c, v = slider(tr(a[1], a[2])..'##ve'..name..i, tonumber(e[i]) or 0, a[3], a[4], '%.1f')
                    if c then
                        local ne = { tonumber(e[1]) or 0, tonumber(e[2]) or 0, tonumber(e[3]) or 0 }
                        ne[i] = v
                        V.veh.eyes[name] = ne; V.saveVeh()
                        if name == V.model then S.setEye(ne[1], ne[2], ne[3]) end
                        e = ne
                    end
                end
                if ownEye and button(tr('Default eye', '눈 위치 기본값으로'), 'ved'..name, 'Forgets this vehicle\'s eye position.', '이 차량의 눈 위치를 지웁니다.') then V.resetEye(name) end
                imgui.text(tr('Banking, body follow on jumps, cut distance:', '기울기·점프 때 몸 따라가기·안 그리는 거리:'))
                pctOwnSlider(BANK, name, 'vb'..name)
                for _, key in ipairs(VEH_KEYS) do
                    local item = V.TUNE_INDEX[key]
                    local label = (key ~= 'near') and tr(item.en..' (any character)', item.kr..' (캐릭터 공통)') or nil
                    tuneSlider(item, name, 'vm'..name..key, label)
                end
                -- characters' own body follow: folded, so a vehicle many characters drove stays tidy
                local pf = V.veh.pilotFollow[name]
                if type(pf) == 'table' and next(pf) ~= nil then
                    local chars = {}
                    for c in pairs(pf) do chars[#chars + 1] = c end
                    table.sort(chars)
                    if section(string.format(tr('Body follow per character (%d)', '캐릭터별 몸 따라가기 (%d명)'), #chars), 'vpc'..name,
                        'Body follow on jumps saved for this vehicle with each character. Open a character to change or forget its values.',
                        '이 차량에서 캐릭터마다 따로 저장한 점프 몸 따라가기 값. 캐릭터를 열면 고치거나 지울 수 있어요.') then
                        for _, c in ipairs(chars) do
                            local now = (name == V.model and c == V.pilot) and tr('  (driving now)', '  (지금 타는 중)') or ''
                            if section(V.pilotLabel(c)..now, 'vpc'..name..'/'..c) then
                                for _, key in ipairs(FOLLOW_KEYS) do followSlider(V.TUNE_INDEX[key], name, c, 'vp'..name..c..key) end
                                if button(tr('Forget this character\'s values', '이 캐릭터 값 지우기'), 'vpcx'..name..c,
                                    'This character uses the vehicle\'s body follow again.', '이 캐릭터도 다시 차량의 몸 따라가기 값을 써요.') then
                                    V.clearFollowVal(name, c)
                                end
                                imgui.tree_pop()
                            end
                        end
                        imgui.tree_pop()
                    end
                end
                imgui.text(tr('Shake:', '흔들림:'))
                for _, fg in ipairs(FEEL) do pctOwnSlider(fg, name, 'vf'..name..fg[1]) end
                local n, vd = 0, V.veh.detail[name]
                if type(vd) == 'table' then
                    for k in pairs(vd) do local item = V.TUNE_INDEX[k]; if item and not item.main then n = n + 1 end end
                end
                if section(string.format(tr('Advanced options (fine tuning) - %d changed', '고급 옵션 (세부 조절) - 이 차량 값 %d개'), n), 'vadv'..name,
                    'Every fine-tuning value this vehicle uses. Untouched = its default; touch one and it is saved for this vehicle ("[vehicle]").',
                    '이 차량이 쓰는 세부 조절 값 전부. 안 만진 값은 기본값 그대로고, 만지면 이 차량에 저장돼요 ("[이 차량]" 표시).') then
                    tuneTree(name, 'va'..name..'_')
                    imgui.tree_pop()
                end
                -- back to default: everything except the eye position and body follow (they depend on
                -- the seat and the character, so they are kept)
                local vdd = V.veh.detail[name]
                local resettable = V.veh.feel[name] ~= nil
                if type(vdd) == 'table' then
                    for k in pairs(vdd) do if k ~= 'followUp' and k ~= 'followFwd' then resettable = true end end
                end
                if resettable and button(tr('Everything back to default (eye position and body follow stay)', '눈 위치·몸 따라가기 빼고 전부 기본값으로'), 'vfd'..name,
                    'Forgets the banking, cut distance, shake and fine tuning you set for this vehicle; back to the defaults. Eye position and body follow on jumps (any character and per character) stay.',
                    '이 차량에 저장한 기울기·안 그리는 거리·흔들림·세부 조절을 지우고 기본값으로 돌아가요. 눈 위치와 점프 몸 따라가기(캐릭터 공통·캐릭터별)는 그대로 남아요.') then
                    if type(vdd) == 'table' then
                        local keep = { followUp = vdd.followUp, followFwd = vdd.followFwd }
                        V.veh.detail[name] = next(keep) ~= nil and keep or nil
                    end
                    V.clearOwnVal('feel', name)
                    V.saveVeh()
                end
                if button(tr('Forget everything I set for this vehicle', '이 차량에 저장한 것 전부 지우기'), 'vdel'..name, 'Forgets everything you set for this vehicle (eye position too); it goes back to its defaults.', '이 차량에 저장한 것을 전부 지우고 (눈 위치 포함) 기본값으로 돌아가요.') then
                    V.veh.eyes[name], V.veh.feel[name], V.veh.detail[name], V.veh.pilotFollow[name] = nil, nil, nil, nil
                    V.saveVeh()
                    if name == V.model then V.resetEye(name) end
                end
                imgui.tree_pop()
            end
        end
        if #names == 0 then imgui.text(tr('  (none yet - change something while driving)', '  (아직 없음 - 차를 타고 값을 바꾸면 생겨요)')) end
        imgui.tree_pop()
    end

    -- hotkeys ------------------------------------------------------------------------------------
    if section(tr('Hotkeys', '단축키'), 'hotkeys',
        'Keys / controller buttons for switching cameras, recentering and switching the add-on effects. Each action can have a keyboard key and a controller combo.',
        '카메라 전환·머리 맞추기·추가 기능 켜기/끄기용 키. 동작마다 키보드 키 하나와 컨트롤러 조합 하나를 정할 수 있어요.') then
        local padNames = {}
        for i, pd in ipairs(V.HOTKEY_PADS) do padNames[i] = { pd[1], pd[1], pd[1] } end
        help('Keyboard: click the button, then press the key you want (Esc = cancel). Controller: pick a combo from the list.',
             '키보드: 버튼을 클릭한 다음 원하는 키를 누르세요 (Esc = 취소). 컨트롤러: 목록에서 고르세요.')
        V.keyCaptureSeen = V.t                 -- the menu is open: a key capture may go on
        for _, a in ipairs(V.HOTKEY_ACTIONS) do
            imgui.text(tr(a.en, a.kr))
            local key = V.cfg['key'..a.id]
            local bound = key ~= nil and key ~= 'None'
            local waiting = V.keyCapture == a.id
            local label = waiting and tr('Press any key... (Esc = cancel)', '아무 키나 누르세요... (Esc = 취소)')
                or string.format(tr('Keyboard: %s', '키보드: %s'), bound and key or tr('none', '없음'))
            if button(label, 'k'..a.id, 'Click, then press the key for this. (Insert is the UEVR menu key and can\'t be used.) A key already used by another action moves to this one.',
                '클릭한 다음 이 동작에 쓸 키를 누르세요. (Insert는 UEVR 메뉴 키라 못 써요.) 다른 동작에 쓰던 키를 누르면 이쪽으로 옮겨져요.') then
                if waiting then V.keyCapture = nil else V.keyCaptureStart(a.id) end
            end
            if bound and not waiting then
                imgui.same_line()
                if button(tr('Clear', '지우기'), 'kc'..a.id, 'No keyboard key for this.', '이 동작의 키보드 키를 없앱니다.') then
                    V.cfg['key'..a.id] = 'None'; ch = true
                end
            end
            local pd = combo(tr('  Controller', '  컨트롤러'), padNames, V.cfg['pad'..a.id], 'p'..a.id,
                'Hold the Back (View) button and press the second button. The game may also react to that button, so pick one you don\'t use while racing.',
                'Back(뷰) 버튼을 누른 채 두 번째 버튼을 누르세요. 게임도 그 버튼에 반응할 수 있으니 레이스 중 안 쓰는 버튼으로 고르세요.')
            if pd then V.cfg['pad'..a.id] = pd; ch = true end
        end
        imgui.tree_pop()
    end

    -- menu screen positions ------------------------------------------------------------------------
    if section(tr('Menu screen positions', '메뉴 화면 위치'), 'views',
        'Fixes menus where your VR view ends up in a strange place (open it to see how).',
        'VR 시점이 엉뚱한 곳에 가는 메뉴 화면을 고치는 기능 (열어 보면 사용법이 있어요).') then
        help('Some menu and result screens put the game camera in a strange place: in VR you then stand under the map, inside a wall or far away. For those screens a saved VR camera position is applied automatically. The usual ones are already included. Not used in races.',
             '어떤 메뉴·결과 화면은 게임 카메라를 이상한 곳에 둬서, VR에서는 맵 밑이나 벽 속, 아주 먼 곳에 서 있게 돼요. 그런 화면에 저장된 VR 카메라 위치를 자동으로 적용합니다. 자주 나오는 화면은 이미 들어 있어요. 레이스 중에는 작동하지 않아요.')
        help('A screen looks wrong? 1) On that screen open UEVR menu > Camera > Camera Offset and move it until it looks right. 2) Press "Save" below. From then on it is applied every time that screen appears.',
             '어떤 화면이 이상하면: 1) 그 화면에서 UEVR 메뉴 > Camera > Camera Offset으로 제대로 보일 때까지 옮기고 2) 아래 "저장"을 누르세요. 다음부터 그 화면이 나올 때마다 자동으로 적용돼요.')
        local c, v = checkbox(tr('Apply saved positions', '저장된 위치 자동 적용'), V.cfg.viewOffsets, 'viewsOn',
            'Off: no screen gets a saved position.', '끄면 어떤 화면에도 저장된 위치를 적용하지 않아요.')
        if c then V.cfg.viewOffsets = v; ch = true end
        local key = V.viewState.currentKey
        if key then
            local k, auto = V.viewLookup(key)
            local n = k and V.VIEW_NAMES[k]
            imgui.text(tr('Current screen: ', '지금 화면: ')..(n and tr(n[1], n[2]) or key)..(auto and tr(' (same camera, other map)', ' (다른 맵의 같은 카메라)') or ''))
            tip('The camera of the screen you are on now. "Same camera, other map": result screens share one camera on every map, so one saved position works everywhere.',
                '지금 보고 있는 화면의 카메라. "다른 맵의 같은 카메라": 결과창은 모든 맵이 같은 카메라를 써서, 한 번 저장하면 다른 맵에도 적용돼요.')
            if button(tr('Save the current UEVR camera offset for this screen', '지금 UEVR 카메라 위치를 이 화면에 저장'), 'viewSave',
                'Saves what you set in UEVR menu > Camera > Camera Offset for this screen.',
                'UEVR 메뉴 > Camera > Camera Offset에서 맞춘 위치를 이 화면에 저장합니다.') then V.viewSaveCurrent() end
            if k and not auto then
                local isDefault = V.viewDefaults[k] ~= nil
                if button(isDefault and tr('Back to the built-in position', '기본 위치로') or tr('Forget this screen', '이 화면 삭제'), 'viewForget',
                    'Removes what you saved for this screen (built-in screens go back to their built-in position).',
                    '이 화면에 저장한 위치를 지웁니다 (원래 들어 있던 화면은 기본 위치로 돌아가요).') then V.viewForget(k) end
            end
        else
            imgui.text(tr('Current screen: race / vehicle camera (not handled)', '지금 화면: 레이스·차량 카메라 (대상 아님)'))
        end
        imgui.tree_pop()
    end

    -- reset everything (press twice) ---------------------------------------------------------------
    imgui.separator()
    local armed = V.t < armReset
    if button(armed and tr('Press again to reset ALL settings', '한 번 더 누르면 전부 초기화') or tr('Reset all settings', '전체 설정 초기화'), 'resetAll',
        'All settings and fine tuning back to the recommended values (press twice). Saved vehicles stay; delete them in "Saved vehicles".',
        '모든 설정과 세부 조절을 추천값으로 되돌립니다 (두 번 눌러야 해요). 저장된 차량은 남아요 ("저장된 차량"에서 지울 수 있어요).') then
        if armed then
            V.resetSettings()
            S.cameraLock, S.showCinematics, S.showCrashCamera = V.cfg.cameraLock, V.cfg.showCinematics, V.cfg.showCrashCamera
            S.setPilotMode(V.cfg.pilot)
            S.setCameraMode(V.cfg.cameraMode)
            armReset = 0; ch = true
            log('all settings reset')
        else
            armReset = V.t + 3
        end
    end

    if ch then V.save() end
    imgui.tree_pop()
end
callbacks.on_draw_ui(function()
    V.withFont(function()
        if widthMode == nil then widthMode = detectWidthMode(); log('widget width: '..widthMode) end
        if widthMode == 'push' then
            local pushed = pcall(function() imgui.push_item_width(-LABEL_W) end)
            local ok, err = pcall(drawMenu)
            if pushed then pcall(function() imgui.pop_item_width() end) end   -- always balanced
            if not ok then error(err, 0) end
        else
            drawMenu()
        end
    end)
end)
