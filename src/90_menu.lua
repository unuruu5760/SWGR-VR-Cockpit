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
local function pctSlider(label, tbl, key, id, tipEn)
    local c, v = slider(label..'##'..id, tonumber(tbl[key]) or 100, 0, 200, '%.0f %%')
    if tipEn then tip(tipEn) end
    if c then tbl[key] = round(v); return true end
    return false
end
local function checkbox(label, value, id, tipEn)
    local c, v = imgui.checkbox(label..'##'..id, value)
    if tipEn then tip(tipEn) end
    return c, v
end
local function combo(label, list, current, id, tipEn)
    local idx = 1
    for i, item in ipairs(list) do if item[1] == current then idx = i end end
    local names = {}
    for i, item in ipairs(list) do names[i] = tr(item[2]) end
    local c, v = imgui.combo(sized(label..'##'..id), idx, names)
    if tipEn then tip(tipEn) end
    if c and list[v] then return list[v][1] end
    return nil
end
local function typeName(ty)
    local n = V.TYPE_NAMES[ty or '']
    return n and tr(n[1]) or tostring(ty)
end
-- a group (tree node) with a description on hover; named by its id alone, so the label may change
-- (counts, markers) without the group closing
local function section(label, id, tipEn)
    local open = imgui.tree_node(label..'###'..id)
    if tipEn then tip(tipEn) end
    return open
end
local function button(label, id, tipEn)
    local c = imgui.button(label..'##'..id)
    if tipEn then tip(tipEn) end
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
local function help(en)
    for line in (V.wrap(tr(en))..'\n'):gmatch('(.-)\n') do imgui.text('  '..line) end
end
-- (no "%" in imgui.text / tooltips: some UEVR builds treat that text as a format string)

local CAMERA_MODES = {
    { 'cockpit', 'VR cockpit' },
    { 'game', 'Game cameras (third person / bonnet)' },
}
local LOCKS = {
    { 'track', 'Level horizon (most comfortable)' },
    { 'hills', 'Follow hills (up / down only)' },
    { 'smooth', 'Follow the vehicle, smoothed (recommended)' },
    { 'light', 'Follow the vehicle, lightly smoothed' },
    { 'pilot', 'Exactly like the vehicle (motion sickness!)' },
}
local PILOT = {
    { 'head', 'Hide the head (hands and body stay)' },
    { 'hidden', 'Hide the whole pilot' },
    { 'visible', 'Show the whole pilot' },
}
local FEEL = {
    { 'engine', 'Engine vibration',
      'Engine hum while standing and driving, and the heavy throb when you rev with W. 100 = recommended, 0 = off, 200 = double.' },
    { 'road', 'Road rumble and bumps',
      'Fine rumble from the ground that grows with speed, and the head bobbing up and down over the terrain.' },
    { 'motion', 'Push in corners / drifts',
      'Pushed sideways in corners, rumble while drifting, buffeting right behind other racers.' },
    { 'boost', 'Boost punch',
      'Afterburner, ramjet and race start: the view lunges forward, the nose lifts, a low hum while it burns, shaking as the ramjet overheats.' },
    { 'landing', 'Landings and hits',
      'Pressed down when you land after a jump (deeper after longer jumps), knocked when you hit something.' },
}
local BANK = { 'roll', 'Banking',
    'How much the view leans sideways with the vehicle in turns. 100 = recommended, 50 = half, 0 = always level, 200 = double. Bikes and planes lean very hard (up to 90 degrees when drifting): lower it if that is too much.' }
local FOLLOW_KEYS = { 'followUp', 'followFwd' }
local VEH_KEYS = { 'followUp', 'followFwd', 'near' }   -- shown in each saved vehicle

-- Values saved per vehicle. m = the vehicle (the one driven, or one in "Saved vehicles"). Without a
-- vehicle the widget is greyed out, shows the shared value and can't be changed. Only a value the
-- user changes is stored for the vehicle ("[vehicle]"); the others keep following the shared value.
local function ownMark(own) return own and tr('[vehicle] ') or '' end
-- builtin: this vehicle's built-in default as text (nil = none, it uses the shared value)
local function ownTip(tipEn, m, own, shared, rec, builtin)
    local note
    if not m then
        note = tr('Get into a vehicle to change it (saved for that vehicle).')
    elseif own then
        note = tr('Saved for this vehicle. Default: ')..(builtin or shared)..(builtin and tr(' (this vehicle)') or tr(' (shared)'))
            ..tr(', recommended: ')..rec
    elseif builtin then
        note = tr('This vehicle\'s own default (shared value: ')..shared
            ..tr('). Touch it and your value is saved for this vehicle. Recommended: ')..rec
    else
        note = tr('Not changed for this vehicle: follows the shared value. Touch it and it is saved for this vehicle. Recommended: ')..rec
    end
    local t = tr(tipEn)
    tip(t ~= '' and t..'\n'..note or note)
end
local function ownReset(own, kind, m, key, id)
    if not own then return end
    imgui.same_line()
    if button(tr('default'), id..'x', 'Forgets the value you set for this vehicle: back to its default (the vehicle\'s own default if it has one, else the shared value).') then V.clearOwnVal(kind, m, key) end
end
-- one fine-tuning value of vehicle m; true if the vehicle has its own
local function tuneSlider(item, m, id, label)
    local own = V.ownVal('detail', m, item.key)
    local dis = not m and disabledBegin()
    local c, v = slider(ownMark(own)..(label or tr(item.en))..'###'..id, V.valFor(m, item.key), item.lo, item.hi, '%.2f')
    disabledEnd(dis)
    local b = V.builtinVal('detail', m, item.key)
    ownTip(item.tipEn or '', m, own, string.format('%.2f', V.sharedVal(item.key)), string.format('%.2f', item.base), b and string.format('%.2f', b))
    if c and m then V.setOwnVal('detail', m, item.key, v) end
    ownReset(own, 'detail', m, item.key, id)
    return own ~= nil
end
-- body follow of vehicle m with character c (saved for that pair; else the vehicle's value)
local function followSlider(item, m, c, id, label)
    local own = V.followOwn(m, c, item.key)
    local cv, v = slider((own and tr('[vehicle+character] ') or '')..(label or tr(item.en))..'###'..id,
        V.followVal(m, c, item.key), item.lo, item.hi, '%.2f')
    local d = string.format('%.2f', V.pilotBuiltin(m, c, item.key) or V.valFor(m, item.key))
    local t = tr(item.tipEn or '')
    if own then
        tip(t..tr('\nSaved for this vehicle and character. Default: ')..d)
    else
        tip(t..tr('\nNot changed for this character: uses the default ')..d..tr('. Touch it and it is saved for this vehicle and character.'))
    end
    if cv then V.setFollowVal(m, c, item.key, v) end
    if own then
        imgui.same_line()
        if button(tr('default'), id..'x', 'Forgets the value for this vehicle and character.') then V.clearFollowVal(m, c, item.key) end
    end
    return own ~= nil
end
-- a % amount of vehicle m (banking or a shake group: { key, en, tipEn }); true if own
local function pctOwnSlider(p, m, id)
    local own = V.ownVal('feel', m, p[1])
    local dis = not m and disabledBegin()
    local c, v = slider(ownMark(own)..tr(p[2])..'###'..id, V.pctFor(m, p[1]), 0, 200, '%.0f %%')
    disabledEnd(dis)
    local b = V.builtinVal('feel', m, p[1])
    ownTip(p[3], m, own, tostring(round(V.sharedPct(p[1]))), '100', b and tostring(round(b)))
    if c and m then V.setOwnVal('feel', m, p[1], round(v)) end
    ownReset(own, 'feel', m, p[1], id)
    return own ~= nil
end
-- Fine tuning by topic, so everything about one thing (e.g. landings) is in one place, roughly in
-- the order it happens. A value not listed here still shows up, under "Other".
local TUNE_LAYOUT = {
    { 'engine', 'Engine', { 'idle', 'idleRev', 'cruise' } },
    { 'road', 'Road and corners', { 'road', 'bumps', 'corner', 'accel', 'drift', 'draft' } },
    { 'lunge', 'Boost lunge and nose lift',
      { 'ramjet', 'afterburner', 'launch', 'ebrake', 'lungeMax', 'fwdScale', 'nod', 'lowHum', 'heatShake' } },
    { 'boostfx', 'Boost screen, hit-stop, warp',
      { 'flashRJ', 'flashAB', 'satRJ', 'satAB', 'vigRJ', 'vigAB', 'fadeOut', 'hitstopStrength', 'hitstopAB', 'hitstopTime', 'warpAmount' } },
    { 'landing', 'Landings and hits',
      { 'airLift', 'landing', 'landFloor', 'landLean', 'landHit', 'landHitHz', 'headHitPitch', 'headHitRoll', 'headHitHz', 'nearLow', 'impact' } },
    { 'view', 'View (banking)', { 'rollAmount', 'rollMax' } },
    { 'spring', 'All shaking: head spring', { 'springHz', 'damping' } },
    { 'start', 'Race start', { 'leaveDelay', 'blendTime', 'carIdle', 'carRev' } },
}
local tuneGroups = nil
local function buildTuneGroups()
    local groups, listed = {}, {}
    for _, g in ipairs(TUNE_LAYOUT) do
        local items = {}
        for _, key in ipairs(g[3]) do
            local item = V.TUNE_INDEX[key]
            if item and not item.main then items[#items + 1] = item; listed[key] = true end
        end
        if #items > 0 then groups[#groups + 1] = { g[1], g[2], items } end
    end
    local rest = {}
    for _, item in ipairs(V.TUNABLES) do
        if not item.main and not listed[item.key] then rest[#rest + 1] = item end
    end
    if #rest > 0 then groups[#groups + 1] = { 'other', 'Other', rest } end
    return groups
end
-- every fine-tuning value of vehicle m, by topic (body follow / cut distance are in the View menu)
local function tuneTree(m, idp)
    tuneGroups = tuneGroups or buildTuneGroups()
    for _, g in ipairs(tuneGroups) do
        if section(tr(g[2]), idp..'g_'..g[1]) then
            local any = false
            for _, item in ipairs(g[3]) do any = tuneSlider(item, m, idp..item.key) or any end
            if any and button(tr('All of this group back to default'), idp..'all'..g[1],
                'Forgets the values you set for this vehicle in this group.') then
                for _, item in ipairs(g[3]) do V.clearOwnVal('detail', m, item.key) end
            end
            imgui.tree_pop()
        end
    end
end

local armReset = 0
local function drawMenu()
    local title = tr('STAR WARS Galactic Racer VR')..'  v'..V.VERSION
    if not section(title, 'swgrvr', 'VR cockpit for Galactic Racer. Hover over anything in this menu for an explanation.') then return end
    if V.oldScriptsFound then
        help('!! The old swgr_cockpit_*.lua scripts are still installed. Delete them from the scripts folder, then press Reset scripts.')
    end
    local ch = false

    -- all add-on effects on / off ----------------------------------------------------------------
    local cx, vx = checkbox(tr('Add-on effects on'), V.cfg.extras, 'extras',
        'The original cockpit script only puts you in the seat. Everything this package adds is switched by this box: cockpit shake and boost effects, banking limit, body follow on jumps, near clip, screen colours, the engine start shot and car body hum. Off = exactly like the original cockpit, handy to compare. (Eye position per vehicle, hotkeys and menu screen positions keep working.)')
    if cx then V.cfg.extras = vx; ch = true end
    if not V.cfg.extras then
        help('-> Add-on effects are OFF: the cockpit works like the original script.')
    end
    if V.hotkeyText('Extras') ~= tr('none') then
        imgui.text(string.format(tr('  On / off key: %s'), V.hotkeyText('Extras')))
    end

    -- camera mode, hotkeys, recenter ---------------------------------------------------------
    local m = combo(tr('View'), CAMERA_MODES, S.cameraMode, 'mode',
        'VR cockpit = you sit in the vehicle. Game cameras = the game\'s own third person / bonnet cameras (the cockpit effects are off there). The hotkey below switches too.')
    if m then S.setCameraMode(m) end
    imgui.text(string.format(tr('  Switch: %s    Next game camera: %s'),
        V.hotkeyText('Toggle'), V.hotkeyText('Cycle')))
    tip('Change the keys in "Hotkeys" below.')
    if button(tr('Recenter head at the seat'), 'recenter',
        'If you sit off-centre or too far forward / back: sit straight in your real chair and press this. Your current head position becomes the middle of the seat.') then S.recenter() end
    -- per-vehicle values: what you change while driving is saved for that vehicle only
    if V.model then
        imgui.text(string.format(tr('Vehicle: %s (%s)'), V.model, typeName(V.vtype))
            ..(V.pilot and string.format(tr('   Character: %s'), V.pilotLabel(V.pilot)) or ''))
        tip('The vehicle you are driving now (type / model).')
        help(string.format(tr('-> What you change now (eye position, banking, body follow, cut distance, shake, fine tuning) is saved for %s only. What you don\'t touch keeps its default.'), V.model))
    else
        help('-> No vehicle: the vehicle settings (eye position, banking, body follow, cut distance, shake, fine tuning) only show the defaults and can\'t be changed. Get into a vehicle to change them for it, or change a saved vehicle in "Saved vehicles" at the bottom.')
    end
    imgui.separator()

    -- view ---------------------------------------------------------------------------------------
    if section(tr('View and eye position'), 'view',
        'Where your eyes sit in the vehicle and how the view moves with it.') then
        do
            local locked = not V.model
            local e, ownEye = V.eyeFor(V.model)
            if locked then
                help('No vehicle yet: showing the default eye position. Get into a vehicle to adjust it; your change is saved for that vehicle.')
            else
                imgui.text(string.format(tr('Eye position (%s): %s'), V.model,
                    ownEye and tr('saved for this vehicle') or tr('default position')))
                tip('Saved automatically for the vehicle you drive as soon as you move a slider.')
            end
            local x, y, z = e[1], e[2], e[3]
            local dis = locked and disabledBegin()
            local c1, v1 = slider(tr('Sideways (cm)')..'##eyeX', x, -60, 60, '%.1f')
            tip('Moves your eyes left / right in the seat. Saved for this vehicle.')
            local c2, v2 = slider(tr('Forward / back (cm)')..'##eyeY', y, -100, 100, '%.1f')
            tip('Moves your eyes forward / back. Use it if the dashboard is too close or too far.')
            local c3, v3 = slider(tr('Up / down (cm)')..'##eyeZ', z, 0, 150, '%.1f')
            tip('Moves your eyes up / down. Use it if you feel you sit too low or too high.')
            disabledEnd(dis)
            if not locked and (c1 or c2 or c3) then V.setEye(c1 and v1 or x, c2 and v2 or y, c3 and v3 or z) end
            if ownEye and button(tr('Default eye for this vehicle'), 'eyeReset',
                'Forgets the eye position saved for this vehicle.') then V.resetEye() end
        end
        local l = combo(tr('Follow the vehicle'), LOCKS, S.cameraLock, 'lock',
            'How much the view tilts with the vehicle when it pitches over hills and leans in turns. Higher in the list = more comfortable, lower = more alive. If you get motion sick, pick "Level horizon".')
        if l then S.cameraLock = l; V.cfg.cameraLock = l; ch = true end
        pctOwnSlider(BANK, V.model, 'v_roll')
        local p = combo(tr('Pilot'), PILOT, S.pilotVisibility == 'visible' and V.cfg.pilot or S.pilotVisibility, 'pilot',
            'How much of your pilot you see in the cockpit. The head is in the same place as your eyes, so it is usually hidden.')
        if p then S.setPilotMode(p) end
        local c, v = checkbox(tr('Show the race intro flyover'), S.showCinematics, 'cine',
            'Before a race the game flies the camera over the track. On: you watch it with the game camera, then the cockpit takes over. Off: cockpit from the start.')
        if c then S.showCinematics = v; V.cfg.showCinematics = v; ch = true end
        c, v = checkbox(tr('Outside view when crashing'), S.showCrashCamera, 'crash',
            'On: when you crash or tumble, the game\'s crash camera shows the wreck from outside. Off: you stay in the cockpit (can be wild).')
        if c then S.showCrashCamera = v; V.cfg.showCrashCamera = v; ch = true end
        c, v = checkbox(tr('Follow the pilot on jumps'), V.cfg.bodyFollow, 'follow',
            'On jumps (mostly bikes) the rider stands up in the air. Your eyes stay at the seat, so you would end up inside the rider\'s body. On: your eyes move with the body while airborne.')
        if c then V.cfg.bodyFollow = v; ch = true end
        if V.cfg.bodyFollow then
            if V.model and V.pilot then
                imgui.text(string.format(tr('  Saved for this vehicle and character (%s)'), V.pilotLabel(V.pilot)))
                tip('Characters differ in build and posture, so the same vehicle can need other values for each character.')
            end
            for _, key in ipairs(FOLLOW_KEYS) do
                local item = V.TUNE_INDEX[key]
                if V.model and V.pilot then followSlider(item, V.model, V.pilot, 'v_'..key, '  '..tr(item.en))
                else tuneSlider(item, V.model, 'v_'..key, '  '..tr(item.en)) end
            end
        end
        c, v = checkbox(tr('Cut what is right at the eye'), V.cfg.nearClip, 'near',
            'The pilot body is right next to your eyes. On landings and jumps it can fill your view from the inside. On: anything a few centimetres from your eyes is not drawn, so you see past it. Hands and handlebars further out stay.')
        if c then V.cfg.nearClip = v; ch = true end
        if V.cfg.nearClip then
            local item = V.TUNE_INDEX.near
            tuneSlider(item, V.model, 'v_near', '  '..tr(item.en))
        end
        imgui.tree_pop()
    end

    -- shake --------------------------------------------------------------------------------------
    if section(tr('Cockpit shake'), 'feel',
        'The view moves like your head would in a real racer: engine, road, corners, boosts, landings. Five amounts: 100 = recommended, 0 = off, 200 = double. Each one is explained when you hover over it.') then
        local c, v = checkbox(tr('On'), V.cfg.feelOn, 'feelOn',
            'All cockpit shake and boost punch at once. Off = a perfectly still cockpit. If you feel motion sick, try this first.')
        if c then V.cfg.feelOn = v; ch = true end
        local vm, anyOwn = V.model, false
        for _, f in ipairs(FEEL) do anyOwn = pctOwnSlider(f, vm, 'f'..f[1]) or anyOwn end
        c, v = checkbox(tr('Landing hits your head'), V.cfg.headHit, 'headHit',
            'The usual landing moves your view down, which feels like the vehicle jolts while your head stays still. This also snaps the view angle down and back with a little sideways wobble at touchdown, so it feels like your head takes the hit. Fine tuning > Landings and hits has its values.')
        if c then V.cfg.headHit = v; ch = true end
        if anyOwn and button(tr('This vehicle: all shake back to default'), 'feelShared',
            'Forgets the shake amounts you set for this vehicle; back to its defaults.') then
            for _, g in ipairs(V.FEEL_GROUPS) do V.clearOwnVal('feel', vm, g) end
        end
        imgui.tree_pop()
    end

    -- boost effects ------------------------------------------------------------------------------
    if section(tr('Boost effects'), 'boostfx',
        'Extra effects when you fire the afterburner or the ramjet, or at the race start.') then
        ch = pctSlider(tr('Screen colours and flash'), V.cfg, 'screen', 'screen',
            'While boosting the colours get stronger and the screen edges darker, with a short flash when it starts; then it eases back. 0 = off, 100 = recommended.') or ch
        local c, v = checkbox(tr('Hit-stop at ramjet / race start'), V.cfg.hitstop, 'hitstop',
            'The trick of action games: at ramjet ignition and the race start the whole game slows down for a split second, then snaps back to full speed. Feels like a punch.')
        if c then V.cfg.hitstop = v; ch = true end
        c, v = checkbox(tr('Warp pulse at ramjet / race start'), V.cfg.warp, 'warp',
            'At ramjet ignition and the race start the size of the world pulses for a moment (VR world scale), like the speed kick the flat game does by widening the screen.')
        if c then V.cfg.warp = v; ch = true end
        imgui.tree_pop()
    end

    -- race start ---------------------------------------------------------------------------------
    if section(tr('Race start'), 'intro',
        'What happens before the race: the engine start shot and how you get into the cockpit.') then
        local c, v = checkbox(tr('Show the engine start, then move into the cockpit'), V.cfg.intro, 'intro',
            'Before the race the game shows your engine starting from outside. On: you watch it, and shortly after the engine starts the view flies smoothly into your seat. Off: cockpit the whole time.')
        if c then V.cfg.intro = v; ch = true end
        ch = pctSlider(tr('Car body engine hum (game cameras)'), V.cfg, 'carShake', 'carShake',
            'Seen from outside (the engine start shot, third person) the vehicle body sits perfectly still even with the engine running. This makes it hum and shake when you rev. 0 = off.') or ch
        imgui.tree_pop()
    end

    -- fine tuning (every single value) -------------------------------------------------------------
    if section(tr('Fine tuning (advanced)'), 'fine',
        'For people who want to go deeper: every single value behind the simple settings above. You don\'t need this.') then
        help('Every single value. The amounts in "Cockpit shake" and "Banking" are applied on top of these (they multiply). 0 turns an effect off. Hover for details and the recommended value.')
        if V.model then
            help(string.format(tr('Driving %s: a value you change is saved for this vehicle only ("[vehicle]"); the others keep their defaults.'), V.model))
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
    if section(string.format(tr('Saved vehicles (%d)'), #names), 'vehicles',
        'Every vehicle with something saved. Open one to see and change all its values without driving it: untouched values keep their defaults, a value you touch is saved for that vehicle.') then
        local AX = { { 'Sideways (cm)', -60, 60 }, { 'Forward / back (cm)', -100, 100 }, { 'Up / down (cm)', 0, 150 } }
        for _, name in ipairs(names) do
            if section(name..(name == V.model and tr('  (driving now)') or ''), 'veh'..name) then
                local e, ownEye = V.eyeFor(name)
                imgui.text(ownEye and tr('Eye position (saved for this vehicle):') or tr('Eye position (default):'))
                for i, a in ipairs(AX) do
                    local c, v = slider(tr(a[1])..'##ve'..name..i, tonumber(e[i]) or 0, a[2], a[3], '%.1f')
                    if c then
                        local ne = { tonumber(e[1]) or 0, tonumber(e[2]) or 0, tonumber(e[3]) or 0 }
                        ne[i] = v
                        V.veh.eyes[name] = ne; V.saveVeh()
                        if name == V.model then S.setEye(ne[1], ne[2], ne[3]) end
                        e = ne
                    end
                end
                if ownEye and button(tr('Default eye'), 'ved'..name, 'Forgets this vehicle\'s eye position.') then V.resetEye(name) end
                imgui.text(tr('Banking, body follow on jumps, cut distance:'))
                pctOwnSlider(BANK, name, 'vb'..name)
                for _, key in ipairs(VEH_KEYS) do
                    local item = V.TUNE_INDEX[key]
                    local label = (key ~= 'near') and tr(item.en)..tr(' (any character)') or nil
                    tuneSlider(item, name, 'vm'..name..key, label)
                end
                -- characters' own body follow: folded, so a vehicle many characters drove stays tidy
                local pf = V.veh.pilotFollow[name]
                if type(pf) == 'table' and next(pf) ~= nil then
                    local chars = {}
                    for c in pairs(pf) do chars[#chars + 1] = c end
                    table.sort(chars)
                    if section(string.format(tr('Body follow per character (%d)'), #chars), 'vpc'..name,
                        'Body follow on jumps saved for this vehicle with each character. Open a character to change or forget its values.') then
                        for _, c in ipairs(chars) do
                            local now = (name == V.model and c == V.pilot) and tr('  (driving now)') or ''
                            if section(V.pilotLabel(c)..now, 'vpc'..name..'/'..c) then
                                for _, key in ipairs(FOLLOW_KEYS) do followSlider(V.TUNE_INDEX[key], name, c, 'vp'..name..c..key) end
                                if button(tr('Forget this character\'s values'), 'vpcx'..name..c,
                                    'This character uses the vehicle\'s body follow again.') then
                                    V.clearFollowVal(name, c)
                                end
                                imgui.tree_pop()
                            end
                        end
                        imgui.tree_pop()
                    end
                end
                imgui.text(tr('Shake:'))
                for _, fg in ipairs(FEEL) do pctOwnSlider(fg, name, 'vf'..name..fg[1]) end
                local n, vd = 0, V.veh.detail[name]
                if type(vd) == 'table' then
                    for k in pairs(vd) do local item = V.TUNE_INDEX[k]; if item and not item.main then n = n + 1 end end
                end
                if section(string.format(tr('Advanced options (fine tuning) - %d changed'), n), 'vadv'..name,
                    'Every fine-tuning value this vehicle uses. Untouched = its default; touch one and it is saved for this vehicle ("[vehicle]").') then
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
                if resettable and button(tr('Everything back to default (eye position and body follow stay)'), 'vfd'..name,
                    'Forgets the banking, cut distance, shake and fine tuning you set for this vehicle; back to the defaults. Eye position and body follow on jumps (any character and per character) stay.') then
                    if type(vdd) == 'table' then
                        local keep = { followUp = vdd.followUp, followFwd = vdd.followFwd }
                        V.veh.detail[name] = next(keep) ~= nil and keep or nil
                    end
                    V.clearOwnVal('feel', name)
                    V.saveVeh()
                end
                if button(tr('Forget everything I set for this vehicle'), 'vdel'..name, 'Forgets everything you set for this vehicle (eye position too); it goes back to its defaults.') then
                    V.veh.eyes[name], V.veh.feel[name], V.veh.detail[name], V.veh.pilotFollow[name] = nil, nil, nil, nil
                    V.saveVeh()
                    if name == V.model then V.resetEye(name) end
                end
                imgui.tree_pop()
            end
        end
        if #names == 0 then imgui.text(tr('  (none yet - change something while driving)')) end
        imgui.tree_pop()
    end

    -- hotkeys ------------------------------------------------------------------------------------
    if section(tr('Hotkeys'), 'hotkeys',
        'Keys / controller buttons for switching cameras, recentering and switching the add-on effects. Each action can have a keyboard key and a controller combo.') then
        local padNames = {}
        for i, pd in ipairs(V.HOTKEY_PADS) do padNames[i] = { pd[1], pd[1], pd[1] } end
        help('Keyboard: click the button, then press the key you want (Esc = cancel). Controller: pick a combo from the list.')
        V.keyCaptureSeen = V.t                 -- the menu is open: a key capture may go on
        for _, a in ipairs(V.HOTKEY_ACTIONS) do
            imgui.text(tr(a.en))
            local key = V.cfg['key'..a.id]
            local bound = key ~= nil and key ~= 'None'
            local waiting = V.keyCapture == a.id
            local label = waiting and tr('Press any key... (Esc = cancel)')
                or string.format(tr('Keyboard: %s'), bound and key or tr('none'))
            if button(label, 'k'..a.id, 'Click, then press the key for this. (Insert is the UEVR menu key and can\'t be used.) A key already used by another action moves to this one.') then
                if waiting then V.keyCapture = nil else V.keyCaptureStart(a.id) end
            end
            if bound and not waiting then
                imgui.same_line()
                if button(tr('Clear'), 'kc'..a.id, 'No keyboard key for this.') then
                    V.cfg['key'..a.id] = 'None'; ch = true
                end
            end
            local pd = combo(tr('  Controller'), padNames, V.cfg['pad'..a.id], 'p'..a.id,
                'Hold the Back (View) button and press the second button. The game may also react to that button, so pick one you don\'t use while racing.')
            if pd then V.cfg['pad'..a.id] = pd; ch = true end
        end
        imgui.tree_pop()
    end

    -- menu screen positions ------------------------------------------------------------------------
    if section(tr('Menu screen positions'), 'views',
        'Fixes menus where your VR view ends up in a strange place (open it to see how).') then
        help('Some menu and result screens put the game camera in a strange place: in VR you then stand under the map, inside a wall or far away. For those screens a saved VR camera position is applied automatically. The usual ones are already included. Not used in races.')
        help('A screen looks wrong? 1) On that screen open UEVR menu > Camera > Camera Offset and move it until it looks right. 2) Press "Save" below. From then on it is applied every time that screen appears.')
        local c, v = checkbox(tr('Apply saved positions'), V.cfg.viewOffsets, 'viewsOn',
            'Off: no screen gets a saved position.')
        if c then V.cfg.viewOffsets = v; ch = true end
        local key = V.viewState.currentKey
        if key then
            local k, auto = V.viewLookup(key)
            local n = k and V.VIEW_NAMES[k]
            imgui.text(tr('Current screen: ')..(n and tr(n[1]) or key)..(auto and tr(' (same camera, other map)') or ''))
            tip('The camera of the screen you are on now. "Same camera, other map": result screens share one camera on every map, so one saved position works everywhere.')
            if button(tr('Save the current UEVR camera offset for this screen'), 'viewSave',
                'Saves what you set in UEVR menu > Camera > Camera Offset for this screen.') then V.viewSaveCurrent() end
            if k and not auto then
                local isDefault = V.viewDefaults[k] ~= nil
                if button(isDefault and tr('Back to the built-in position') or tr('Forget this screen'), 'viewForget',
                    'Removes what you saved for this screen (built-in screens go back to their built-in position).') then V.viewForget(k) end
            end
        else
            imgui.text(tr('Current screen: race / vehicle camera (not handled)'))
        end
        imgui.tree_pop()
    end

    -- reset everything (press twice) ---------------------------------------------------------------
    imgui.separator()
    local armed = V.t < armReset
    if button(armed and tr('Press again to reset ALL settings') or tr('Reset all settings'), 'resetAll',
        'All settings and fine tuning back to the recommended values (press twice). Saved vehicles stay; delete them in "Saved vehicles".') then
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
