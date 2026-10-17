-- Hotkeys: keyboard keys and controller combos (Back held + a second button) for
-- cockpit <-> game cameras, next game camera, recenter, add-on effects on / off.
-- Keyboard keys are set like UEVR's own key binding: click the button in the menu, press a key.
local log = V.logger('hotkeys')
local S = V.cam
-- keys that can be bound (ImGui key names without "Key_"). Not Insert (the UEVR menu key) and not
-- Escape (cancels).
local CAPTURE_KEYS = {}
do
    for i = 1, 12 do CAPTURE_KEYS[#CAPTURE_KEYS + 1] = 'F'..i end
    for c in ('ABCDEFGHIJKLMNOPQRSTUVWXYZ'):gmatch('.') do CAPTURE_KEYS[#CAPTURE_KEYS + 1] = c end
    for i = 0, 9 do CAPTURE_KEYS[#CAPTURE_KEYS + 1] = tostring(i) end
    for i = 0, 9 do CAPTURE_KEYS[#CAPTURE_KEYS + 1] = 'Keypad'..i end
    for _, k in ipairs({ 'Home', 'End', 'PageUp', 'PageDown', 'Delete', 'Backspace', 'Tab', 'Space', 'Enter',
        'LeftArrow', 'RightArrow', 'UpArrow', 'DownArrow', 'KeypadDecimal', 'KeypadDivide', 'KeypadMultiply',
        'KeypadSubtract', 'KeypadAdd', 'KeypadEnter', 'Minus', 'Equal', 'LeftBracket', 'RightBracket',
        'Backslash', 'Semicolon', 'Apostrophe', 'Comma', 'Period', 'Slash', 'GraveAccent', 'CapsLock',
        'ScrollLock', 'NumLock', 'PrintScreen', 'Pause', 'LeftCtrl', 'RightCtrl', 'LeftShift', 'RightShift',
        'LeftAlt', 'RightAlt' }) do
        CAPTURE_KEYS[#CAPTURE_KEYS + 1] = k
    end
end
local BACK, RB, RTHUMB = 0x0020, 0x0200, 0x0080
V.HOTKEY_PADS = {
    { 'None', 0 },
    { 'Back + A', 0x1000 }, { 'Back + B', 0x2000 }, { 'Back + X', 0x4000 }, { 'Back + Y', 0x8000 },
    { 'Back + D-pad Up', 0x0001 }, { 'Back + D-pad Down', 0x0002 },
    { 'Back + D-pad Left', 0x0004 }, { 'Back + D-pad Right', 0x0008 },
    { 'Back + RB', 0x0200 },
}
-- the held look back may also use a single button or a right stick direction
local STICK = 0.5 * 32767                  -- a stick pushed past half way
V.HOTKEY_PADS_HOLD = {
    { 'None', 0 },
    { 'Right stick up', 'RSU' }, { 'Right stick down', 'RSD' }, { 'Right stick left', 'RSL' }, { 'Right stick right', 'RSR' },
    { 'Y', 0x8000, true }, { 'X', 0x4000, true }, { 'B', 0x2000, true }, { 'A', 0x1000, true },
    { 'LB', 0x0100, true }, { 'RB', 0x0200, true },
    { 'Left stick click', 0x0040, true }, { 'Right stick click', 0x0080, true },
    { 'D-pad Up', 0x0001, true }, { 'D-pad Down', 0x0002, true }, { 'D-pad Left', 0x0004, true }, { 'D-pad Right', 0x0008, true },
}
for i = 2, #V.HOTKEY_PADS do V.HOTKEY_PADS_HOLD[#V.HOTKEY_PADS_HOLD + 1] = V.HOTKEY_PADS[i] end
V.HOTKEY_ACTIONS = {
    { id = 'Toggle', en = 'Cockpit <-> game cameras' },
    { id = 'Cycle', en = 'Next game camera' },
    { id = 'Recenter', en = 'Recenter head at the seat' },
    { id = 'Extras', en = 'Add-on effects on / off (compare with the original)' },
    { id = 'LookBack', en = 'Look back from the cockpit seat (while held)', hold = true, pads = V.HOTKEY_PADS_HOLD },
}
local function padMask(name, list)
    for _, p in ipairs(list or V.HOTKEY_PADS) do if p[1] == name then return p[2], p[3] == true end end
    return 0, false
end
-- bit test without Lua 5.3 operators: is bit m (a power of two) set in b?
local function hasBit(b, m) return m > 0 and math.floor(b / m) % 2 == 1 end

local buttons, rx, ry = 0, 0, 0
callbacks.on_xinput_get_state(function(retval, user_index, state)
    if user_index == 0 and state then
        pcall(function() rx, ry = tonumber(state.Gamepad.sThumbRX) or 0, tonumber(state.Gamepad.sThumbRY) or 0 end)
        local ok, b = pcall(function() return state.Gamepad.wButtons end)
        if ok and tonumber(b) then
            buttons = tonumber(b)
            -- in the cockpit while racing the game doesn't get its camera change button (RB, with the
            -- alternative controls the right stick click): the cockpit view stays anyway, but the game
            -- moved its HUD a little for each camera (2026-10-17; always, no menu switch). Our own
            -- buttons are read above, so a hotkey on that button still works.
            local cam = S.controlScheme == 1 and RTHUMB or RB
            if S.enabled and S.racing and hasBit(buttons, cam) then
                pcall(function() state.Gamepad.wButtons = buttons - cam end)
            end
        end
    end
end)
local function keyDown(name)
    if not name or name == 'None' then return false end
    local ok, down = pcall(function() return imgui.is_key_down(imgui.ImGuiKey['Key_'..name]) end)
    return ok and down or false
end
local function padDown(name, list)
    local m, single = padMask(name, list)
    if m == 'RSU' then return ry > STICK end
    if m == 'RSD' then return ry < -STICK end
    if m == 'RSL' then return rx < -STICK end
    if m == 'RSR' then return rx > STICK end
    if type(m) ~= 'number' or m == 0 then return false end
    if single then return hasBit(buttons, m) and not hasBit(buttons, BACK) end   -- (Back + it is a combo)
    return hasBit(buttons, BACK) and hasBit(buttons, m)
end
-- key capture: V.keyCapture = the action waiting for a key. Only keys pressed after the click count;
-- cancelled with Escape, a second click, or when the menu is closed (so driving keys can't end up
-- bound by accident). The key is taken away from any other action that had it.
V.keyCapture, V.keyCaptureSeen = nil, 0
local capWasDown = {}
function V.keyCaptureStart(id)
    V.keyCapture, V.keyCaptureSeen = id, V.t
    for _, k in ipairs(CAPTURE_KEYS) do capWasDown[k] = keyDown(k) end
    capWasDown.Escape = keyDown('Escape')
end
local function captureStep()
    if V.t - V.keyCaptureSeen > 0.5 then V.keyCapture = nil; return end      -- menu closed
    local esc = keyDown('Escape')
    if esc and not capWasDown.Escape then V.keyCapture = nil; return end
    capWasDown.Escape = esc
    for _, k in ipairs(CAPTURE_KEYS) do
        local d = keyDown(k)
        if d and not capWasDown[k] then
            for _, a in ipairs(V.HOTKEY_ACTIONS) do
                if a.id ~= V.keyCapture and V.cfg['key'..a.id] == k then V.cfg['key'..a.id] = 'None' end
            end
            V.cfg['key'..V.keyCapture] = k
            V.save()
            log('key for '..V.keyCapture..': '..k)
            V.keyCapture = nil
            return
        end
        capWasDown[k] = d
    end
end
local held = {}
local function run(id)
    if id == 'Toggle' then S.setCameraMode(S.enabled and 'game' or 'cockpit')
    elseif id == 'Cycle' then S.cycleGameCamera()
    elseif id == 'Recenter' then S.recenter()
    elseif id == 'Extras' then V.cfg.extras = not V.cfg.extras; V.save() end
    log('hotkey '..id)
end
callbacks.on_frame(function()
    local ok, err = pcall(function()
        local capturing = V.keyCapture ~= nil        -- no actions while a key is being set
        if capturing then captureStep() end
        for _, a in ipairs(V.HOTKEY_ACTIONS) do
            local down = keyDown(V.cfg['key'..a.id]) or padDown(V.cfg['pad'..a.id], a.pads)
            if a.id == 'LookBack' then S.lookBackKey = down and not capturing      -- (held: the cockpit reads it)
            elseif down and not held[a.id] and not capturing then run(a.id) end
            held[a.id] = down
        end
    end)
    if not ok and V.t > (V.hotkeyErrT or 0) then V.hotkeyErrT = V.t + 5; log('error: '..tostring(err)) end
end)
-- short text for the menu
function V.hotkeyText(id)
    local k, p = V.cfg['key'..id], V.cfg['pad'..id]
    local parts = {}
    if k and k ~= 'None' then parts[#parts + 1] = k end
    if p and p ~= 'None' then parts[#parts + 1] = p end
    if #parts == 0 then return V.tr('none') end
    return table.concat(parts, ' / ')
end
