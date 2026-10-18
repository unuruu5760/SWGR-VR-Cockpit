-- The menu (UEVR > Script UI): a few big groups, amounts in % (100 = recommended).
local log = V.logger('menu')
local S = V.cam
local tr = V.tr

-- colours (ABGR): test features yellow, values saved for a vehicle light blue, warnings orange,
-- explanations grey, the ride shake and motion-sickness warnings red. Plain white text if this UEVR
-- build can't colour.
local COL = { test = 0xFF5ADCFF, own = 0xFFFFC878, warn = 0xFF3CA0FF, info = 0xFFB4B4B4, danger = 0xFF5A5AFF, head = 0xFF96DCFF }
local function colorText(text, col)
    if not pcall(imgui.text_colored, text, col) then imgui.text(text) end
end
-- colour of the next widget's label (and value); true if pushed, to be popped with popColor
local function pushColor(col)
    if not col then return false end
    local signed = col >= 0x80000000 and col - 0x100000000 or col      -- (the binding takes an int)
    local ok = pcall(imgui.push_style_color, 0, signed)                  -- (0 = ImGuiCol_Text)
    return ok
end
local function popColor(pushed) if pushed then pcall(imgui.pop_style_color, 1) end end

-- Rows: [slider / combo][reset][label]. The reset is a small arrow, there while the value differs from
-- its default (reset = { fn = what it does, def = the default as text }); without one its place stays
-- empty, so all the labels line up (2026-10-17: the "default" button after a label took room and got
-- cut off). The row's tooltip shows while the widget or its label is hovered (pendingHover, read by
-- the next tip); a label cut off at the window's edge is shown on top of it (pendingCut).
local pendingCut, pendingHover = nil, nil
local function tip(en)
    local cut, hov = pendingCut, pendingHover
    pendingCut, pendingHover = nil, nil
    if hov == nil then
        if not cut then return V.tip(en) end
        local ok, h = pcall(imgui.is_item_hovered)
        hov = ok and h
    end
    if not hov then return end
    local t = tr(en)
    pcall(imgui.set_tooltip, V.wrap(cut and (t ~= '' and cut..'\n'..t or cut) or t))
end

-- Widget width: ImGui sliders / combos fill the line and push their label off the right edge.
-- With set_next_item_width they all end at the same place: the label column on the right is as wide
-- as the widest label (with the reset place) of the last frame, at most LABEL_MAX of the window, so
-- the sliders line up and widening the window shows the whole labels; a label that still doesn't fit
-- is shown on top of its tooltip. Sliders are at least MIN_W wide. Without calc_text_size: "full
-- width minus LABEL_W". Else push_item_width around the whole menu, else the label is written on its
-- own line above the widget (and a reset is a "default" button after it).
local LABEL_W, MIN_W, LABEL_MAX = 270, 110, 0.6
local labelCol, labelColNow = LABEL_W, 0      -- the label column of the last frame / widest one so far
local widthMode = nil                      -- 'next' / 'push' / 'above'
local function detectWidthMode()
    local okN, fnN = pcall(function() return imgui.set_next_item_width end)
    if okN and type(fnN) == 'function' then return 'next' end
    local okP, fnP = pcall(function() return imgui.push_item_width end)
    local okQ, fnQ = pcall(function() return imgui.pop_item_width end)
    if okP and okQ and type(fnP) == 'function' and type(fnQ) == 'function' then return 'push' end
    return 'above'
end
-- the reset place: a square of the widget's height
local function slotSize()
    local ok, h = pcall(function() return imgui.calc_text_size('A').y end)
    return (ok and tonumber(h) or 16) + 6
end
-- before a row's widget: its width (or, 'above', the label on its own line); returns the widget's id label
local function rowStart(text, id, col)
    pendingCut, pendingHover = nil, nil
    if widthMode == 'next' then
        local ok = pcall(function()
            local tw = imgui.calc_text_size(text).x + slotSize() + 8
            if tw > labelColNow then labelColNow = tw end
            local right = imgui.get_window_size().x - 30                   -- (padding, scroll bar)
            local cx = imgui.get_cursor_pos().x
            local cw = math.min(labelCol, right * LABEL_MAX)
            local w = math.max(MIN_W, right - cx - cw - 12)
            imgui.set_next_item_width(w)
            if cx + w + 12 + tw > right then pendingCut = text end
        end)
        if not ok then pcall(function() imgui.set_next_item_width(-LABEL_W) end) end
    elseif widthMode == 'above' then
        if not pcall(imgui.text_colored, text, col) then imgui.text(text) end
    end
    return '##'..id
end
-- after a row's widget (hov: the widget was hovered): the reset and the label
local function rowEnd(text, id, reset, col, hov)
    if widthMode == 'above' then
        if reset then
            imgui.same_line()
            if imgui.button(tr('default')..'##r'..id) then reset.fn() end
        end
        pendingHover = hov
        return
    end
    imgui.same_line()
    if reset then
        if imgui.arrow_button('##r'..id, 0) then reset.fn() end          -- (0 = an arrow to the left)
        local okR, hovR = pcall(imgui.is_item_hovered)
        if okR and hovR then pcall(imgui.set_tooltip, tr('Back to default')..(reset.def and (': '..reset.def) or '')) end
    else
        local s = slotSize()
        pcall(imgui.invisible_button, '##e'..id, { s, s })
    end
    imgui.same_line()
    local pushed = pushColor(col)
    imgui.text(text)
    popColor(pushed)
    local okL, hovL = pcall(imgui.is_item_hovered)
    pendingHover = hov or (okL and hovL) or false
end
local function hovered()
    local ok, h = pcall(imgui.is_item_hovered)
    return ok and h or false
end

-- slider row with a value format when this UEVR build supports it (falls back to the plain slider).
-- label: 'text##id' (or ###id); reset: see above; col: the label's colour
local fmtOK = nil
local function slider(label, value, lo, hi, fmt, reset, col)
    local text = label:match('^(.-)##') or label
    local id = label:match('##+(.*)$') or label
    local wl = rowStart(text, id, col)
    local c, v
    if fmt and fmtOK ~= false then
        local ok, c1, v1 = pcall(imgui.slider_float, wl, value, lo, hi, fmt)
        if ok then fmtOK = true; c, v = c1, v1 else fmtOK = false end
    end
    if c == nil then c, v = imgui.slider_float(wl, value, lo, hi) end
    rowEnd(text, id, reset, col, hovered())
    return c, v
end
local function round(x) return math.floor(x + 0.5) end
-- a reset to def for a value of a table (nil while it is at its default)
local function resetTo(tbl, key, def, fmt)
    local cur = tonumber(tbl[key])
    if cur == nil or math.abs(cur - def) < 0.0005 then return nil end
    return { fn = function() tbl[key] = def; V.save() end, def = string.format(fmt or '%g', def) }
end
-- percent slider bound to a table field (in V.cfg: back to its default); returns true when changed
local function pctSlider(label, tbl, key, id, tipEn)
    local def = (tbl == V.cfg and tonumber(V.DEFAULTS[key])) or 100
    local c, v = slider(label..'##'..id, tonumber(tbl[key]) or def, 0, 200, '%.0f %%', resetTo(tbl, key, def, '%.0f'))
    if tipEn then tip(tipEn) end
    if c then tbl[key] = round(v); return true end
    return false
end
local function checkbox(label, value, id, tipEn, col)
    pendingCut, pendingHover = nil, nil
    local pushed = pushColor(col)
    local c, v = imgui.checkbox(label..'##'..id, value)
    popColor(pushed)
    if tipEn then tip(tipEn) end
    return c, v
end
local function combo(label, list, current, id, tipEn, col)
    local idx = 1
    for i, item in ipairs(list) do if item[1] == current then idx = i end end
    local names = {}
    for i, item in ipairs(list) do names[i] = tr(item[2]) end
    local wl = rowStart(label, id, col)
    local pushed = pushColor(col)
    local c, v = imgui.combo(wl, idx, names)
    popColor(pushed)
    rowEnd(label, id, nil, col, hovered())
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
local function section(label, id, tipEn, col)
    pendingCut, pendingHover = nil, nil
    local pushed = pushColor(col)
    local open = imgui.tree_node(label..'###'..id)
    popColor(pushed)
    if tipEn then tip(tipEn) end
    return open
end
local function button(label, id, tipEn)
    pendingCut, pendingHover = nil, nil
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
local function help(en, col)
    for line in (V.wrap(tr(en))..'\n'):gmatch('(.-)\n') do colorText('  '..line, col or COL.info) end
end
-- (no "%" in imgui.text / tooltips: some UEVR builds treat that text as a format string)

local CAMERA_MODES = {
    { 'cockpit', 'VR cockpit' },
    { 'game', 'Game cameras (third person / bonnet)' },
}
local LOCKS = {
    { 'track', '1. Level horizon' },
    { 'hills', '2. Follow hills (most comfortable)' },
    { 'smooth', '3. Follow the vehicle, smoothed (recommended)' },
    { 'light', '4. Follow the vehicle, lightly smoothed' },
    { 'pilot', '5. Exactly like the vehicle (motion sickness!)' },
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
-- the shaking-along amounts in the Cockpit shake section (saved per vehicle)
local ALONG_SLIDERS = {
    { 'shakeAlong', '  Trembling: world share' },
    { 'shakeAlongMove', '  Sways: world share' },
    { 'shakeAlongSmooth', '  Smooth: driving' },
    { 'shakeAlongSmooth2', '  Smooth: boosts and hits' },
    { 'shakeAlongAir', '  Trembling in the air' },
    { 'shakeAlongLand', '  Landing slam' },
}
local FOLLOW_KEYS = { 'followUp', 'followFwd' }
-- the ride shake values have no recommended value (what is fine differs from person to person)
for _, k in ipairs({ 'alongTilt', 'shakeAlong', 'shakeAlongMove', 'shakeAlongSmooth', 'shakeAlongSmooth2', 'shakeAlongAir', 'shakeAlongLand' }) do
    if V.TUNE_INDEX[k] then V.TUNE_INDEX[k].noRec = true end
end
-- picture per track and weather: { key, label, lo, hi, format, description }; the older controls folded
-- apart (PIC_MORE: kept for the values saved with them)
local PIC_ROWS = {
    { 'picExp', 'Brightness', -3, 2, '%.1f',
      'The whole picture darker or brighter, in camera stops: -1 = half as bright, +1 = double. 0 = as the game does it.', 'Light' },
    { 'picUncap', 'Keep bright skies from turning white', 0, 1, 'check',
      'In some places (under the big wrecks) the game does not let the picture get darker than a set level, so the bright sky beyond turns white - a little further on it is fine again. Ticked: that limit is lifted, the game darkens for the sky as it does everywhere else.' },
    { 'picPair', 'Expose for the bright outside, keep the inside', 0, 100, '%.0f %%',
      'One slider for the two set by hand: the game brightens dark views less (Tunnels: brighten no further than, here 8 to 15), so the bright outside seen from a tunnel or from under a wreck does not turn white; and the dark tones are lifted back by about as much, so the inside stays near what it was. 0 = off.' },
    { 'picPairLift', '  Inside lifted back with it', 0, 200, '%.0f %%',
      'How much the dark parts are lifted back with it: 100 = about as much as they were darkened, more = brighter inside, less = darker. The game\'s own brightening can\'t be read, so it is near, not exact.' },
    { 'picPairCap', '  Lamps, deep dark: not lifted too far', 0, 1, 'check',
      'Lifting back goes no further than what the game\'s brightening was held back by. Without it the darkest parts are lifted the most (a lamp\'s soft light in a dark tunnel, deep shadows), past the game\'s own picture. Works on the part lifted by brightness (Keep the inside\'s contrast below 100).' },
    { 'picFusion', '  Lift by blending two pictures (Fusion)', 0, 1, 'check',
      'The engine\'s other way of lifting by the area around (for Keep the inside\'s contrast, Lift dark places, Tunnels and glare): it makes a darker and a brighter picture and takes each part from the one where it is neither too bright nor too dark, so a lamp too bright in the brighter one is taken from the darker one. New in the engine, not tried in this game: if it looks wrong, untick.' },
    { 'picPairKeep', '  Keep the inside\'s contrast', 0, 100, '%.0f %%',
      'How the inside is lifted back: 0 = each part by its own brightness (the inside looks flatter), 100 = by the area around it (the inside keeps its contrast, the way it was before). The soft glow around lamps grows either way: lifting the dark while keeping the bright down brightens the lamp\'s fading light too.' },
    { 'picTunnel', 'Tunnels: less glare from outside', 0, 200, '%.0f %%',
      'Only in tunnels (the game\'s own narrow indoor areas): the bright outside seen from inside is toned down, the inside stays as it is. Out in the open, or under a big roof open at the sides: the game\'s own picture. 100 = strong, 200 = the most there is. 0 = off.' },
    { 'picGlare', 'Tone down glaring places (everywhere)', 0, 200, '%.0f %%',
      'Everywhere, out in the open too: only the very bright places (sky, sunlit sand) get darker. A sunny day can look overcast with it; for tunnels alone use Tunnels. 100 = strong, 200 = the most there is. 0 = as the game does it.' },
    { 'picShadow', 'Lift dark places', 0, 100, '%.0f %%',
      'Only the dark places (shadows, night, the cockpit) get brighter; the bright ones stay. 0 = as the game does it.' },
    { 'picBlack', 'Deeper blacks', 0, 300, '%.0f %%',
      'Takes off the grey haze: the darkest parts go black, the bright ones stay (like ReShade\'s Levels). Against the headset\'s washed-out look. 0 = as the game does it.', 'Colour' },
    { 'picVib', 'Vibrance', 0, 100, '%.0f %%',
      'More colour in the washed-out parts (sky, sunlit sand). The engine can only raise colour by brightness, not by how pale a colour is, so bright lights (lamps, candles) get stronger too - keep it moderate. 0 = as the game does it.' },
    { 'picTemp', 'Colour temperature', -250, 250, '%.0f',
      'Minus = cooler (bluer), plus = warmer (yellower). 0 = as the game does it.' },
    { 'picBloom', 'Bloom (glow around bright things)', 0, 200, '%.0f %%',
      'The glow that spreads around bright things. In VR it can fog the whole view. 0 = no glow, 100 = as the game does it.' },
    { 'picSat', 'Colour strength (saturation)', 50, 200, '%.0f %%',
      'How strong the colours are. Above 100 = stronger colours. 100 = as the game does it.' },
    { 'picCon', 'Contrast', 50, 150, '%.0f %%',
      'Difference between dark and bright. Above 100 = darker darks, brighter brights. 100 = as the game does it.' },
    { 'picLampCard', 'Round glow card by lamps', 0, 100, '%.0f %%',
      'The soft round glow card the game puts by its standing lamps, as bright as set here. 100 = as the game does it, 0 = none. Set on the lamp itself, so the game keeps it.', 'Lamps' },
    { 'picLampAir', 'Lamp light in the air', 0, 100, '%.0f %%',
      'How much each lamp\'s light shows in the air around it (the fog it lights; these lamps have it strong). 100 = as the game does it, 0 = none. Set on the lamp itself, so the game keeps it.' },
}
local PIC_MORE = {
    { 'picLow', 'Tunnels (older): leave out the dark part', 0, 98, '%.0f',
      'The older tunnel control: it only starts to work above about 92. 0 = as the game does it.' },
    { 'picMinEV', 'Tunnels: brighten no further than', 0, 15, '%.1f',
      'Dark places are not brightened beyond this (camera EV: higher = it stops sooner); bright places are not touched. If the outside in daylight also gets darker, it is too high. 0 = as the game does it.' },
    { 'picHi', 'Bright parts (colour gain)', 30, 150, '%.0f %%',
      'The older way to darken bright parts: it multiplies their colour, so far down they turn grey. Tone down glaring places does it better. 100 = as the game does it.' },
}
-- the shake master amounts are per vehicle type; the type they show (the one driven, else picked)
local MASTER_TYPES = { { 'Bike', 'Bike' }, { 'Car', 'Landspeeder' }, { 'Skimmer', 'Skimmer' }, { 'Plane', 'Podracer' } }
local masterType, masterSeen = 'Bike', nil
local rideType, rideSeen = 'Bike', nil         -- (the ride shake masters: their own type, apart)
local VEH_KEYS = { 'followUp', 'followFwd', 'near' }   -- shown in each saved vehicle

-- Values saved per vehicle. m = the vehicle (the one driven, or one in "Saved vehicles"). Without a
-- vehicle the widget is greyed out, shows the shared value and can't be changed. Only a value the
-- user changes is stored for the vehicle ("[vehicle]"); the others keep following the shared value.
local function ownMark(own) return own and tr('[vehicle] ') or '' end
-- builtin: this vehicle's built-in default as text (nil = none, it uses the shared value)
-- rec nil: no recommended value (the ride shake: what is fine differs from person to person)
local function ownTip(tipEn, m, own, shared, rec, builtin)
    local note
    if not m then
        note = tr('Get into a vehicle to change it (saved for that vehicle).')
    elseif own then
        note = tr('Saved for this vehicle. Default: ')..(builtin or shared)..(builtin and tr(' (this vehicle)') or tr(' (shared)'))
            ..(rec and tr(', recommended: ')..rec or '')
    elseif builtin then
        note = tr('This vehicle\'s own default (shared value: ')..shared
            ..(rec and tr('). Touch it and your value is saved for this vehicle. Recommended: ')..rec
                or tr('). Touch it and your value is saved for this vehicle.'))
    else
        note = rec and tr('Not changed for this vehicle: follows the shared value. Touch it and it is saved for this vehicle. Recommended: ')..rec
            or tr('Not changed for this vehicle: follows the shared value. Touch it and it is saved for this vehicle.')
    end
    local t = tr(tipEn)
    tip(t ~= '' and t..'\n'..note or note)
end
-- one fine-tuning value of vehicle m; true if the vehicle has its own
local function tuneSlider(item, m, id, label, fmt, col, noRec)
    fmt = fmt or '%.2f'
    noRec = noRec or item.noRec
    local own = V.ownVal('detail', m, item.key)
    local tf = fmt:gsub(' ?%%%%', '')            -- (the tooltip: no percent sign)
    local b = V.builtinVal('detail', m, item.key)
    local reset = own and { fn = function() V.clearOwnVal('detail', m, item.key) end,
        def = string.format(tf, b or V.sharedVal(item.key)) }
    local dis = not m and disabledBegin()
    local c, v = slider(ownMark(own)..(label or tr(item.en))..'###'..id, V.valFor(m, item.key), item.lo, item.hi, fmt, reset, col or (own and COL.own))
    disabledEnd(dis)
    if fmt:sub(1, 4) == '%.0f' then v = round(v) end
    ownTip(item.tipEn or '', m, own, string.format(tf, V.sharedVal(item.key)), not noRec and string.format(tf, item.base) or nil, b and string.format(tf, b))
    if c and m then V.setOwnVal('detail', m, item.key, v) end
    return own ~= nil
end
-- body follow of vehicle m with character c (saved for that pair; else the vehicle's value)
local function followSlider(item, m, c, id, label)
    local own = V.followOwn(m, c, item.key)
    local d = string.format('%.2f', V.pilotBuiltin(m, c, item.key) or V.valFor(m, item.key))
    local reset = own and { fn = function() V.clearFollowVal(m, c, item.key) end, def = d }
    local cv, v = slider((own and tr('[vehicle+character] ') or '')..(label or tr(item.en))..'###'..id,
        V.followVal(m, c, item.key), item.lo, item.hi, '%.2f', reset, own and COL.own)
    local t = tr(item.tipEn or '')
    if own then
        tip(t..tr('\nSaved for this vehicle and character. Default: ')..d)
    else
        tip(t..tr('\nNot changed for this character: uses the default ')..d..tr('. Touch it and it is saved for this vehicle and character.'))
    end
    if cv then V.setFollowVal(m, c, item.key, v) end
    return own ~= nil
end
-- a % amount of vehicle m (banking or a shake group: { key, en, tipEn }); true if own
-- a picture value of place m (nil = none yet: greyed out); saved for that place, light blue when it has one
-- (m = '*': the value for every track and weather; a place's own one goes back to that one)
local function picSlider(m, r, idp)
    local key, fmt = r[1], r[5]
    local f = fmt == '%.1f' and '%.1f' or '%.0f'
    local own, value, back, set
    if m == '*' then
        own, value, back = V.picBaseOwn(key), V.picBase(key), V.PIC_NEUTRAL[key]
        set = function(x) V.setPicBase(key, x) end
    else
        own, value, back = m and V.picOwn(key, m), V.picVal(key, m or '?'), V.picBase(key)
        set = function(x) if m then V.setPicVal(m, key, x) end end
    end
    if fmt == 'check' then
        -- (an on / off value: 1 / 0)
        local c, v = checkbox(tr(r[2]), value > 0.5, idp..key, r[6], own and COL.own)
        if c then set(v and 1 or 0) end
        return
    end
    local reset = own and { fn = function() set(back) end, def = string.format(f, back) }
    local c, v = slider(tr(r[2])..'##'..idp..key, value, r[3], r[4], fmt, reset, own and COL.own)
    tip(r[6])
    if c then set(fmt == '%.1f' and math.floor(v * 10 + 0.5) / 10 or round(v)) end
end
-- every picture slider of place m, the older controls folded below (open-coloured when one is in use)
local function picRows(m, idp)
    local group = nil
    for _, r in ipairs(PIC_ROWS) do
        group = r[7] or group
        -- (a public build leaves out the options still being worked on; a group's name goes with its first row shown)
        local shown = V.PIC_LAB or not V.PIC_LAB_KEYS[r[1]]
        if shown and group then colorText(tr(group), COL.info); group = nil end   -- (Light, Colour)
        if shown then picSlider(m, r, idp) end
        -- (Tunnels on the place raced now: whether you are closed in right now)
        if shown and r[1] == 'picTunnel' and m and m ~= '*' and m == V.picPlace() and V.picVal('picTunnel', m) > 0.5 then
            local hit, d = V.picRoof()
            colorText('    '..(hit == nil and tr('The game\'s areas could not be read on this map: no Tunnels here (see the log)')
                or hit and tr('Now: in a tunnel (Tunnels on)') or tr('Now: not in a tunnel')), COL.info)
            if hit ~= nil then
                -- (the game's area the vehicle is in: indoor / outdoor, how wide, its name)
                local short = d and d.name:gsub('^SAD_%a+_Tracks_', ''):gsub('^SAD_', '') or nil
                colorText('    '..(not d and tr('Game area: none (outdoors)')
                    or d.skipped and string.format(tr('Game area: named open by the game, left out (%s)'), short)
                    or not d.interior and string.format(tr('Game area: outdoors (%s)'), short)
                    or d.narrow <= V.AREA_WIDE_M * 100 and string.format(tr('Game area: indoors, %d m across (%s)'), math.floor(d.narrow / 100 + 0.5), short)
                    or string.format(tr('Game area: indoors, over %d m across (%s)'), V.AREA_WIDE_M, short)), COL.info)
            end
        end
    end
    local used = false
    for _, r in ipairs(PIC_MORE) do if m and V.picOwn(r[1], m) then used = true end end
    if section(tr('More (older controls)')..(used and tr('  (in use)') or ''), idp..'more',
        'Older ways to tame tunnels and bright parts; kept for the values saved with them.', used and COL.own or nil) then
        for _, r in ipairs(PIC_MORE) do picSlider(m, r, idp) end
        imgui.tree_pop()
    end
end
local function pctOwnSlider(p, m, id)
    local own = V.ownVal('feel', m, p[1])
    local b = V.builtinVal('feel', m, p[1])
    local reset = own and { fn = function() V.clearOwnVal('feel', m, p[1]) end, def = tostring(round(b or V.sharedPct(p[1]))) }
    local dis = not m and disabledBegin()
    local c, v = slider(ownMark(own)..tr(p[2])..'###'..id, V.pctFor(m, p[1]), 0, 200, '%.0f %%', reset, own and COL.own)
    disabledEnd(dis)
    ownTip(p[3], m, own, tostring(round(V.sharedPct(p[1]))), '100', b and tostring(round(b)))
    if c and m then V.setOwnVal('feel', m, p[1], round(v)) end
    return own ~= nil
end
-- Fine tuning by topic, so everything about one thing (e.g. landings) is in one place, roughly in
-- the order it happens. A value not listed here still shows up, under "Other".
local TUNE_LAYOUT = {
    { 'engine', 'Engine', { 'idle', 'idleRev', 'cruise' } },
    { 'road', 'Road and corners', { 'road', 'bumps', 'corner', 'accel', 'drift', 'draft' } },
    { 'lunge', 'Boost lunge and nose lift',
      { 'ramjet', 'afterburner', 'abRumble', 'launch', 'ebrake', 'lungeMax', 'fwdScale', 'nod', 'lowHum', 'heatShake' } },
    { 'boostfx', 'Boost screen, hit-stop, warp',
      { 'flashRJ', 'flashAB', 'satRJ', 'satAB', 'vigRJ', 'vigAB', 'fadeOut', 'hitstopStrength', 'hitstopAB', 'hitstopTime', 'warpAmount' } },
    { 'landing', 'Landings and hits',
      { 'airLift', 'landing', 'landFloor', 'landLean', 'landHit', 'landHitHz', 'headHitPitch', 'headHitRoll', 'headHitHz', 'nearLow', 'impact' } },
    { 'view', 'View (banking)', { 'rollAmount', 'rollMax' } },
    { 'spring', 'All shaking: head spring', { 'springHz', 'damping', 'alongTilt' } },
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
        colorText(string.format(tr('Vehicle: %s (%s)'), V.modelLabel(V.model), typeName(V.vtype))
            ..string.format(tr('   Character: %s'), V.pilotLabel(V.pilot)), COL.own)
        tip('The vehicle you are driving now: its type and the model of the part your seat is in (landspeeder and skim speeder: the rear, speeder bike: the controls, podracer: the pod). Values are saved by that part: swap it in Edit Vehicle and the vehicle has its own values; swap any other part and they stay.')
        help(string.format(tr('-> What you change now (eye position, banking, body follow, cut distance, shake, fine tuning) is saved for %s only. What you don\'t touch keeps its default.'), V.modelLabel(V.model)))
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
                colorText(string.format(tr('Eye position (%s): %s'), V.modelLabel(V.model),
                    ownEye and tr('saved for this vehicle') or tr('default position')), COL.own)
                tip('Saved automatically for the vehicle you drive as soon as you move a slider.')
            end
            local x, y, z = e[1], e[2], e[3]
            local de = V.defaultEyeFor(V.model)
            local function eyeReset(i)
                if locked or not ownEye or math.abs((tonumber(e[i]) or 0) - de[i]) < 0.05 then return nil end
                return { fn = function()
                    local ne = { x, y, z }
                    ne[i] = de[i]
                    if math.abs(ne[1] - de[1]) + math.abs(ne[2] - de[2]) + math.abs(ne[3] - de[3]) < 0.05 then V.resetEye()
                    else V.setEye(ne[1], ne[2], ne[3]) end
                end, def = string.format('%.1f', de[i]) }
            end
            local dis = locked and disabledBegin()
            local c1, v1 = slider(tr('Sideways (cm)')..'##eyeX', x, -160, 160, '%.1f', eyeReset(1))
            tip('Moves your eyes left / right in the seat. Saved for this vehicle.')
            local c2, v2 = slider(tr('Forward / back (cm)')..'##eyeY', y, -200, 200, '%.1f', eyeReset(2))
            tip('Moves your eyes forward / back. Use it if the dashboard is too close or too far.')
            local c3, v3 = slider(tr('Up / down (cm)')..'##eyeZ', z, -100, 250, '%.1f', eyeReset(3))
            tip('Moves your eyes up / down. Use it if you feel you sit too low or too high.')
            disabledEnd(dis)
            if not locked and (c1 or c2 or c3) then V.setEye(c1 and v1 or x, c2 and v2 or y, c3 and v3 or z) end
            if ownEye and button(tr('Default eye for this vehicle'), 'eyeReset',
                'Forgets the eye position saved for this vehicle.') then V.resetEye() end
        end
        local l = combo(tr('Follow the vehicle'), LOCKS, S.cameraLock, 'lock',
            'How much the view tilts with the vehicle when it pitches over hills and leans in turns. Higher in the list = more comfortable, lower = more alive. If you get motion sick, pick "Level horizon". "Exactly like the vehicle" leans as the game designed it, like the original cockpit script: it sets Banking to 200, maximum 90, amount 0.55.', S.cameraLock == 'pilot' and COL.danger or nil)

        if l then S.cameraLock = l; V.cfg.cameraLock = l; V.syncBankingMode(l); ch = true end
        if S.cameraLock == 'pilot' then
            help('"Exactly like the vehicle": the view leans as the game designed it (like the original cockpit script) - Banking 200, maximum 90, amount 0.55. Want more lean? Raise the amount in Fine tuning > View (banking). What you set while driving a vehicle is saved for it ([vehicle]) and stays when you switch modes.', COL.danger)
        end
        pctOwnSlider(BANK, V.model, 'v_roll')
        local rn = S.rollNow
        if rn and S.enabled then
            imgui.text(string.format(tr('  Now: the vehicle leans %.0f deg, your view %.0f deg'), rn[1], rn[2]))
            tip('Live, while you drive. With the add-on effects off and "Exactly like the vehicle" both are the same (as in the original cockpit script). Banking, the follow mode and the shake change the second one.')
        end
        local p = combo(tr('Pilot'), PILOT, S.pilotVisibility == 'visible' and V.cfg.pilot or S.pilotVisibility, 'pilot',
            'How much of your pilot you see in the cockpit. The head is in the same place as your eyes, so it is usually hidden.')
        if p then S.setPilotMode(p) end
        local c, v
        c, v = checkbox(tr('Follow the pilot on jumps'), V.cfg.bodyFollow, 'follow',
            'On jumps (mostly bikes) the rider stands up in the air. Your eyes stay at the seat, so you would end up inside the rider\'s body. On: your eyes move with the body while airborne.')
        if c then V.cfg.bodyFollow = v; ch = true end
        if V.cfg.bodyFollow then
            if V.model then
                colorText(string.format(tr('  Saved automatically for %s + %s'), V.modelLabel(V.model), V.pilotLabel(V.pilot)), COL.own)
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
        if section(tr('Game scenes and cameras'), 'gamecams',
            'When the game shows its own scenes and cameras (race intro, crash, takedown, finish line, look back) the cockpit can step aside; and looking back from the cockpit seat.') then
            c, v = checkbox(tr('Show the race intro flyover'), S.showCinematics, 'cine',
                'Before a race the game flies the camera over the track, and after the race it shows its scenes. On: you watch them with the game camera, then the cockpit takes over. Off: cockpit from the start.')
            if c then S.showCinematics = v; V.cfg.showCinematics = v; ch = true end
            c, v = checkbox(tr('Outside view when crashing'), S.showCrashCamera, 'crash',
                'On: when you crash or tumble, the game\'s crash camera shows the wreck from outside. Off: you stay in the cockpit (can be wild).')
            if c then S.showCrashCamera = v; V.cfg.showCrashCamera = v; ch = true end
            c, v = checkbox(tr('Show takedowns'), S.showTakedownCamera, 'takedown',
                'On: when you take a rival down, the game shows it with its own camera for about 2 seconds, then you are back in the cockpit. Off: you stay in the cockpit.')
            if c then S.showTakedownCamera = v; V.cfg.showTakedownCamera = v; ch = true end
            c, v = checkbox(tr('Show the finish line camera'), S.showFinishCamera, 'finishcam',
                'On: when you cross the finish line, the game shows your vehicle from outside for about 5 seconds before the results. Off: you stay in the cockpit until the results.')
            if c then S.showFinishCamera = v; V.cfg.showFinishCamera = v; ch = true end
            c, v = checkbox(tr('Look back'), S.showLookBack, 'lookback',
                'Lets you look back in the cockpit view, which you couldn\'t before: the game\'s own look back shows its rear camera, and the cockpit look back hotkey (right stick up unless changed) turns you round in the cockpit seat while you hold it. Change that button in Hotkeys. Off: neither.')
            if c then S.showLookBack = v; V.cfg.showLookBack = v; ch = true end
            imgui.tree_pop()
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
        -- overall strength per vehicle type: the default amounts and the ones saved for a vehicle, apart
        -- (the type shown follows the vehicle you get into; another one can be picked)
        if V.vtype and V.vtype ~= masterSeen then masterSeen, masterType = V.vtype, V.vtype end
        local mt = combo(tr('Master: vehicle type'), MASTER_TYPES, masterType, 'masterType',
            'Which vehicle type the two master amounts below are for. Each type has its own. It starts at the type you are driving.')
        if mt then masterType = mt end
        local kd, ks = 'shakeDefault_'..masterType, 'shakeSaved_'..masterType
        local cd, vd = slider(tr('Master: default amounts')..'##shakeDefault', tonumber(V.cfg[kd]) or 100, 0, 300, '%.0f %%',
            resetTo(V.cfg, kd, 100, '%.0f'))
        tip('On every vehicle of this type, multiplies all the shake amounts you did not set for that vehicle (its default or the shared amount). The ones you set for a vehicle stay. 100 = as they are, 50 = half, 200 = double, 0 = off.')
        if cd then V.cfg[kd] = round(vd); ch = true end
        local cs, vs = slider(tr('Master: saved amounts')..'##shakeSaved', tonumber(V.cfg[ks]) or 100, 0, 300, '%.0f %%',
            resetTo(V.cfg, ks, 100, '%.0f'))
        tip('On every vehicle of this type, multiplies all the shake amounts you set for that vehicle (marked [vehicle]). 100 = as set, 50 = half, 200 = double, 0 = off.')
        if cs then V.cfg[ks] = round(vs); ch = true end
        c, v = checkbox(tr('Landing hits your head'), V.cfg.headHit, 'headHit',
            'The usual landing moves your view down, which feels like the vehicle jolts while your head stays still. This also snaps the view angle down and back with a little sideways wobble at touchdown, so it feels like your head takes the hit. Fine tuning > Landings and hits has its values.')
        if c then V.cfg.headHit = v; ch = true end
        -- the ride shake (test): everything about it in red
        local ca, va = checkbox(tr('Ride shake'), V.cfg.shakeAlongOn, 'shakeAlongOn',
            'Moves part of the shake from the cockpit to the world: that part moves you with the vehicle and shakes the world. The amounts below are saved per vehicle.', COL.danger)
        if ca then V.cfg.shakeAlongOn = va; ch = true end
        help('This option is for extreme users: for those who don\'t get motion sick, or who want even more sense of speed from the game. It works best with the follow modes 3 to 5.', COL.danger)
        if V.cfg.shakeAlongOn then
            -- (saved for the vehicle you drive, like the fine tuning; the defaults come later per type)
            for _, sa in ipairs(ALONG_SLIDERS) do tuneSlider(V.TUNE_INDEX[sa[1]], vm, 'sa_'..sa[1], tr(sa[2]), '%.0f %%', COL.danger, true) end
            -- its masters: a vehicle type of their own (the cockpit shake's doesn't count here)
            if V.vtype and V.vtype ~= rideSeen then rideSeen, rideType = V.vtype, V.vtype end
            local rt = combo(tr('Master: vehicle type'), MASTER_TYPES, rideType, 'rideType',
                'Which vehicle type the two ride shake master amounts below are for. Each type has its own, apart from the cockpit shake masters. It starts at the type you are driving.', COL.danger)
            if rt then rideType = rt end
            local rd, rs = 'rideDefault_'..rideType, 'rideSaved_'..rideType
            local crd, vrd = slider(tr('Master: default amounts')..'##rideDefault', tonumber(V.cfg[rd]) or 100, 0, 300, '%.0f %%',
                resetTo(V.cfg, rd, 100, '%.0f'), COL.danger)
            tip('On every vehicle of this type, multiplies the ride shake amounts (trembling and sways world share, landing slam) you did not set for that vehicle. The ones you set stay. 100 = as they are, 50 = half, 200 = double, 0 = off.')
            if crd then V.cfg[rd] = round(vrd); ch = true end
            local crs, vrs = slider(tr('Master: saved amounts')..'##rideSaved', tonumber(V.cfg[rs]) or 100, 0, 300, '%.0f %%',
                resetTo(V.cfg, rs, 100, '%.0f'), COL.danger)
            tip('On every vehicle of this type, multiplies the ride shake amounts (trembling and sways world share, landing slam) you set for that vehicle. 100 = as set, 50 = half, 200 = double, 0 = off.')
            if crs then V.cfg[rs] = round(vrs); ch = true end
        end
        local info = V.shakeAlongInfo
        if V.cfg.shakeAlongOn and info and info.failed then help(tr('Not possible with this vehicle: ')..tostring(info.failed), COL.warn) end
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

    -- the picture everywhere ------------------------------------------------------------------------
    local baseUsed = next(V.cfg.picBase or {}) ~= nil
    if section(tr('VR picture for every track'), 'picBase',
        'Picture values for every track and weather at once, against the headset\'s paler, brighter look. A track\'s own values (Brightness per track and weather) replace these there.', baseUsed and COL.own or COL.test) then
        help('Every track and weather starts from these. Where you set a track\'s own value (light blue there), that one is used instead.')
        picRows('*', 'pb')
        if baseUsed and button(tr('Every track: back to the game\'s picture'), 'picBaseReset',
            'Forgets these values: every track looks as the game shows it again (a track\'s own values stay).') then V.clearPicBase() end
        imgui.tree_pop()
    end

    -- picture per track and weather --------------------------------------------------------------
    if section(tr('Brightness per track and weather'), 'picture',
        'For tracks that look too bright (or too dark) in VR. What you change here is saved for the track you are racing, in the weather it has now, only; every other track and weather stays as the game shows it.', COL.test) then
        local place = V.picPlace()
        colorText(string.format(tr('Now: %s'), place and V.mapLabel(place) or tr('reading the race...')), COL.own)
        if V.picWholeMap(place) then tip(tr('The track or its weather could not be read here: saved for the whole map.')) end
        help(V.PIC_LAB and 'Saved for this track in this weather only (another weather, or the track reversed, has its own). The outside turns white inside tunnels: Tunnels. Sky or sand too glaring out in the open: Tone down glaring places. Too dark (night): Lift dark places, or Brightness.'
            or 'Saved for this track in this weather only (another weather, or the track reversed, has its own).')
        local dis = not place and disabledBegin()
        picRows(place, 'pic')
        if V.PIC_LAB and button(tr('Starting point against glare'), 'picRec',
            'Puts in for this track and weather: tunnels 100, bloom 70. Adjust from there.') and place then
            V.setPicVal(place, 'picTunnel', 100); V.setPicVal(place, 'picBloom', 70)
        end
        disabledEnd(dis)
        if place and V.veh.maps[place] then
            V.picCompareSeen = V.t
            local cc, cv = checkbox(tr('Compare: show the game\'s picture'), V.picCompare == true, 'picCompare',
                'While ticked, your values here are left out, to see the difference. Not saved; it switches off when the menu closes.')
            if cc then V.picCompare = cv end
        end
        if place and V.veh.maps[place] and button(tr('This track and weather: back to the game\'s picture'), 'picReset',
            'Forgets the picture values saved for this track in this weather: it looks as the game shows it again.') then V.clearPicMap(place) end
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
            help(string.format(tr('Driving %s: a value you change is saved for this vehicle only ("[vehicle]"); the others keep their defaults.'), V.modelLabel(V.model)))
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
        local AX = { { 'Sideways (cm)', -160, 160 }, { 'Forward / back (cm)', -200, 200 }, { 'Up / down (cm)', -100, 250 } }
        for _, name in ipairs(names) do
            if section(typeName(V.typeOf(name))..' / '..V.modelLabel(name)..(name == V.model and tr('  (driving now)') or ''), 'veh'..name) then
                local e, ownEye = V.eyeFor(name)
                imgui.text(ownEye and tr('Eye position (saved for this vehicle):') or tr('Eye position (default):'))
                local de = V.defaultEyeFor(name)
                for i, a in ipairs(AX) do
                    local reset = nil
                    if ownEye and math.abs((tonumber(e[i]) or 0) - de[i]) >= 0.05 then
                        reset = { def = string.format('%.1f', de[i]), fn = function()
                            local ne = { tonumber(e[1]) or 0, tonumber(e[2]) or 0, tonumber(e[3]) or 0 }
                            ne[i] = de[i]
                            if math.abs(ne[1] - de[1]) + math.abs(ne[2] - de[2]) + math.abs(ne[3] - de[3]) < 0.05 then V.resetEye(name)
                            else
                                V.veh.eyes[name] = ne; V.saveVeh()
                                if name == V.model then S.setEye(ne[1], ne[2], ne[3]) end
                            end
                        end }
                    end
                    local c, v = slider(tr(a[1])..'##ve'..name..i, tonumber(e[i]) or 0, a[2], a[3], '%.1f', reset)
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
                -- (the shaking-along amounts of this vehicle; untouched = the shared ones)
                colorText(tr('Ride shake:'), COL.danger)
                for _, sa in ipairs(ALONG_SLIDERS) do tuneSlider(V.TUNE_INDEX[sa[1]], name, 'vsa'..name..sa[1], tr(sa[2]), '%.0f %%', COL.danger, true) end
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

    -- saved tracks (picture per track and weather) -----------------------------------------------
    local maps = {}
    for m in pairs(V.veh.maps) do maps[#maps + 1] = m end
    table.sort(maps)
    if section(string.format(tr('Saved tracks (%d)'), #maps), 'maps',
        'Every track and weather with its own picture values (Brightness per track and weather). Open one to see and change them, or forget them.') then
        local here = V.picPlace()
        for _, m in ipairs(maps) do
            local label = V.mapLabel(m)..(V.picWholeMap(m) and tr('  (whole map, older version)') or '')
            if section(label..(m == here and tr('  (here now)') or ''), 'map'..m) then
                picRows(m, 'pm'..m)
                if button(tr('Forget these values'), 'mapdel'..m,
                    'Forgets the picture values saved here: it looks as the game shows it again.') then V.clearPicMap(m) end
                imgui.tree_pop()
            end
        end
        if #maps == 0 then imgui.text(tr('  (none yet - change something in Brightness per track and weather)')) end
        imgui.tree_pop()
    end

    -- hotkeys ------------------------------------------------------------------------------------
    if section(tr('Hotkeys'), 'hotkeys',
        'Keys / controller buttons for switching cameras, recentering and switching the add-on effects. Each action can have a keyboard key and a controller combo.') then
        local padNames, holdNames = {}, {}
        for i, pd in ipairs(V.HOTKEY_PADS) do padNames[i] = { pd[1], pd[1], pd[1] } end
        for i, pd in ipairs(V.HOTKEY_PADS_HOLD) do holdNames[i] = { pd[1], pd[1], pd[1] } end
        help('Keyboard: click the button, then press the key you want (Esc = cancel). Controller: pick a combo from the list.')
        V.keyCaptureSeen = V.t                 -- the menu is open: a key capture may go on
        -- (each action: a line, its name in colour, its keyboard key and controller button indented under it)
        for i, a in ipairs(V.HOTKEY_ACTIONS) do
            if i > 1 then pcall(imgui.spacing) end
            pcall(imgui.separator)
            colorText(tr(a.en), COL.head)
            local indented = pcall(imgui.indent)
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
            local pd = combo(tr('  Controller'), a.hold and holdNames or padNames, V.cfg['pad'..a.id], 'p'..a.id,
                a.hold and 'Look back from the cockpit seat while you hold it (with "Look back" on in View > Game scenes and cameras). A right stick direction or a single button works here. The game may also react to the button you pick.'
                    or 'Hold the Back (View) button and press the second button. The game may also react to that button, so pick one you don\'t use while racing.')
            if pd then V.cfg['pad'..a.id] = pd; ch = true end
            if indented then pcall(imgui.unindent) end
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
            S.showTakedownCamera, S.showFinishCamera = V.cfg.showTakedownCamera, V.cfg.showFinishCamera
            S.showLookBack = V.cfg.showLookBack ~= false
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
        if labelColNow > 0 then labelCol, labelColNow = labelColNow, 0 end     -- (the last frame's widest label)
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
