"""The public build (the picture options still being worked on: off), in a mock game.

usage: python tools/luacheck/public_build_test.py <public KO script> [<public EN script>]

Checks: it is the public build; the options still being worked on are left out of the menu, their
values (saved by a working build) are kept in the file but not used, the game's areas are not read;
2.1.0's picture controls work per track and weather and older whole-map values move as in the working
build; the Korean build has every menu text it draws in Korean (missing ones listed)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import picture_weather_test as P  # noqa: E402  (its helpers: the Lua state, the mock, race(), check())

LAB_LABELS = ['Tone down glaring places (everywhere)', 'Lift dark places', 'Tunnels: less glare from outside', 'Deeper blacks',
              'Vibrance', 'Colour temperature', 'Keep bright skies from turning white', 'Expose for the bright outside, keep the inside',
              '  Inside lifted back with it', '  Keep the inside\'s contrast', '  Lamps, deep dark: not lifted too far',
              '  Lift by blending two pictures (Fusion)', 'Round glow card by lamps', 'Lamp light in the air', 'Starting point against glare']
OLD_LABELS = ['Brightness', 'Bloom (glow around bright things)', 'Colour strength (saturation)', 'Contrast',
              'Tunnels (older): leave out the dark part', 'Tunnels: brighten no further than', 'Bright parts (colour gain)']


def lua_list(xs):
    return '{ ' + ', '.join(P.json.dumps(x) for x in xs) + ' }'


PUBLIC = r'''
check('the public build', V.PIC_LAB, false)
-- (Korean: every text the menu looks up and has no Korean for)
local missing = {}
if V.LANG == 'ko' then
    -- (a text already in Korean, as tooltips pass on, is not one)
    setmetatable(V.KO, { __index = function(t, k) if type(k) == 'string' and not k:find('[-]') and k:find('%a') then missing[k] = true end end })
end
-- (the engine's actor lists asked for, by class)
local asked = {}
local listOf = MOCK.cdo.GetAllActorsOfClass
MOCK.cdo.GetAllActorsOfClass = function(self, w, cls, out) asked[cls.name] = (asked[cls.name] or 0) + 1; return listOf(self, w, cls, out) end
local VOL = 'Class /Script/SweejAmbience.SweejAmbienceVolume'
MOCK.objectsOf = MOCK.objectsOf or {}
MOCK.objectsOf[VOL] = {}
-- (a lamp of the game: untouched)
local LAMP = 'BlueprintGeneratedClass /Game/Griffin/Lighting/Blueprints/LightFixture/BP_CMN_LightFixture_Base.BP_CMN_LightFixture_Base_C'
MOCK.uobjects = MOCK.uobjects or {}
MOCK.uobjects[LAMP] = { name = LAMP }
local lamp = { ['Glow Intensity'] = 2, ['SM Glow Active'] = true, VolumetricScattering = 5, SM_Glow_Billboard = {} }
function lamp:get_address() return 'lamp1' end
MOCK.objectsOf[LAMP] = { lamp }
MOCK.commands = {}
race('L_Mastiff_LOOP_A', 'TRAK_MAS_LOOP_A_SHORT_02_HARD', 'TrackCondition.Sunset')
local fe = V.picPlace()
check('the track and weather read', fe, 'L_Mastiff_LOOP_A|Fallen Empire|forward|Sunset')
-- values a working build saved for options still being worked on, with one of 2.1.0's
V.veh.maps[fe] = { picShadow = 73, picMinEV = 10, picPair = 60, picPairLift = 120, picPairKeep = 100, picPairCap = 1, picTunnel = 100,
    picGlare = 50, picBlack = 40, picVib = 30, picTemp = 20, picUncap = 1, picLampCard = 0, picLampAir = 0, picFusion = 1 }
frames(5)
local p = V.pic
check('2.1.0\'s control used: floor 10 EV', p.minBright and string.format('%.3f', p.minBright), string.format('%.3f', 0.012 * 2 ^ 10))
check('  the ones being worked on not used', tostring(p.shadow)..tostring(p.glare)..tostring(p.gamma)..tostring(p.offset)..tostring(p.satHi)
    ..tostring(p.temp)..tostring(p.maxBright)..tostring(p.fusion)..tostring(p.capMax), 'nilnilnilnilnilnilnilnilnil')
check('  read as the game\'s own', V.picVal('picShadow')..'/'..V.picVal('picPair')..'/'..V.picVal('picLampAir'), '0/0/100')
check('  not counted as set', V.picOwn('picShadow'), nil)
local cam = MOCK.cm.CameraCachePrivate.POV.PostProcessSettings
check('  camera: no local exposure, curve, colour', tostring(cam.bOverride_LocalExposureShadowContrastScale)..tostring(cam.bOverride_LocalExposureHighlightContrastScale)
    ..tostring(cam.bOverride_ColorGamma)..tostring(cam.bOverride_ColorOffset)..tostring(cam.bOverride_WhiteTemp)..tostring(cam.bOverride_LocalExposureMethod)
    ..tostring(cam.bOverride_ColorCorrectionShadowsMax)..tostring(cam.bOverride_AutoExposureMaxBrightness), 'nilnilnilnilnilnilnilnil')
check('  camera: 2.1.0\'s floor written', cam.bOverride_AutoExposureMinBrightness, true)
local on = 0
for _, c in ipairs(MOCK.commands) do if c == 'r.LocalExposure 1' then on = on + 1 end end
check('  the renderer\'s local exposure not switched on', on, 0)
check('  the lamps untouched', tostring(lamp['Glow Intensity'])..'/'..tostring(lamp['SM Glow Active'])..'/'..tostring(lamp.VolumetricScattering), '2/true/5')
check('  the lamps not even looked for', asked[LAMP], nil)
check('the game\'s areas not read', asked[VOL], nil)
check('  no tunnel', V.picRoof(), nil)
-- the values kept in the file
V.setPicVal(fe, 'picExp', -0.5); frames(1)
local saved = file()[fe] or {}
check('kept in the file', string.format('%s %s %s %s %s', tostring(saved.picShadow), tostring(saved.picPair), tostring(saved.picLampAir),
    tostring(saved.picFusion), tostring(saved.picExp)), '73 60 0 1 -0.5')
check('2.1.0\'s brightness used', p.exp and string.format('%.2f', p.exp), '-0.50')
-- the menu: 2.1.0's controls, not the ones being worked on
MOCK.ui.labels, MOCK.ui.texts = {}, {}
MOCK.menu('idle')
local function drawn(en)
    local want = V.tr(en)
    for _, l in ipairs(MOCK.ui.labels) do if l:find(want, 1, true) then return true end end
    for _, l in ipairs(MOCK.ui.texts) do if l:find(want, 1, true) then return true end end
    return false
end
local shownLab, missingOld = {}, {}
for _, en in ipairs(@LAB@) do if drawn(en) then shownLab[#shownLab + 1] = en end end
for _, en in ipairs(@OLD@) do if not drawn(en) then missingOld[#missingOld + 1] = en end end
check('menu: none of the options being worked on', table.concat(shownLab, ', '), '')
check('menu: all of 2.1.0\'s', table.concat(missingOld, ', '), '')
local function texted(en)
    local want = V.tr(en)
    for _, l in ipairs(MOCK.ui.texts) do if l == want or l:find('^%s*'..want:gsub('%p', '%%%0')..'$') then return true end end
    return false
end
check('menu: the groups Light and Colour, no Lamps', tostring(texted('Light'))..tostring(texted('Colour'))..tostring(texted('Lamps')), 'truetruefalse')
local pub = V.wrap(V.tr('Saved for this track in this weather only (another weather, or the track reversed, has its own).')):match('^[^\n]*')
local hasPub = false
for _, l in ipairs(MOCK.ui.texts) do if l == '  '..pub then hasPub = true end end
check('menu: the public help', hasPub, true)
local tunnelWord = false
for _, l in ipairs(MOCK.ui.texts) do if l:find(V.tr('Now: in a tunnel (Tunnels on)'), 1, true) or l:find(V.tr('Now: not in a tunnel'), 1, true) then tunnelWord = true end end
check('menu: no tunnel lines', tunnelWord, false)
-- (every widget clicked and hovered once: the tooltips too)
MOCK.menu('click'); MOCK.menu('idle')
check('after the clicks: still nothing of them used', tostring(V.pic.shadow)..tostring(V.pic.gamma)..tostring(V.pic.fusion), 'nilnilnil')
note('menu labels drawn: '..#MOCK.ui.labels)
local miss = {}
for k in pairs(missing) do miss[#miss + 1] = k end
table.sort(miss)
for _, k in ipairs(miss) do note('no Korean: '..k) end
if V.LANG == 'ko' then note('Korean missing: '..#miss) end
'''.replace('@LAB@', lua_list(LAB_LABELS)).replace('@OLD@', lua_list(OLD_LABELS))


def main():
    bad = 0
    for script in sys.argv[1:3]:
        print('==', script)
        if 'PIC_LAB = false' not in open(script, encoding='utf-8').read():
            print('   FAIL not a public build (PIC_LAB = false missing)')
            bad += 1
            continue
        for title, files, body in (('public build', {}, PUBLIC), ('older values', P.OLD_FILE, P.OLD_VALUES)):
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
