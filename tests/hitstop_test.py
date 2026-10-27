"""The hit-stop (Boost effects, since 2026-10-27): only what you see stops short and catches up; the game
keeps its full speed (no global time dilation), so online races and time trials lose nothing. Its own
settings are fixed (V.fhOpt; most cases here change them - "the release settings" runs them as they ship);
the player's are on / off, two strengths, a length: a value chosen stays, one equal to an older default
saved by an older version takes the new default. The sound is never changed.

usage: python tests/hitstop_test.py <script.lua> [<script.lua>]"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import picture_weather_test as P  # noqa: E402  (the Lua state, the mock, check(), note(), frames())

HITSTOP = r"""
local S = SWGR_VR_CAM
local MPH = 44.704
V.cfg.extras, V.cfg.feelOn, V.cfg.hitstop = true, true, true
-- 0. the new defaults: every vehicle the same - ramjet / start 0.7, afterburner 0.5, 0.1 s (cars had their own)
local defs = {}
for _, m in ipairs({ 'Car/Mako', 'Car/Beluga', 'Plane/Myth', 'Bike/Taipan', 'Skimmer/Saker' }) do
    defs[#defs + 1] = string.format('%s %.2f/%.2f/%.2f', m, V.valFor(m, 'hitstopStrength'), V.valFor(m, 'hitstopAB'), V.valFor(m, 'hitstopTime'))
end
note('defaults: '..table.concat(defs, ', '))
check('the new defaults, every vehicle', table.concat(defs, ', '), 'Car/Mako 0.70/0.50/0.10, Car/Beluga 0.70/0.50/0.10, Plane/Myth 0.70/0.50/0.10, Bike/Taipan 0.70/0.50/0.10, Skimmer/Saker 0.70/0.50/0.10')
V.fhOpt.check, V.fhOpt.log = true, true        -- (the check lines and the per-event lines, as when working on it)
-- (the numbers below were made with the old landspeeder values: set for every vehicle here)
V.cfg.detail.hitstopStrength, V.cfg.detail.hitstopAB, V.cfg.detail.hitstopTime = 0.53, 0.33, 0.16
V.fhOpt.maxLag = 600                       -- (the numbers below were made with 600)
V.fhOpt.catchMax = 100                     -- (and the short catch-up of 0.35 s; the gentle one has its own case)
V.fhOpt.sling = false                      -- (and first back to normal speed like the old one; right after the stall has its own case)
-- another vehicle near you (made first: the mock moves the newest one, yours)
local other, ov = MOCK.makeVehicle('Bike', 'Taipan')
local otherBody, otherFx = MOCK.bodyRoot, MOCK.fx
ov.Velocity = { X = 150 * MPH, Y = 0, Z = 0 }
local me, v = MOCK.makeVehicle('Car', 'Mako')
local myBody, myFx = MOCK.bodyRoot, MOCK.fx
MOCK.objectsOf = MOCK.objectsOf or {}
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { me, other }
MOCK.pawn = me
local function drive(mph) v.SpeedMPH, v.Throttle, v.IgnitionStatus = mph, 1, 3; v.Velocity = { X = mph * MPH, Y = 0, Z = 0 } end
drive(200); frames(2)
note('cockpit '..tostring(S.enabled)..', anchor '..tostring(S.anchor ~= nil)..', vehicle '..tostring(V.model))
local function logged(from, text)
    local n = 0
    for i = from + 1, #(MOCK.logs or {}) do if MOCK.logs[i]:find(text, 1, true) then n = n + 1 end end
    return n
end
-- (the other vehicle right beside you)
local function beside()
    local t = v.VehicleTransform.Translation
    ov.VehicleTransform.Translation = { X = t.X + 300, Y = t.Y + 400, Z = t.Z }
end
-- a ramjet with the hit-stop on: watched frame by frame for 1.5 s
local function ramjet(each)
    v.RamjetState = 0; frames(0.5)
    beside()
    local w = { lagMe = 0, lagOther = 0, fxMe = 1, fxOther = 1, step = 0, dil0 = MOCK.dilationCalls or 0 }
    local prev = -myBody.RelativeLocation.X
    v.RamjetState = 3
    for i = 1, 108 do
        if each then each(i) end
        MOCK.frame(1 / 72)
        local now = -myBody.RelativeLocation.X
        w.step, prev = math.max(w.step, math.abs(now - prev)), now
        w.lagMe = math.max(w.lagMe, now)
        w.lagOther = math.max(w.lagOther, -otherBody.RelativeLocation.X)
        w.fxMe, w.fxOther = math.min(w.fxMe, myFx.dil), math.min(w.fxOther, otherFx.dil)
    end
    w.dil = (MOCK.dilationCalls or 0) - w.dil0
    w.after = string.format('%.1f/%.1f/%.2f/%.2f', myBody.RelativeLocation.X, otherBody.RelativeLocation.X, myFx.dil, otherFx.dil)
    return w
end
-- 1. the hit-stop
local w = ramjet()
note(string.format('hit-stop: you drawn up to %.0f cm behind, the other %.0f cm; effects down to %.2f / %.2f; game slow-downs %d; after: %s',
    w.lagMe, w.lagOther, w.fxMe, w.fxOther, w.dil, w.after))
check('hit-stop: the game itself never slowed (no time dilation)', w.dil, 0)
-- (a landspeeder: strength 0.53 for 0.16 s, then 0.12 s back: 0.087 s behind at 200 mph = 782 cm, eased
-- off toward 600: about 581)
check('  you drawn behind, eased off below the farthest (600 cm)', w.lagMe > 540 and w.lagMe <= 600, true)
check('  the other vehicle drawn behind (its own speed)', w.lagOther > 300, true)
check('  effects slowed (yours and the other one)', w.fxMe < 0.7 and w.fxOther < 0.7, true)
check('  the sound never changed', MOCK.pitchCalls == nil, true)
check('  all back after it', w.after, '0.0/0.0/1.00/1.00')
local info = V.hitstopInfo()
check('  the menu knows what it did', tostring(info.used)..'/'..tostring(info.ownCm ~= nil)..'/'..tostring(info.moved)..'/'..tostring((tonumber(info.fxN) or 0) > 0), 'true/true/1/true')
-- (the farthest raised: as far as the time behind says)
V.fhOpt.maxLag = 1000
w = ramjet()
note(string.format('farthest 1000 cm: you %.0f cm behind (0.087 s x 200 mph = 782)', w.lagMe))
check('  farthest 1000: about 780 cm', math.abs(w.lagMe - 780) < 25, true)
V.fhOpt.maxLag = 600
-- 2. the hit-stop off (Boost effects): nothing at all - nothing drawn behind or slowed, the game never slowed
V.cfg.hitstop = false
w = ramjet()
note(string.format('off: you drawn behind %.0f cm, effects %.2f, time dilation set %d times', w.lagMe, w.fxMe, w.dil))
check('off: nothing drawn behind or slowed, the game never slowed', w.dil == 0 and w.lagMe < 0.5 and w.fxMe == 1, true)
-- 3. switched off in the middle: all back at once
V.cfg.hitstop = true
v.RamjetState = 0; frames(0.5); v.RamjetState = 3
for i = 1, 8 do MOCK.frame(1 / 72) end
local mid = -myBody.RelativeLocation.X
V.cfg.hitstop = false
MOCK.frame(1 / 72); MOCK.frame(1 / 72)
check('switched off in the middle: back at once ('..string.format('%.0f', mid)..' cm before)', mid > 50 and string.format('%.1f/%.1f/%.2f',
    myBody.RelativeLocation.X, otherBody.RelativeLocation.X, myFx.dil) == '0.0/0.0/1.00', true)
V.cfg.hitstop = true
-- 4. each part on its own
V.fhOpt.others, V.fhOpt.fx = false, false
w = ramjet()
check('only your view: the other one and the effects left alone', w.lagMe > 500 and w.lagOther < 0.5 and w.fxOther == 1, true)
V.fhOpt.others, V.fhOpt.fx, V.fhOpt.view = true, true, false
w = ramjet()
check('without your view: you not drawn behind, the other one is', w.lagMe < 0.5 and w.lagOther > 300, true)
V.fhOpt.view = true
-- 4b. the check: how fast your seat looked on screen, against what the old hit-stop did (in each line)
MOCK.seatFollows = true
local function checkLine(from, kind)
    for i = from + 1, #(MOCK.logs or {}) do
        local l = MOCK.logs[i]
        if l:find('hit-stop check ('..kind..')', 1, true) then return l end
    end
end
local function num(l, pat) return tonumber(l and l:match(pat)) or -1 end
local c0
V.fhOpt.maxLag = 1000
c0 = #MOCK.logs
w = ramjet()
local lf = checkLine(c0, 'picture')
note('farthest 1000: '..tostring(lf))
check('check, not eased off: the same as slowing the game through the hold and the ramp, all given back',
    lf ~= nil and math.abs(num(lf, 'hold looked ([%d.]+)') - num(lf, 'hold looked [%d.]+ %(slowing the game: ([%d.]+)%)')) < 0.03
    and math.abs(num(lf, 'ramp ([%d.]+)') - num(lf, 'ramp [%d.]+ %(([%d.]+)%)')) < 0.03
    and math.abs(num(lf, '([%d.]+) s behind') - num(lf, 's behind %(slowing the game: ([%d.]+)%)')) < 0.01
    and math.abs(num(lf, '([%d.]+) s given back') - num(lf, '([%d.]+) s behind')) < 0.01 and not lf:find('eased off', 1, true), true)
V.fhOpt.maxLag = 600
c0 = #MOCK.logs
w = ramjet()
lf = checkLine(c0, 'picture')
note('farthest 600: '..tostring(lf))
check('check, eased off at the farthest: said, less behind than slowing the game', lf ~= nil and lf:find('eased off', 1, true) ~= nil
    and num(lf, '([%d.]+) s behind') < num(lf, 's behind %(slowing the game: ([%d.]+)%)'), true)
-- (the time lines: not eased off, its shake not held, it looks like slowing the game for its first
-- 0.2 s, seat and cockpit; then it catches up, faster, where slowing the game is back to 1)
local function part(l, pat) return l and l:match(pat) end
V.fhOpt.freeze, V.fhOpt.maxLag = false, 1000
c0 = #MOCK.logs
w = ramjet()
local lFree = checkLine(c0, 'picture')
V.fhOpt.freeze, V.fhOpt.maxLag = true, 600
local first3 = 'seat speed ([%d.]+/[%d.]+/[%d.]+)'
note('time lines: '..tostring(part(lFree, 'at 0.05.*')))
check('check, time lines: like the old one for 0.2 s (0.60 / 0.60 / 0.76), then catches up faster',
    part(lFree, first3) == '0.60/0.60/0.76' and num(lFree, 'looked up to ([%d.]+)') > 1.1, true)
-- (UEVR's object check knows the vehicles and effects but not your body part, as in the game on
-- 2026-10-27: the body was dropped as gone and never moved. It must move all the same.)
UEVR_UObjectHook = { exists = function(o) return o ~= myBody and o ~= myFx end }
c0 = #MOCK.logs
w = ramjet()
UEVR_UObjectHook = nil
lf = checkLine(c0, 'picture')
note('object check blind to your body: '..tostring(part(lf, 'hold looked [^;]*'))..'; '..tostring(part(lf, 'your body drawn behind in [%d]+ of [%d]+ frames')))
check('UEVR does not know your body part and effects: drawn behind and slowed all the same',
    w.lagMe > 500 and w.fxMe < 0.7 and num(lf, 'hold looked ([%d.]+)') < 0.7 and part(lf, 'drawn behind in (%d+) of') == part(lf, 'drawn behind in %d+ of (%d+) frames'), true)
-- (the catch-up, gentle - at most 8 in 100 faster, the default: no second kick, it takes longer instead)
V.fhOpt.catchMax, V.fhOpt.maxLag = 8, 1000
c0 = #MOCK.logs
v.RamjetState = 0; frames(0.5); beside(); v.RamjetState = 3
for i = 1, 200 do MOCK.frame(1 / 72) end
local lg = checkLine(c0, 'picture')
V.fhOpt.catchMax, V.fhOpt.maxLag = 100, 600
note('gentle catch-up: '..tostring(part(lg, 'then caught up[^;]*'))..'; '..tostring(part(lg, 'at 0.05.*seat speed [%d./-]+')))
check('gentle catch-up: never above 1.09, slower to catch up, all given back, back after', num(lg, 'looked up to ([%d.]+)') <= 1.09
    and num(lg, 'caught up in ([%d.]+) s') > 1.2 and math.abs(num(lg, '([%d.]+) s given back') - num(lg, '([%d.]+) s behind')) < 0.01
    and string.format('%.1f', myBody.RelativeLocation.X) == '0.0', true)
-- (right after the stall - the default: from the stall straight on to the catch-up, no stretch at the
-- game's speed in between, one move)
V.fhOpt.sling, V.fhOpt.maxLag = true, 1000
c0 = #MOCK.logs
v.RamjetState = 0; frames(0.5); beside(); v.RamjetState = 3
for i = 1, 108 do MOCK.frame(1 / 72) end
local lsl = checkLine(c0, 'picture')
V.fhOpt.sling, V.fhOpt.maxLag = false, 600
note('right after the stall: '..tostring(part(lsl, 'then caught up[^;]*'))..'; '..tostring(part(lsl, 'at 0.05.*seat speed [%d./-]+')))
check('right after the stall: slow in the stall, already past the game at 0.3 s, one push, all given back, back after',
    num(lsl, 'seat speed ([%d.]+)/') < 0.65 and num(lsl, 'seat speed [%d.]+/[%d.]+/[%d.]+/([%d.]+)/') > 1.15
    and num(lsl, 'looked up to ([%d.]+)') > 1.2 and lsl:find('right after the stall', 1, true) ~= nil
    and math.abs(num(lsl, '([%d.]+) s given back') - num(lsl, '([%d.]+) s behind')) < 0.02
    and string.format('%.1f/%.2f', myBody.RelativeLocation.X, myFx.dil) == '0.0/1.00', true)
-- (a stall bigger than the farthest - strength 1 for 0.4 s at 200 mph wants 27 m, the farthest is 6 m: it is
-- cut where it can go no further and the catch-up comes at once, never a stretch at normal speed between)
V.fhOpt.sling = true
V.setOwnVal('detail', V.model, 'hitstopStrength', 1.0); V.setOwnVal('detail', V.model, 'hitstopTime', 0.4)
c0 = #MOCK.logs
v.RamjetState = 0; frames(0.5); beside(); v.RamjetState = 3
for i = 1, 108 do MOCK.frame(1 / 72) end
local lcut = checkLine(c0, 'picture')
V.setOwnVal('detail', V.model, 'hitstopStrength', 0.53); V.setOwnVal('detail', V.model, 'hitstopTime', 0.16)
V.fhOpt.sling = false
note('a stall too big: '..tostring(part(lcut, 'the stall cut[^;]*'))..'; '..tostring(part(lcut, 'at 0.05.*seat speed [%d./-]+')))
check('a stall too big for the farthest: cut, then caught up at once (past the game by 0.2 s), back after',
    lcut ~= nil and lcut:find('the stall cut at', 1, true) ~= nil and num(lcut, 'seat speed ([%d.]+)/') < 0.6
    and num(lcut, 'seat speed [%d.]+/[%d.]+/([%d.]+)/') > 1.1 and string.format('%.1f', myBody.RelativeLocation.X) == '0.0', true)
MOCK.seatFollows = nil
-- 5. a hit in the middle (200 mph forward -> 40 mph back): the drawn body bends, never jumps
w = ramjet(function(i) if i == 8 then v.Velocity = { X = -40 * MPH, Y = 0, Z = 0 } end end)
drive(200); frames(1)
note(string.format('a hit in the middle: your body moved at most %.1f cm in a frame (it was metres before)', w.step))
check('a hit in the middle: no jump (under 60 cm a frame), back after', w.step < 60 and w.after:sub(1, 3) == '0.0', true)
w = ramjet()
check('  a plain ramjet: no jump either', w.step < 60, true)
-- 6. the game never works with a moved part: back where the game had it at the start of each tick,
-- drawn behind again before the frame; a place the game gives it meanwhile is its new resting place
local function tickOnly(dt)
    MOCK.clockT = MOCK.clockT + dt
    MOCK.gameTime = (MOCK.gameTime or 0) + dt
    local t, vel = v.VehicleTransform.Translation, v.Velocity
    t.X, t.Y, t.Z = t.X + vel.X * dt, t.Y + vel.Y * dt, t.Z + vel.Z * dt
    MOCK.fire('tick', nil, dt)
end
local function drawOnly()
    MOCK.fire('frame'); MOCK.fire('draw')
    for view = 0, 1 do MOCK.fire('stereo', nil, view, 1, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }) end
end
v.RamjetState = 0; frames(0.5); beside(); v.RamjetState = 3
local backAtTick, drawnMe, drawnOther = true, 0, 0
for i = 1, 30 do
    tickOnly(1 / 72)
    if math.abs(myBody.RelativeLocation.X) > 0.01 or math.abs(otherBody.RelativeLocation.X) > 0.01 then backAtTick = false end
    if i == 10 then myBody.RelativeLocation = { X = 0, Y = 0, Z = 17.7 } end      -- (the game lifts it, as at the race start)
    drawOnly()
    drawnMe, drawnOther = math.max(drawnMe, -myBody.RelativeLocation.X), math.max(drawnOther, -otherBody.RelativeLocation.X)
end
frames(1.5)
note(string.format('ticks: back at each tick %s; drawn behind before the frame: you %.0f cm, the other %.0f cm', tostring(backAtTick), drawnMe, drawnOther))
check('back at the start of each tick, drawn behind before each frame', backAtTick and drawnMe > 100 and drawnOther > 100, true)
check('  the place the game gave it meanwhile kept, no lag left in it', string.format('%.1f/%.1f', myBody.RelativeLocation.X, myBody.RelativeLocation.Z), '0.0/17.7')
myBody.RelativeLocation = { X = 0, Y = 0, Z = 0 }; frames(0.5)
-- 6b. the pause menu in the middle: the world stands still, so do you and the others; on afterwards
v.RamjetState = 0; frames(0.5); beside(); v.RamjetState = 3
for i = 1, 6 do MOCK.frame(1 / 72) end
MOCK.paused = true
for i = 1, 3 do MOCK.frame(1 / 72) end
local p0, slide = -myBody.RelativeLocation.X, 0
for i = 1, 40 do MOCK.frame(1 / 72); slide = math.max(slide, math.abs(-myBody.RelativeLocation.X - p0)) end
MOCK.paused = false
frames(1.5)
note(string.format('paused in the middle: drawn %.0f cm behind, moved %.1f cm while paused', p0, slide))
check('paused in the middle: you stay where you were drawn, back after', p0 > 100 and slide < 1 and string.format('%.1f', myBody.RelativeLocation.X) == '0.0', true)
-- 6c. a crash in the middle with the outside view off: the cockpit view goes on, no jump
S.showCrashCamera = false
w = ramjet(function(i)
    if i == 15 then v.IsWrecked = function() return true end end
    if i == 60 then v.IsWrecked = function() return false end end
end)
S.showCrashCamera = true
note(string.format('a crash in the middle: your body moved at most %.1f cm in a frame', w.step))
check('a crash in the middle (outside view off): no jump, back after', w.step < 60 and w.after:sub(1, 3) == '0.0', true)
frames(1)
-- 6d. the others unticked in the middle, then the game places the other vehicle's part itself: its
-- place is kept at the end (not the one from before)
w = ramjet(function(i)
    if i == 10 then V.fhOpt.others = false end
    if i == 12 then otherBody.RelativeLocation = { X = 0, Y = 0, Z = 17.7 } end
end)
V.fhOpt.others = true
check('the game placed a part itself in the middle: its place kept at the end', string.format('%.1f/%.1f', otherBody.RelativeLocation.X, otherBody.RelativeLocation.Z), '0.0/17.7')
otherBody.RelativeLocation = { X = 0, Y = 0, Z = 0 }
-- 6e. a second ramjet in the catch-up, the shake held: the hold starts again from where the view is, never
-- from what the first one held (that bug snapped the view back to it in one frame)
V.fhOpt.freeze = true
local firstD, beforeD, afterD = 0, 0, 0
w = ramjet(function(i)
    if i == 2 then firstD = V.feelDown or 0 end              -- (what the first one holds)
    if i == 30 then v.RamjetState = 0 end
    if i == 31 then v.RamjetState = 3; beforeD = V.feelDown or 0 end
    if i == 32 then afterD = V.feelDown or 0 end
end)
V.fhOpt.freeze = false
frames(1)
note(string.format('a second ramjet in the catch-up: the view up / down %.2f before, %.2f after; the first one held %.2f', beforeD, afterD, firstD))
check('a second ramjet in the catch-up: not snapped back to what the first one held',
    not (math.abs(afterD - firstD) < 0.05 and math.abs(beforeD - firstD) > 0.5), true)
-- 7. another vehicle's part can not be moved: put back, said once, left alone from then on; the saved
-- setting untouched
MOCK.moveError = otherBody
local logs0 = #(MOCK.logs or {})
w = ramjet(); w = ramjet()
MOCK.moveError = nil
local n = logged(logs0, 'a part left alone from now on')
note('another vehicle failing: said '..n..' times')
check('another vehicle failing: said once, you still drawn behind, the setting kept', n == 1 and w.lagMe > 500 and V.fhOpt.others == true, true)
-- 8. your body can not be moved: said once, then left alone (no retry every frame), the reason kept
MOCK.moveError = myBody
logs0 = #(MOCK.logs or {})
w = ramjet(); w = ramjet()
MOCK.moveError = nil
n = logged(logs0, 'hit-stop: your body part can not be moved')
info = V.hitstopInfo()
note('your body failing: said '..n..' times; menu: '..tostring(info.ownWhy))
check('your body failing: said once, left alone after, the setting kept', n == 1 and info.ownWhy == 'its body part can not be moved (see the log)' and V.fhOpt.view == true, true)
-- 9. a body that collides with physics: left alone, said in the log
MOCK.bodyCollision = 3
logs0 = #(MOCK.logs or {})                 -- (from here: it is looked into ahead, before the first boost)
local me2, v2 = MOCK.makeVehicle('Skimmer', 'Saker')
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { me2 }
MOCK.pawn, v, myBody = me2, v2, MOCK.bodyRoot
drive(200); frames(2)
w = ramjet()
check('a body colliding with physics: not drawn behind, said in the log', w.lagMe < 0.5 and logged(logs0, '1 with physics') > 0 and w.dil == 0, true)
local warmSaid = false
for i = logs0 + 1, #MOCK.logs do
    local l = MOCK.logs[i]
    if l:find('1 with physics', 1, true) then warmSaid = true; break end
    if l:find('ramjet at', 1, true) then break end
end
check('  looked into ahead: said before the first boost', warmSaid, true)
MOCK.bodyCollision = nil
-- 10. a query-only body that sends overlap events: left alone too (it would enter and leave triggers)
MOCK.bodyOverlap = true
logs0 = #(MOCK.logs or {})
local me4, v4 = MOCK.makeVehicle('Skimmer', 'Merlin')
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { me4 }
MOCK.pawn, v, myBody = me4, v4, MOCK.bodyRoot
drive(200); frames(2)
w = ramjet()
check('a body with overlap events: not drawn behind, said in the log', w.lagMe < 0.5 and logged(logs0, '1 query with overlap events') > 0, true)
MOCK.bodyOverlap = nil
-- 10b. another vehicle with a hit shape (physics) in its body, as every one in the game had: what hangs
-- under its holder drawn behind one by one, the hit shape never moved, said in the log
logs0 = #(MOCK.logs or {})                 -- (from here: it may be looked into ahead, before the boost)
MOCK.hitShape, MOCK.looseFx = true, true
local other7, ov7 = MOCK.makeVehicle('Bike', 'Shaper')
local seat7, laser7 = MOCK.seatComp, MOCK.looseFxComp
MOCK.hitShape, MOCK.looseFx = nil, nil
ov7.Velocity = { X = 150 * MPH, Y = 0, Z = 0 }
local me8, v8 = MOCK.makeVehicle('Car', 'Beluga')
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { me8, other7 }
MOCK.pawn, v, myBody = me8, v8, MOCK.bodyRoot
drive(200); frames(2)
v.RamjetState = 0; frames(0.5)
local t8 = v.VehicleTransform.Translation
ov7.VehicleTransform.Translation = { X = t8.X + 300, Y = t8.Y + 400, Z = t8.Z }
local hit0, seatMost = MOCK.hitMoves or 0, 0
v.RamjetState = 3
local laser7Most = 0
for i = 1, 108 do MOCK.frame(1 / 72); seatMost = math.max(seatMost, -seat7.RelativeLocation.X); laser7Most = math.max(laser7Most, -laser7.RelativeLocation.X) end
note(string.format('another vehicle (not a podracer): the effect on its middle moved %.0f cm', laser7Most))
check('another vehicle, not a podracer: the effect on its middle left as it is (only podracers have a laser there)', laser7Most < 0.5, true)
note(string.format('another vehicle with a hit shape: its seat mesh drawn up to %.0f cm behind, the hit shape moved %d times', seatMost, (MOCK.hitMoves or 0) - hit0))
check('another vehicle with a hit shape: drawn behind part by part, the hit shape never moved, said, back after',
    seatMost > 300 and (MOCK.hitMoves or 0) == hit0 and logged(logs0, 'one by one') > 0 and string.format('%.1f', seat7.RelativeLocation.X) == '0.0', true)
-- 11. podracers (with them off first: V.fhOpt.pods)
V.fhOpt.pods = false
MOCK.podLayout = true
local podLogs0 = #(MOCK.logs or {})          -- (from here: looked into ahead once on, before a boost)
local me3, v3 = MOCK.makeVehicle('Plane', 'Myth')
local pod = MOCK.podMesh
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { me3 }
MOCK.pawn, v = me3, v3
drive(250); frames(2)
local podMax0 = MOCK.podMax or 0
logs0 = #(MOCK.logs or {})
w = ramjet()
check('a podracer: its pod not drawn behind (Podracers too off), said', (MOCK.podMax or 0) <= math.max(podMax0, 6.01) and logged(logs0, 'Podracers too is off') > 0 and w.dil == 0, true)
-- (podracers too, but the pod collides with physics - the mock's pod: left alone, said)
V.fhOpt.pods = true
MOCK.podMax, logs0 = 0, #(MOCK.logs or {})
w = ramjet()
check('podracers too, a pod with physics collision: not drawn behind, said', (MOCK.podMax or 0) <= 6.01 and logged(podLogs0, 'your pod') > 0 and logged(podLogs0, 'left alone') > 0, true)
-- (podracers too, a pod free of collision, offline: drawn behind, its container never moved, back after)
MOCK.podCollision, MOCK.looseFx = 0, true
local otherPod, ovp = MOCK.makeVehicle('Plane', 'Hexing')             -- (another podracer with its laser, beside you)
local otherLaser = MOCK.looseFxComp
ovp.Velocity = { X = 250 * MPH, Y = 0, Z = 0 }
local me5, v5 = MOCK.makeVehicle('Plane', 'Mythos')
pod = MOCK.podMesh
local laser = MOCK.looseFxComp
MOCK.looseFx = nil
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { me5, otherPod }
MOCK.pawn, v = me5, v5
drive(250); frames(2)
local contCalls0 = MOCK.alongCalls or 0
MOCK.podMax = 0
local laserMost, otherLaserMost = 0, 0
w = ramjet(function(i)
    if i == 1 then local t = v.VehicleTransform.Translation; ovp.VehicleTransform.Translation = { X = t.X + 300, Y = t.Y + 400, Z = t.Z } end
    laserMost, otherLaserMost = math.max(laserMost, -laser.RelativeLocation.X), math.max(otherLaserMost, -otherLaser.RelativeLocation.X)
end)
note(string.format('  the other podracer: its laser drawn up to %.0f cm behind', otherLaserMost))
check('  the other podracer: its laser drawn behind with it, back after', otherLaserMost > 300 and string.format('%.1f', otherLaser.RelativeLocation.X) == '0.0', true)
note(string.format('podracers too, free of collision: pod moved up to %.0f cm, its container moved %d times', MOCK.podMax or 0, (MOCK.alongCalls or 0) - contCalls0))
check('podracers too, offline, free of collision: the pod drawn behind, the container left, the game not slowed', (MOCK.podMax or 0) > 300 and (MOCK.alongCalls or 0) == contCalls0 and w.dil == 0, true)
check('  and back after', string.format('%.1f', pod.RelativeLocation.X), '0.0')
local laserSaid = false
for _, l in ipairs(MOCK.logs or {}) do if l:find('beams drawn behind with it too', 1, true) and l:find('NS_PlasmaBeam', 1, true) then laserSaid = true end end
note(string.format('  the laser drawn up to %.0f cm behind', laserMost))
check('  the laser on its middle drawn behind with it (said), back after', laserMost > 300 and laserSaid and string.format('%.1f', laser.RelativeLocation.X) == '0.0', true)
local leftLine = nil
for i = #MOCK.logs, 1, -1 do if MOCK.logs[i]:find('your parts not drawn behind', 1, true) then leftLine = MOCK.logs[i]; break end end
note('podracer: '..tostring(leftLine and leftLine:match('your parts not drawn behind.*')))
check('  the parts not drawn behind said (once per vehicle)', leftLine ~= nil and leftLine:find('VehicleBody', 1, true) ~= nil
    and leftLine:find('SkeletalPart0_SKM_PodRoot', 1, true) == nil, true)
-- (online: drawn behind as well - V.fhOpt.podsOnline)
MOCK.online, MOCK.podMax = true, 0
w = ramjet()
check('podracers online: drawn behind as well', (MOCK.podMax or 0) > 300 and string.format('%.1f', pod.RelativeLocation.X) == '0.0', true)
-- (with podracers offline only: online they are left alone, said)
V.fhOpt.podsOnline = false
MOCK.podMax, logs0 = 0, #(MOCK.logs or {})
w = ramjet()
info = V.hitstopInfo()
check('podracers offline only, online: left alone, said', (MOCK.podMax or 0) <= 6.01 and logged(logs0, 'offline only') > 0 and info.ownWhy == 'podracers: offline only for now', true)
V.fhOpt.podsOnline = true
MOCK.online, MOCK.podCollision, MOCK.podLayout = nil, nil, nil
V.fhOpt.pods = false
-- 13. the menu: the hit-stop's checkbox in Boost effects (its new name), no test section, no hotkey
MOCK.ui.labels, MOCK.ui.texts = {}, {}
MOCK.menu('idle')
local found, testSection = 0, 0
for _, l in ipairs(MOCK.ui.labels) do
    if l:find(V.tr('Hit-stop at boosts and the race start'), 1, true) then found = found + 1 end
    if l:find('##fh', 1, true) then testSection = testSection + 1 end      -- (its options' ids: fhView, fhOthers ...)
end
local hotkey = false
for _, a in ipairs(V.HOTKEY_ACTIONS) do if a.id:find('Hitstop', 1, true) then hotkey = true end end
check('menu: the hit-stop checkbox there, no test section, no hotkey', found > 0 and testSection == 0 and not hotkey, true)
-- 14. the race start with many vehicles near: a few looked into per frame, all drawn behind soon
local racers = {}
for n = 1, 5 do
    local o, ovn = MOCK.makeVehicle('Bike', 'Racer'..n)
    ovn.Velocity = { X = 150 * MPH, Y = 0, Z = 0 }
    racers[n] = { pawn = o, v = ovn, body = MOCK.bodyRoot }
end
local me6, v6 = MOCK.makeVehicle('Car', 'Mako')
local list = { me6 }
for n = 1, 5 do list[#list + 1] = racers[n].pawn end
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = list
MOCK.pawn, v, myBody = me6, v6, MOCK.bodyRoot
local function drawnCount() local c = 0; for n = 1, 5 do if racers[n].body.RelativeLocation.X < -0.5 then c = c + 1 end end; return c end
local function gather() local tt = v.VehicleTransform.Translation; for n = 1, 5 do racers[n].v.VehicleTransform.Translation = { X = tt.X + 300 * n, Y = tt.Y + 400, Z = tt.Z } end end
-- (on the grid: standing, everyone near, a moment before the launch - looked into ahead)
v.SpeedMPH, v.Velocity = 0, { X = 0, Y = 0, Z = 0 }
for n = 1, 5 do racers[n].v.Velocity = { X = 0, Y = 0, Z = 0 } end
gather(); frames(2.5)
drive(200); for n = 1, 5 do racers[n].v.Velocity = { X = 150 * MPH, Y = 0, Z = 0 } end
v.RamjetState = 3
MOCK.frame(1 / 72)
local gridN = drawnCount()
frames(1.5)
note('on the grid, looked into ahead: drawn behind in the first frame of the launch '..gridN..' of 5')
check('on the grid: the others looked into ahead, all drawn behind from the first frame', gridN == 5 and drawnCount() == 0, true)
-- (later, five that were never near before - new ones: a few looked into a frame)
for n = 1, 5 do
    local o, ovn = MOCK.makeVehicle('Bike', 'Late'..n)
    ovn.Velocity = { X = 150 * MPH, Y = 0, Z = 0 }
    racers[n] = { pawn = o, v = ovn, body = MOCK.bodyRoot }
end
MOCK.lastVehicle = v6
list = { me6 }
for n = 1, 5 do list[#list + 1] = racers[n].pawn end
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = list
v.RamjetState = 0; frames(0.5)
gather()
v.RamjetState = 3
MOCK.frame(1 / 72)
local firstN = drawnCount()
for i = 1, 20 do MOCK.frame(1 / 72) end
local soonN = drawnCount()
frames(1.5)
note('many vehicles near: drawn behind after the first frame '..firstN..', a few frames later '..soonN..', after it '..drawnCount())
check('many vehicles near: looked into a piece a frame (not all at once), all 5 drawn behind soon, all back after', firstN < 5 and soonN == 5 and drawnCount() == 0, true)
-- 14a. more vehicles near than are drawn behind (6): the ones ahead and beside you first, two right
-- behind you left out
local front, back = {}, {}
for n = 1, 6 do local o, ovn = MOCK.makeVehicle('Bike', 'Front'..n); front[n] = { pawn = o, v = ovn, body = MOCK.bodyRoot } end
for n = 1, 2 do local o, ovn = MOCK.makeVehicle('Bike', 'Back'..n); back[n] = { pawn = o, v = ovn, body = MOCK.bodyRoot } end
local me7, v7 = MOCK.makeVehicle('Car', 'Mako')
list = { me7 }
for _, x in ipairs(front) do list[#list + 1] = x.pawn end
for _, x in ipairs(back) do list[#list + 1] = x.pawn end
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = list
MOCK.pawn, v, myBody = me7, v7, MOCK.bodyRoot
drive(200); frames(1)
local function place()
    local t = v.VehicleTransform.Translation
    for n, x in ipairs(front) do x.v.VehicleTransform.Translation = { X = t.X + 2000 + 1000 * n, Y = t.Y + 300, Z = t.Z }; x.v.Velocity = { X = 200 * MPH, Y = 0, Z = 0 } end
    for n, x in ipairs(back) do x.v.VehicleTransform.Translation = { X = t.X - 400 * n, Y = t.Y + 200, Z = t.Z }; x.v.Velocity = { X = 200 * MPH, Y = 0, Z = 0 } end
end
local frontMost, backMost = {}, {}
v.RamjetState = 0; place(); frames(1); place()
v.RamjetState = 3
for i = 1, 60 do
    place()
    MOCK.frame(1 / 72)
    for n, x in ipairs(front) do frontMost[n] = math.max(frontMost[n] or 0, -x.body.RelativeLocation.X) end
    for n, x in ipairs(back) do backMost[n] = math.max(backMost[n] or 0, -x.body.RelativeLocation.X) end
end
frames(1.5)
local frontN, backN = 0, 0
for n = 1, 6 do if frontMost[n] > 50 then frontN = frontN + 1 end end
for n = 1, 2 do if backMost[n] > 0.5 then backN = backN + 1 end end
note('eight near: ahead and beside drawn behind '..frontN..' of 6, right behind you '..backN..' of 2')
check('eight near: the six ahead drawn behind, the two right behind you left out', frontN == 6 and backN == 0, true)
-- 14b. a bike jumping while the hit-stop runs: the view keeps following the rider as before - the
-- body follow reads the chest where it really is and the seat drawn last frame, the hit-stop's move taken
-- off (2026-10-27, the user: "in jumps the view sometimes does not follow the rider")
local bike, bv = MOCK.makeVehicle('Bike', 'Taipan')
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { bike }
MOCK.pawn, v, myBody = bike, bv, MOCK.bodyRoot
MOCK.seatFollows = true
drive(200); frames(2)
local function jumpBoost()
    v.RamjetState = 0; frames(0.5)
    v.TimeInAir, v.OnGroundScale = 0.6, 0
    local most = 0
    v.RamjetState = 3
    for i = 1, 60 do MOCK.frame(1 / 72); most = math.max(most, math.abs(V.feelFwd or 0)) end
    v.TimeInAir, v.OnGroundScale = 0, 1
    frames(2)
    return most
end
V.cfg.hitstop = false
local offMost = jumpBoost()
V.cfg.hitstop = true
local onMost = jumpBoost()
MOCK.seatFollows = nil
note(string.format('a bike jumping: the eye forward at most %.1f cm with the hit-stop off, %.1f cm with it on', offMost, onMost))
check('a bike jumping with the hit-stop: the view follows the rider as without it', onMost < offMost + 3, true)
-- 15. the hit-stop fails to start (last: it stays stopped): said once, the ramjet once - not fired
-- again every frame -, stopped (said in the menu), and the game never slowed instead
V.cfg.hitstop = true
local logsS, dilS = #(MOCK.logs or {}), MOCK.dilationCalls or 0
local keepView = V.fhOpt.view
V.fhOpt.view = nil
setmetatable(V.fhOpt, { __index = function(t, k) if k == 'view' then error('test: view can not be read') end end })
v.RamjetState = 0; frames(0.5); v.RamjetState = 3; frames(1)
setmetatable(V.fhOpt, nil); V.fhOpt.view = keepView
info = V.hitstopInfo()
note('failing to start: said '..logged(logsS, 'starting it failed')..' times, ramjet events '..logged(logsS, 'ramjet at'))
check('failing to start: said once, the ramjet once, stopped, the game never slowed',
    logged(logsS, 'starting it failed') == 1 and logged(logsS, 'ramjet at') == 1 and info.stopped == true and (MOCK.dilationCalls or 0) == dilS, true)
-- (the menu now: stopped, said; then every widget clicked)
MOCK.ui.labels, MOCK.ui.texts = {}, {}
MOCK.menu('idle')
local stoppedLine = false
for _, l in ipairs(MOCK.ui.texts) do if l:find(V.tr('The hit-stop stopped after an error (see the log)'), 1, true) then stoppedLine = true end end
check('menu: stopped after an error, said', stoppedLine, true)
MOCK.menu('click'); MOCK.menu('idle')
"""

# a 2.1.1 player: the hit-stop turned off and their own ramjet strength stay; what they never set takes
# the new defaults (cars too)
OLD_211 = r"""
check('2.1.1 values kept: off, their ramjet strength; the rest the new defaults',
    string.format('%s %.2f/%.2f/%.2f %.2f', tostring(V.cfg.hitstop), V.valFor('Car/Mako', 'hitstopStrength'), V.valFor('Car/Mako', 'hitstopAB'),
        V.valFor('Car/Mako', 'hitstopTime'), V.valFor('Plane/Myth', 'hitstopStrength')), 'false 0.90/0.50/0.10 0.90')
"""

# values equal to the old defaults: from a 2.1.1 file they were never the player's own (the new defaults
# instead, as 2.1.1 would have dropped them too); from this version's files they were chosen and stay
OLD_NUMBERS = {'swgr_vr_settings.json': {'hitstop': True, 'detail': {'hitstopStrength': 0.333, 'hitstopAB': 0.077, 'hitstopTime': 0.164}},
               'swgr_vr_vehicles.json': {'eyes': {}, 'feel': {}, 'pilotFollow': {}, 'maps': {}, 'legacy': {}, 'moved': {},
                                         'detail': {'Car/Mako': {'hitstopStrength': 0.53, 'hitstopAB': 0.33, 'hitstopTime': 0.16},
                                                    'Bike/Taipan': {'hitstopStrength': 0.53, 'hitstopTime': 0.16}}}}
OLD_NUMBERS_211 = {k: dict(v, format=f) for (k, v), f in zip(OLD_NUMBERS.items(), (2, 4))}
OLD_NUMBERS_NOW = {k: dict(v, format=f) for (k, v), f in zip(OLD_NUMBERS.items(), (3, 5))}
USES = r"""
local function uses()
    local t = {}
    for _, m in ipairs({ 'Car/Mako', 'Bike/Taipan', 'Plane/Myth' }) do
        t[#t + 1] = string.format('%s %.3f/%.3f/%.3f', m, V.valFor(m, 'hitstopStrength'), V.valFor(m, 'hitstopAB'), V.valFor(m, 'hitstopTime'))
    end
    return table.concat(t, ', ')
end
note('uses: '..uses())
"""
OLD_NUMBERS_211_BODY = USES + r"""
check('old numbers in 2.1.1 files: the new defaults (a bike keeps its own)', uses(),
    'Car/Mako 0.700/0.500/0.100, Bike/Taipan 0.530/0.500/0.160, Plane/Myth 0.700/0.500/0.100')
"""
OLD_NUMBERS_NOW_BODY = USES + r"""
check('old numbers chosen in this version: kept', uses(),
    'Car/Mako 0.530/0.330/0.160, Bike/Taipan 0.530/0.077/0.160, Plane/Myth 0.333/0.077/0.164')
-- (and on every start after: saved, read again the same)
V.saveNow(); V.saveVehNow()
check('saved in the formats of today', tostring(MOCK.files['swgr_vr_settings.json'].format)..'/'..tostring(MOCK.files['swgr_vr_vehicles.json'].format), '3/5')
"""


# The hit-stop as it ships (V.fhOpt untouched), cases from the review before the release (2026-10-27):
# nothing in the log when nothing fails; a vehicle whose parts are made anew; the looking ahead stops
# when no hit-stop can come; a part that can not be moved is left alone for good
RELEASE = r"""
local MPH = 44.704
V.cfg.extras, V.cfg.feelOn, V.cfg.hitstop = true, true, true
local gaa = MOCK.cdo.GetAllActorsOfClass
local nFind = 0
rawset(MOCK.cdo, 'GetAllActorsOfClass', function(...) nFind = nFind + 1; return gaa(...) end)
local other, ov = MOCK.makeVehicle('Bike', 'Opp')
local oldBody = MOCK.bodyRoot
ov.Velocity = { X = 150 * MPH, Y = 0, Z = 0 }
MOCK.looseFx = true
local me, v = MOCK.makeVehicle('Car', 'Mako')
local myBody, laser = MOCK.bodyRoot, MOCK.looseFxComp
MOCK.looseFx = nil
MOCK.objectsOf = MOCK.objectsOf or {}
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { me, other }
MOCK.pawn = me
local function beside() local t = v.VehicleTransform.Translation; ov.VehicleTransform.Translation = { X = t.X + 300, Y = t.Y + 400, Z = t.Z } end
local function run(sec) for i = 1, math.floor(sec * 72) do beside(); MOCK.frame(1 / 72) end end
local function lines(from, text)
    local n = 0
    for i = from + 1, #(MOCK.logs or {}) do if MOCK.logs[i]:find(text, 1, true) then n = n + 1 end end
    return n
end
local function ramjet() v.RamjetState = 0; run(0.2); v.RamjetState = 3; run(1.5) end
v.SpeedMPH, v.Throttle, v.IgnitionStatus = 200, 1, 3
v.Velocity = { X = 200 * MPH, Y = 0, Z = 0 }
local logs0 = #(MOCK.logs or {})
run(3)
-- 1. a ramjet and an afterburner as they ship: everything back, nothing in the log
ramjet()
v.AfterburnerState = 0; v.AfterburningTime = 0.3; run(1.5); v.AfterburnerState = 2; run(0.5)
note(string.format('as it ships: your body %.1f, the other %.1f after; hit-stop lines in the log %d', myBody.RelativeLocation.X, oldBody.RelativeLocation.X, lines(logs0, 'hit-stop')))
check('as it ships: all back, no hit-stop line in the log when nothing fails',
    string.format('%.1f/%.1f %d', myBody.RelativeLocation.X, oldBody.RelativeLocation.X, lines(logs0, 'hit-stop')), '0.0/0.0 0')
-- 2. the other vehicle's parts made anew (same vehicle, new parts - its old body gone): looked into again,
-- the new body drawn behind, the gone one never touched
local donor = MOCK.makeVehicle('Bike', 'OppRebuilt')
local newBody = MOCK.bodyRoot
MOCK.lastVehicle = v
rawset(other, 'K2_GetComponentsByClass', function(self, c) return donor:K2_GetComponentsByClass(c) end)
rawset(other, 'RootComponent', donor.RootComponent)
local oldMoves, newMoves = 0, 0
local fo, fn = oldBody.K2_SetRelativeLocation, newBody.K2_SetRelativeLocation
rawset(oldBody, 'K2_SetRelativeLocation', function(self, ...) oldMoves = oldMoves + 1; return fo(self, ...) end)
rawset(newBody, 'K2_SetRelativeLocation', function(self, ...) newMoves = newMoves + 1; return fn(self, ...) end)
run(4)
ramjet()
note('parts made anew: the gone body moved '..oldMoves..' times, the new one '..newMoves)
check('parts made anew: the new body drawn behind, the gone one never touched', oldMoves == 0 and newMoves > 0 and string.format('%.1f', newBody.RelativeLocation.X) == '0.0', true)
-- 3. no hit-stop can come (the add-on effects off, the cockpit shake off, both strengths 0): it does not
-- look at the other vehicles all race
local function finds(label)
    local n0 = nFind
    v.RamjetState = 0; run(0.2); v.RamjetState = 3; run(10)
    note(label..': the vehicles listed '..(nFind - n0)..' times in 10 s')
    return nFind - n0
end
local nNew = 0
local newPawn = function()
    -- (a new vehicle - its own address - the looking ahead starts again for it)
    nNew = nNew + 1
    local p2, v2 = MOCK.makeVehicle('Car', 'Mako'..nNew)
    MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { p2, other }
    MOCK.pawn = p2
    v2.SpeedMPH, v2.Throttle, v2.IgnitionStatus = 200, 1, 3
    v2.Velocity = { X = 200 * MPH, Y = 0, Z = 0 }
    v = v2
    run(1)
end
newPawn(); V.cfg.extras = false
local a = finds('the add-on effects off')
V.cfg.extras = true; newPawn(); V.cfg.feelOn = false
local b = finds('the cockpit shake off')
V.cfg.feelOn = true; newPawn()
V.setOwnVal('detail', V.model, 'hitstopStrength', 0); V.setOwnVal('detail', V.model, 'hitstopAB', 0)
local c = finds('both strengths 0')
V.clearOwnVal('detail', V.model)
-- (both strengths 0: once at most - the strengths are read again in the tick after they were set)
check('no hit-stop can come: the other vehicles are not looked at', a + b == 0 and c <= 1, true)
-- (turned back on: looked at again until the first boost)
local n0 = nFind
run(3)
note('back on: the vehicles listed '..(nFind - n0)..' times in 3 s')
check('back on: the other vehicles looked at again', nFind - n0 > 0, true)
"""
# your effect that can not be moved: left alone for good - not tried and said again at every boost
FX_FAIL = r"""
local MPH = 44.704
V.cfg.extras, V.cfg.feelOn, V.cfg.hitstop = true, true, true
MOCK.looseFx = true
local me, v = MOCK.makeVehicle('Car', 'Mako')
local laser = MOCK.looseFxComp
MOCK.looseFx = nil
local tries = 0
rawset(laser, 'K2_SetRelativeLocation', function() tries = tries + 1; error('K2_SetRelativeLocation: failed') end)
MOCK.objectsOf = MOCK.objectsOf or {}
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { me }
MOCK.pawn = me
v.SpeedMPH, v.Throttle, v.IgnitionStatus = 200, 1, 3
v.Velocity = { X = 200 * MPH, Y = 0, Z = 0 }
frames(2)
local logs0 = #(MOCK.logs or {})
for k = 1, 3 do
    v.RamjetState = 0; frames(1.5); v.RamjetState = 3
    for i = 1, 108 do MOCK.frame(1 / 72) end
end
local said = 0
for i = logs0 + 1, #(MOCK.logs or {}) do if MOCK.logs[i]:find('a part left alone from now on', 1, true) then said = said + 1 end end
note('an effect that can not be moved, 3 ramjets: said '..said..' times, tried '..tries..' times')
check('an effect that can not be moved: said once, not tried again', said == 1 and tries <= 2, true)
"""
# another vehicle with a part that can not be moved (E1) and one that breaks off later (E2): looked into
# again when E2 is gone - E1 still left alone, not tried and said again
FAILED_RELOOK = r"""
local MPH = 44.704
V.cfg.extras, V.cfg.feelOn, V.cfg.hitstop = true, true, true
-- a plain part, free of collision, hanging under parent
local function part(name, parent, fail)
    local c = { _name = name, RelativeLocation = { X = 0, Y = 0, Z = 0 }, tries = 0 }
    c.get_address = function() return 'part_'..name end
    c.get_fname = function() return { to_string = function() return name end } end
    c.is_a = function() return true end
    c.GetCollisionEnabled = function() return 0 end
    c.GetChildrenComponents = function(self, all, out) end
    c.GetAttachParent = function() return parent end
    c.IsSimulatingPhysics = function() return false end
    c.IsUsingAbsoluteLocation = function() return false end
    c.K2_SetRelativeLocation = function(self, l)
        self.tries = self.tries + 1
        if fail then error('K2_SetRelativeLocation: failed') end
        self.RelativeLocation = { X = l.X, Y = l.Y, Z = l.Z }
    end
    return setmetatable(c, { __index = function(_, k) error('part '..name..': no field '..tostring(k), 2) end })
end
MOCK.hitShape = true
local other, ov = MOCK.makeVehicle('Bike', 'Opp')
MOCK.hitShape = nil
local oBody = MOCK.bodyRoot
local E1, E2 = part('E1', oBody, true), part('E2', oBody, false)
local extra = { E1, E2 }
local kidsOf = oBody.GetChildrenComponents
rawset(oBody, 'GetChildrenComponents', function(self, all, out) kidsOf(self, all, out); for _, e in ipairs(extra) do out[#out + 1] = e end end)
local byClass = other.K2_GetComponentsByClass
rawset(other, 'K2_GetComponentsByClass', function(self, c)
    local l = byClass(self, c)
    if c.name:find('SceneComponent', 1, true) then
        local x = {}
        for _, a in ipairs(l) do x[#x + 1] = a end
        for _, e in ipairs(extra) do x[#x + 1] = e end
        return x
    end
    return l
end)
ov.Velocity = { X = 150 * MPH, Y = 0, Z = 0 }
local me, v = MOCK.makeVehicle('Car', 'Mako')
MOCK.objectsOf = MOCK.objectsOf or {}
MOCK.objectsOf['Class /Script/Griffin.VehiclePawn'] = { me, other }
MOCK.pawn = me
local function beside() local t = v.VehicleTransform.Translation; ov.VehicleTransform.Translation = { X = t.X + 300, Y = t.Y + 400, Z = t.Z } end
local function run(sec) for i = 1, math.floor(sec * 72) do beside(); MOCK.frame(1 / 72) end end
local function lines(from, text)
    local n = 0
    for i = from + 1, #(MOCK.logs or {}) do if MOCK.logs[i]:find(text, 1, true) then n = n + 1 end end
    return n
end
local function ramjet() v.RamjetState = 0; run(0.2); v.RamjetState = 3; run(1.5) end
v.SpeedMPH, v.Throttle, v.IgnitionStatus = 200, 1, 3
v.Velocity = { X = 200 * MPH, Y = 0, Z = 0 }
local logs0 = #(MOCK.logs or {})
run(3)
ramjet()
note(string.format('after ramjet 1: E1 tries %d, E2 tries %d, said %d', E1.tries, E2.tries, lines(logs0, 'a part left alone from now on')))
-- E2 broken off: gone from the vehicle's parts
extra = { E1 }
local e2t = E2.tries
run(4)
ramjet()
note(string.format('after ramjet 2 (E2 gone): E1 tries %d, E2 touched after gone %d, said %d', E1.tries, E2.tries - e2t, lines(logs0, 'a part left alone from now on')))
run(4)
ramjet()
note(string.format('after ramjet 3: E1 tries %d, said %d', E1.tries, lines(logs0, 'a part left alone from now on')))
run(4)
ramjet()
note(string.format('after ramjet 4: E1 tries %d, said %d; body %.1f', E1.tries, lines(logs0, 'a part left alone from now on'), MOCK.seatComp.RelativeLocation.X))
check('a part that failed: not tried again after the vehicle is looked into again, the gone one never touched',
    E1.tries == 2 and lines(logs0, 'a part left alone from now on') == 1 and E2.tries == e2t, true)
"""
# a broken vehicles file with lists where vehicle names go (it stopped the whole script): the script runs,
# what is right in it is kept
LISTS = {'swgr_vr_vehicles.json': {'format': 4, 'detail': [{'hitstopStrength': 0.5}, {}], 'feel': [{'road': 50}],
                                   'eyes': {'Car/Mako': [0, -10, 70]}, 'pilotFollow': {}, 'maps': {}, 'legacy': {}, 'moved': {}}}
LISTS_BODY = r"""
note('a vehicles file with lists where the names go: running '..tostring(V ~= nil)..', the eye kept '..tostring(V.veh.eyes['Car/Mako'] ~= nil))
check('a vehicles file with lists where the names go: the script runs, the rest kept', V.veh.eyes['Car/Mako'] ~= nil and next(V.veh.detail) == nil, true)
"""


def main():
    bad = 0
    for script in sys.argv[1:3]:
        print('==', script)
        for title, files, body in (('hit-stop', {}, HITSTOP),
                                   ('2.1.1 values', {'swgr_vr_settings.json': {'format': 2, 'hitstop': False, 'detail': {'hitstopStrength': 0.9}}}, OLD_211),
                                   ('the old numbers in 2.1.1 files', OLD_NUMBERS_211, OLD_NUMBERS_211_BODY),
                                   ('the old numbers chosen in this version', OLD_NUMBERS_NOW, OLD_NUMBERS_NOW_BODY),
                                   ('the release settings', {}, RELEASE),
                                   ('an effect that can not be moved', {}, FX_FAIL),
                                   ('a part that failed, then a re-look', {}, FAILED_RELOOK),
                                   ('a vehicles file with lists', LISTS, LISTS_BODY)):
            notes, fails = P.session(script, files, body)
            print('-- ' + title)
            for n in notes.split('\n'):
                print('   ' + n)
            for f in [x for x in fails.split('\n') if x]:
                print('   FAIL ' + f)
                bad += 1
    print('RESULT:', 'FAIL (%d)' % bad if bad else 'OK')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
