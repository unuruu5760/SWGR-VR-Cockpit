-- Boost screen effects: stronger colours, darker edges and a short flash while the afterburner /
-- ramjet burns, written into the game camera's post-process right before each frame is drawn
-- (the game rebuilds it every frame, so nothing needs undoing). Menu: one amount in %.
local log = V.logger('screen')
V.tunable('boost', 'satAB', 0.12, 0, 3, 'Colours: afterburner', 'How much stronger the colours get while the afterburner burns. 0 = colours stay the same.')
V.tunable('boost', 'satRJ', 0.4, 0, 3, 'Colours: ramjet', 'How much stronger the colours get while the ramjet burns. 0 = colours stay the same.')
V.tunable('boost', 'vigAB', 0.94, 0, 3, 'Dark edges: afterburner', 'How much the screen edges darken while the afterburner burns (tunnel vision). 0 = edges stay normal.')
V.tunable('boost', 'vigRJ', 0.97, 0, 3, 'Dark edges: ramjet', 'How much the screen edges darken while the ramjet burns (tunnel vision). 0 = edges stay normal.')
V.tunable('boost', 'flashAB', 0.94, 0, 3, 'Flash: afterburner', 'A short flash of the screen at the moment the afterburner fires. 0 = no flash.')
V.tunable('boost', 'flashRJ', 2, 0, 3, 'Flash: ramjet', 'A short flash of the screen at the moment the ramjet ignites. 0 = no flash.')
V.tunable('boost', 'fadeOut', 1.2, 0.2, 3, 'Colours fade back (s)', 'After a boost, how long the colours and edges take to return to normal (seconds). Longer = slower, smoother.')
local AB_ACTIVE, RJ_ACTIVE, RJ_GRACE = 0, 3, 5
local AB_MIN_HOLD, AB_REPEAT = 0.12, 1.0          -- same rule as the afterburner lunge (no flicker on taps)

local now = { vig = 0, sat = 0, tint = false, r = 1, g = 1, b = 1, vigOn = false }
local fusionTold = false
local function writeSettings(s, v)
    -- the vignette stays overridden (0 when idle) while the renderer switch is on, because the
    -- switch also lets the game's own vignette through
    s.bOverride_VignetteIntensity = v.vigOn or v.vig > 0.001
    s.VignetteIntensity = v.vig
    -- (the VR picture test, 65_picture: its saturation / contrast multiply the boost's; untouched = 1)
    local pic = V.pic and V.pic.active and V.pic or nil
    local pSat, pCon = pic and pic.sat or 1, pic and pic.con or 1
    s.bOverride_ColorSaturation = v.sat > 0.001 or math.abs(pSat - 1) > 0.001
    local cs = s.ColorSaturation; cs.X, cs.Y, cs.Z, cs.W = 1, 1, 1, (1 + v.sat) * pSat; s.ColorSaturation = cs
    s.bOverride_ColorContrast = v.sat > 0.001 or math.abs(pCon - 1) > 0.001
    local cc = s.ColorContrast; cc.X, cc.Y, cc.Z, cc.W = 1, 1, 1, (1 + v.sat * 0.4) * pCon; s.ColorContrast = cc
    s.bOverride_SceneColorTint = v.tint and true or false
    local tc = s.SceneColorTint; tc.R, tc.G, tc.B, tc.A = v.r, v.g, v.b, 1; s.SceneColorTint = tc
    if pic then
        if pic.exp then s.bOverride_AutoExposureBias = true; s.AutoExposureBias = pic.exp end
        if pic.bloom then s.bOverride_BloomIntensity = true; s.BloomIntensity = pic.bloom end
        if pic.low then
            s.bOverride_AutoExposureLowPercent = true; s.AutoExposureLowPercent = pic.low
            -- (the high end must stay above it)
            s.bOverride_AutoExposureHighPercent = true; s.AutoExposureHighPercent = pic.high or math.min(100, math.max(90, pic.low + 1.5))
        end
        if pic.minBright then s.bOverride_AutoExposureMinBrightness = true; s.AutoExposureMinBrightness = pic.minBright end
        if pic.maxBright then s.bOverride_AutoExposureMaxBrightness = true; s.AutoExposureMaxBrightness = pic.maxBright end
        if pic.glare then s.bOverride_LocalExposureHighlightContrastScale = true; s.LocalExposureHighlightContrastScale = pic.glare end
        if pic.offset then
            s.bOverride_ColorOffset = true
            local o = s.ColorOffset; o.X, o.Y, o.Z, o.W = 0, 0, 0, pic.offset; s.ColorOffset = o
        end
        if pic.satHi then
            s.bOverride_ColorSaturationHighlights, s.bOverride_ColorSaturationMidtones, s.bOverride_ColorSaturationShadows = true, true, true
            local h = s.ColorSaturationHighlights; h.X, h.Y, h.Z, h.W = 1, 1, 1, pic.satHi; s.ColorSaturationHighlights = h
            local m = s.ColorSaturationMidtones; m.X, m.Y, m.Z, m.W = 1, 1, 1, pic.satMid; s.ColorSaturationMidtones = m
            local l = s.ColorSaturationShadows; l.X, l.Y, l.Z, l.W = 1, 1, 1, pic.satLo; s.ColorSaturationShadows = l
        end
        if pic.temp then s.bOverride_WhiteTemp = true; s.WhiteTemp = pic.temp end
        if pic.shadow then s.bOverride_LocalExposureShadowContrastScale = true; s.LocalExposureShadowContrastScale = pic.shadow end
        if pic.fusion then
            local ok, back = pcall(function()
                s.bOverride_LocalExposureMethod = true; s.LocalExposureMethod = 1
                return s.LocalExposureMethod
            end)
            if not fusionTold then
                fusionTold = true
                log('local exposure method Fusion: '..(ok and ('written, reads back '..tostring(back)) or ('could not be written: '..tostring(back))))
            end
        end
        if pic.gamma then
            s.bOverride_ColorGamma = true
            local g = s.ColorGamma; g.X, g.Y, g.Z, g.W = 1, 1, 1, pic.gamma; s.ColorGamma = g
            if pic.capMax then
                s.bOverride_ColorCorrectionShadowsMax = true; s.ColorCorrectionShadowsMax = pic.capMax
                s.bOverride_ColorGammaShadows = true
                local gs = s.ColorGammaShadows; gs.X, gs.Y, gs.Z, gs.W = 1, 1, 1, 1 / pic.gamma; s.ColorGammaShadows = gs
                s.bOverride_ColorGainShadows = true
                local gn = s.ColorGainShadows; gn.X, gn.Y, gn.Z, gn.W = 1, 1, 1, pic.capGain; s.ColorGainShadows = gn
            end
        end
        if math.abs((pic.hi or 1) - 1) > 0.001 then
            s.bOverride_ColorGainHighlights = true
            local g = s.ColorGainHighlights; g.X, g.Y, g.Z, g.W = 1, 1, 1, pic.hi; s.ColorGainHighlights = g
        end
    end
end
local function writeCamera()
    local v = now
    if not (v.vigOn or v.vig > 0.001 or v.sat > 0.001 or v.tint or (V.pic and V.pic.active)) then return end
    local pc = api:get_player_controller(0)
    local cm = pc and pc.PlayerCameraManager
    if not cm then return end
    for _, which in ipairs({ 'CameraCachePrivate', 'ViewTarget' }) do
        pcall(function()
            local holder = cm[which]
            local pov = holder.POV
            local s = pov.PostProcessSettings
            writeSettings(s, v)
            -- nested structs are references; the assignments back are a fallback for copies
            pcall(function() pov.PostProcessSettings = s end)
            pcall(function() if (tonumber(pov.PostProcessBlendWeight) or 0) < 1 then pov.PostProcessBlendWeight = 1 end end)
            pcall(function() holder.POV = pov end)
            pcall(function() cm[which] = holder end)
        end)
    end
end
callbacks.on_pre_viewport_client_draw(function() pcall(writeCamera) end)

-- The VR user_script / Low post-process quality turn the vignette off in the renderer
-- (r.Tonemapper.Quality < 2). It is switched on only while a boost shows it and put back 2 s after
-- (the switch also changes contrast a little, so it must not stay on).
local function readCvar(name, fallback)
    local ok, val = pcall(function()
        local var = api:get_console_manager():find_variable(name)
        return var and var:get_int()
    end)
    return (ok and tonumber(val)) or fallback
end
local origTonemapper = readCvar('r.Tonemapper.Quality', 0)
if origTonemapper == 2 then origTonemapper = 0 end   -- an older version left it changed
local vigBoosted = true                               -- forces one restore at load
local function setVigCvar(on)
    if vigBoosted == on then return end
    vigBoosted = on
    local cmd = 'r.Tonemapper.Quality '..(on and 2 or origTonemapper)
    local ok, err = pcall(function() api:execute_command(cmd) end)
    if not ok then log('command failed: '..cmd..' : '..tostring(err)) end
end
setVigCvar(false)

local st = { abEnv = 0, rjEnv = 0, abFlash = 0, rjFlash = 0, abBurnT = 0, lastABFlash = -10, vigOffT = 0, prevRJ = -1 }
V.onTick('screen', function(dt)
    if dt <= 0 then return end
    dt = math.min(dt, 0.05)
    local p, v = V.pawnAndVehicle()
    local amount = V.cfg.extras and (tonumber(V.cfg.screen) or 0) / 100 or 0
    local playing = v ~= nil and amount > 0 and V.cam.enabled
    if playing then
        local okS, src = pcall(function() return tonumber(p.InputSource) end)
        if okS and src == 2 then playing = false end                  -- AI drives (race finished)
        local okP, paused = pcall(function() return api:get_player_controller(0):IsPaused() end)
        if okP and paused then playing = false end
    end
    local ab, rj = -1, -1
    if playing then
        ab = tonumber(v.AfterburnerState) or -1
        rj = tonumber(v.RamjetState) or -1
        if rj == RJ_ACTIVE and st.prevRJ ~= -1 and st.prevRJ < RJ_ACTIVE then st.rjFlash = 1 end
    end
    st.prevRJ = rj
    local burning = playing and ab == AB_ACTIVE and (tonumber(v.AfterburningTime) or 0) > 0
    local wasHeld = st.abBurnT >= AB_MIN_HOLD
    st.abBurnT = burning and (st.abBurnT + dt) or 0
    local abOn = st.abBurnT >= AB_MIN_HOLD
    if abOn and not wasHeld and V.t - st.lastABFlash > AB_REPEAT then st.abFlash = 1; st.lastABFlash = V.t end
    local rjOn = playing and rj >= RJ_ACTIVE and rj <= RJ_GRACE
    -- in quickly, out slowly: no pop when it ends
    local fadeOut = math.max(0.1, V.val('fadeOut'))
    st.abEnv = V.approach(st.abEnv, abOn and 1 or 0, dt, 0.15, fadeOut)
    st.rjEnv = V.approach(st.rjEnv, rjOn and 1 or 0, dt, 0.1, fadeOut * 1.3)
    st.abFlash = st.abFlash * math.exp(-dt / 0.3)
    st.rjFlash = st.rjFlash * math.exp(-dt / 0.45)
    if not playing then st.abFlash, st.rjFlash = 0, 0 end
    local A = amount
    now.vig = math.min(1.5, 0.6 * (st.abEnv * V.val('vigAB') + st.rjEnv * V.val('vigRJ')) * A)
    now.sat = math.min(1.5, (0.15 * st.abEnv * V.val('satAB') + 0.35 * st.rjEnv * V.val('satRJ')) * A)
    local f = math.min(3, (0.5 * st.abFlash * V.val('flashAB') + 1.2 * st.rjFlash * V.val('flashRJ')) * A)
    now.r, now.g, now.b = 1 + 0.6 * f, 1 + 0.75 * f, 1 + 1.0 * f
    now.tint = f > 0.002
    if now.vig > 0.01 then setVigCvar(true); st.vigOffT = 0
    elseif now.vig < 0.005 then st.vigOffT = st.vigOffT + dt; if st.vigOffT > 2 then setVigCvar(false) end end
    now.vigOn = vigBoosted
end)
V.onReset(function() setVigCvar(false) end)
