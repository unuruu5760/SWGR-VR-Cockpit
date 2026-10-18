-- Fake UEVR / game environment for testing the package outside the game (LuaJIT).
-- Not a simulation of the game - just enough objects with the fields and methods the script uses,
-- so every code path can run: load, ticks with / without a vehicle, boosts, landings, the menu.
MOCK = { logs = {}, files = {}, cbs = {}, commands = {}, mods = { VR_WorldScale = '1.000000' }, errors = {} }
-- UEVR runs Lua 5.4: math.atan(y, x) takes two arguments; LuaJIT (5.1) would ignore the second
do
    local atan1, atan2 = math.atan, math.atan2
    math.atan = function(y, x) if x == nil then return atan1(y) end return atan2(y, x) end
end
local function addLog(s) MOCK.logs[#MOCK.logs + 1] = s end
local function cb(name) return function(fn) MOCK.cbs[name] = MOCK.cbs[name] or {}; table.insert(MOCK.cbs[name], fn) end end

-- strict objects: reading an unknown field is an error (catches typos in field / method names)
local function strict(name, t)
    return setmetatable(t, { __index = function(_, k) error('mock '..name..': no field "'..tostring(k)..'"', 2) end })
end
local function fname(s) return { to_string = function() return s end } end
local function vec(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end
local function quatT(x, y, z, w) return { X = x or 0, Y = y or 0, Z = z or 0, W = w or 1 } end

-- classes / structs
local function class(name)
    return strict('class '..name, {
        name = name,
        get_class_default_object = function(self) return MOCK.cdo end,
        -- (MOCK.noObjectList: UEVR's object list empty, as it was for the game's area boxes in the game)
        get_objects_matching = function(self) if MOCK.noObjectList then return {} end return (MOCK.objectsOf and MOCK.objectsOf[name]) or {} end,
        get_fname = function() return fname(name) end,
        find_function = function(self, fn) return MOCK.uobjects and MOCK.uobjects['Function '..name:gsub('^Class ', '')..':'..fn] end,
    })
end
MOCK.cdo = strict('CDO', {
    ComposeRotators = function(self, a, b) return { Pitch = a.Pitch + b.Pitch, Yaw = a.Yaw + b.Yaw, Roll = a.Roll + b.Roll } end,
    SetGlobalTimeDilation = function(self, ctx, x) MOCK.dilation = x end,
    GetGlobalTimeDilation = function(self, ctx) return MOCK.dilation or 1 end,
    GetTimeSeconds = function(self, ctx) return MOCK.gameTime or 0 end,
    GetLocalPlayerSubSystemFromPlayerController = function(self, pc, cls) return MOCK.inputSubsystem end,
    GetGameUserSettings = function(self) return { ControlScheme = MOCK.controlScheme or 0 } end,
    -- (the engine's list of the world's actors of a class: MOCK.objectsOf; MOCK.noActorList: it gives none)
    GetAllActorsOfClass = function(self, world, cls, out)
        assert(type(out) == 'table' and cls and cls.name, 'GetAllActorsOfClass arguments')
        if MOCK.noActorList then return end
        for _, o in ipairs((MOCK.objectsOf and MOCK.objectsOf[cls.name]) or {}) do out[#out + 1] = o end
    end,
    -- (the lines around the vehicle: all meet something when MOCK.roof is true, MOCK.roof(a, b) decides
    -- for a place only partly closed; MOCK.roofError: the call fails)
    LineTraceSingle = function(self, ctx, a, b, ch, complex, ignore, draw, hit, ignoreSelf, c1, c2, time)
        if MOCK.roofError then error('LineTraceSingle: bad argument') end
        assert(ctx == MOCK.pawn and type(ignore) == 'table' and ignoreSelf == true and b.Z > a.Z, 'bad roof trace')
        for _, x in ipairs({ a.X, a.Y, a.Z, b.X, b.Y, b.Z }) do assert(type(x) == 'number' and x == x, 'bad roof trace point') end
        MOCK.traces = (MOCK.traces or 0) + 1
        local met = MOCK.roof == true
        if type(MOCK.roof) == 'function' then met = MOCK.roof(a, b) == true end
        if met then hit.Distance = math.sqrt((b.X - a.X) ^ 2 + (b.Y - a.Y) ^ 2 + (b.Z - a.Z) ^ 2) / 2 end
        return met
    end,
})
-- Enhanced Input: the look back action injected = the game looks back this frame
MOCK.inputSubsystem = { name = 'EnhancedInputLocalPlayerSubsystem' }
MOCK.lookBackAction = { get_full_name = function() return 'InputAction /Game/Input/IA_LookBack.IA_LookBack' end }
MOCK.uobjects = {
    ['Function /Script/EnhancedInput.EnhancedInputSubsystemInterface:InjectInputVectorForAction'] = setmetatable({}, { __call = function(self, sub, action, value, mods, trigs)
        assert(sub == MOCK.inputSubsystem and action == MOCK.lookBackAction and value.X == 1 and type(mods) == 'table' and type(trigs) == 'table', 'bad injection')
        MOCK.injected = (MOCK.injected or 0) + 1
        if MOCK.lastVehicle then MOCK.lastVehicle.LookBackRequested = true; MOCK.injectReset = MOCK.lastVehicle end
    end }),
}
StructObject = { new = function(t) return { X = 0, Y = 0, Z = 0, W = 0, Pitch = 0, Yaw = 0, Roll = 0 } end }
Vector3f = { new = function(x, y, z) return { x = x, y = y, z = z } end }
Quaternionf = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }

-- the vehicle --------------------------------------------------------------------------------------
local function newComponent(cls, fields)
    fields.get_address = fields.get_address or function() return tostring(fields) end
    fields.get_fname = fields.get_fname or function() return fname(rawget(fields, '_name') or cls) end
    fields.get_outer = fields.get_outer or function() return rawget(fields, '_outer') end
    fields.is_a = fields.is_a or function(self, c) return true end
    fields._cls = cls
    return strict('component '..cls, fields)
end
function MOCK.copy(t)
    if type(t) ~= 'table' then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = MOCK.copy(v) end
    return c
end
MOCK.playerState = { get_address = function() return 'playerstate_local' end }
function MOCK.makeVehicle(kind, model, className)
    local podLayout, seatParent = MOCK.podLayout, nil   -- (a podracer: seat < pod mesh < free container)
    local v = strict('VehicleState', {
        Valid = true,
        VehicleTransform = { Translation = vec(1000, 2000, 300), Rotation = quatT(0, 0, 0, 1) },
        WorldFrameTransform = { Translation = vec(1000, 2000, 300), Rotation = quatT(0, 0, 0, 1) },
        Velocity = vec(0, 0, 0), SpeedMPH = 0, TopSpeedMph = 400, TimeInAir = 0, OnGroundScale = 1,
        RPMScale = 0, Throttle = 0, IgnitionStatus = 3, IgnitionPhase = 0, PerfectStartStrength = 0.5,
        AfterburnerState = 2, AfterburningTime = 0, AfterburnerEnergy = 1, RamjetState = 0, RamjetHeat = 0,
        EnergyBrakeState = 0, LookBackRequested = false, LandingState = 0, DraftingState = 0, Drifting = false, DriftScale = 0,
        IsWrecked = function() return false end, IsTumbling = function() return false end,
    })
    -- (its body: the part the seat is in, as in the game: landspeeder / skimmer rear, bike controls, podracer pod)
    local seatSlot = ({ Car = 'Rear', Skimmer = 'Rear', Bike = 'Controls', Plane = 'Root' })[kind] or 'Rear'
    local asset = { get_full_name = function() return '/Game/Griffin/Vehicles/'..kind..'s/Customisation/'..model..'/'..seatSlot..'/SM_'..model..'_Body' end,
                    Sockets = { { SocketName = 'PilotSeat' } } }
    local root = { get_full_name = function() return '/Game/Griffin/Vehicles/'..kind..'s/Customisation/'..kind..'/Root/SM_Root' end, Sockets = {} }
    local seatTf = { Rotation = quatT(0, 0, 0.7071, 0.7071), Translation = vec(10, 0, 40) }
    MOCK.seatTf = seatTf                   -- (the newest vehicle's seat: tests can shake it)
    local body = newComponent('StaticMeshComponent', { StaticMesh = asset, SkeletalMesh = false, GetSocketTransform = function(self, s, space) return seatTf end,
        GetAttachParent = function(self) return seatParent end })
    local rootMesh = newComponent('StaticMeshComponent', { StaticMesh = root, SkeletalMesh = false, GetSocketTransform = function() return seatTf end })
    local anim = newComponent('VehicleAnimationComponent', { SeatSocketName = 'PilotSeat' })
    local hidden = {}
    local pilot = newComponent('SkeletalMeshComponent', {
        _outer = anim, StaticMesh = false, SkeletalMesh = { get_full_name = function() return '/Game/Griffin/Characters/Pilot/SKM_Tomato02_Outfit_01' end },
        bHiddenInGame = false,
        GetBoneIndex = function(self, b) return 5 end, GetBoneName = function(self, i) return 'Head' end,
        IsBoneHiddenByName = function(self, b) return hidden[b] or false end,
        HideBoneByName = function(self, b, o) hidden[b] = true end, UnHideBoneByName = function(self, b) hidden[b] = false end,
        SetHiddenInGame = function(self, h, p) self.bHiddenInGame = h end,
        GetSocketLocation = function(self, b) return vec(15, 2, 90 + (MOCK.chestUp or 0)) end,
    })
    local custom = newComponent('SceneComponent', {
        _name = 'CustomisationRoot', RelativeLocation = vec(0, 0, 0), RelativeRotation = { Pitch = 0, Yaw = 0, Roll = 0 },
        -- (the game's recipe: which model each part slot comes from)
        ActiveRecipe = { RecipeName = model, UnitRecipes = { { UnitName = 'Main', Parts = { { PartType = seatSlot, vehicleKit = model, ParentIndex = -1 } } } } },
        GetAttachParent = function(self) return nil end,
        K2_GetComponentToWorld = function(self) return { Rotation = quatT(0, 0, 0, 1), Translation = vec(1000, 2000, 300) } end,
        K2_SetRelativeLocationAndRotation = function(self, l, r, sweep, hit, tele)
            for _, x in ipairs({ l.X, l.Y, l.Z, r.Pitch, r.Yaw, r.Roll }) do assert(type(x) == 'number' and x == x, 'bad body place') end
            self.RelativeLocation = vec(l.X, l.Y, l.Z); MOCK.carShakeCalls = (MOCK.carShakeCalls or 0) + 1
            self.RelativeRotation = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }
        end,
        K2_SetRelativeRotation = function(self, r, sweep, hit, tele)
            assert(type(r.Pitch) == 'number' and r.Pitch == r.Pitch, 'bad pitch')
            self.RelativeRotation = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }
            MOCK.tiltCalls = (MOCK.tiltCalls or 0) + 1
            MOCK.maxTilt = math.max(MOCK.maxTilt or 0, math.abs(r.Pitch))
        end,
        -- the vehicle stands level in the mock: world rotation = relative rotation
        K2_GetComponentRotation = function(self) local r = self.RelativeRotation; return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end,
    })
    MOCK.custom = custom
    -- the part the seat, the body and the pilot hang under (the game lifts it at the race start)
    local bodyRoot = newComponent('SceneComponent', {
        _name = 'VehicleBody', RelativeLocation = vec(0, 0, 0), RelativeRotation = { Pitch = 0, Yaw = 0, Roll = 0 },
        GetAttachParent = function(self) if podLayout then return nil end return custom end,
        K2_GetComponentToWorld = function(self) return { Rotation = quatT(0, 0, 0, 1), Translation = vec(1000, 2000, 300) } end,
        IsSimulatingPhysics = function(self) return false end,
        K2_SetRelativeLocationAndRotation = function(self, l, r, sweep, hit, tele)
            for _, x in ipairs({ l.X, l.Y, l.Z, r.Pitch, r.Yaw, r.Roll }) do assert(type(x) == 'number' and x == x, 'bad body place') end
            assert(tele == true, 'teleport')
            self.RelativeLocation = vec(l.X, l.Y, l.Z); self.RelativeRotation = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }
            MOCK.alongCalls = (MOCK.alongCalls or 0) + 1
        end,
    })
    MOCK.bodyRoot = bodyRoot
    -- podracer: the pod's own mesh between the seat and the free container
    MOCK.podMesh = nil
    seatParent = bodyRoot
    if podLayout then
        MOCK.podMesh = newComponent('SkeletalMeshComponent', {
            _name = 'SkeletalPart0_SKM_PodRoot', RelativeLocation = vec(0, 0, 0), RelativeRotation = { Pitch = 0, Yaw = 0, Roll = 0 },
            GetAttachParent = function(self) return bodyRoot end,
            IsSimulatingPhysics = function(self) return false end,
            K2_SetRelativeLocationAndRotation = function(self, l, r, sweep, hit, tele)
                for _, x in ipairs({ l.X, l.Y, l.Z, r.Pitch, r.Yaw, r.Roll }) do assert(type(x) == 'number' and x == x, 'bad pod place') end
                self.RelativeLocation = vec(l.X, l.Y, l.Z); self.RelativeRotation = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }
                MOCK.podCalls = (MOCK.podCalls or 0) + 1
                MOCK.podMax = math.max(MOCK.podMax or 0, math.abs(l.X), math.abs(l.Y), math.abs(l.Z))
            end,
        })
    end
    if MOCK.podMesh and podLayout then seatParent = MOCK.podMesh end
    local camComp = newComponent('VehicleCameraComponent', {
        OnChangeCamera = function() MOCK.cameraCycles = (MOCK.cameraCycles or 0) + 1 end,
        GetActiveStackName = function() return fname('Chase') end,
    })
    local byClass = {
        StaticMeshComponent = { rootMesh, body }, SkeletalMeshComponent = { pilot },
        VehicleAnimationComponent = { anim }, SceneComponent = { custom, bodyRoot, rootMesh, body },
        VehicleCameraComponent = { camComp },
    }
    local pawn = strict('pawn', {
        VehicleState = v, InputSource = 1, RootComponent = custom, CustomisationComponent = custom, PlayerState = MOCK.playerState, CstRootComponent = false,
        TuneComponent = { VehicleConfigData = { PlayerInputData = { Config = { LookBackAction = MOCK.lookBackAction } } } },
        GetGameTimeSinceCreation = function() return MOCK.clockT end,
        get_address = function() return 'pawn_'..model end,
        is_a = function(self, c) return true end,
        get_class = function() return { get_fname = function() return fname(className or ('VBP_'..kind..'_C')) end } end,
        K2_GetComponentsByClass = function(self, c)
            local short = c.name:match('%.([%w_]+)$') or c.name
            return byClass[short] or {}
        end,
    })
    MOCK.lastVehicle = v
    return pawn, v
end

-- camera manager / controller ------------------------------------------------------------------------
local function pov() return { Location = vec(0, 0, 0), Rotation = { Pitch = 0, Yaw = 0, Roll = 0 },
    PostProcessSettings = { ColorSaturation = { X = 1, Y = 1, Z = 1, W = 1 }, ColorContrast = { X = 1, Y = 1, Z = 1, W = 1 },
                            SceneColorTint = { R = 1, G = 1, B = 1, A = 1 }, ColorGainHighlights = { X = 1, Y = 1, Z = 1, W = 1 },
                            AutoExposureBias = 0, BloomIntensity = 0.675, AutoExposureLowPercent = 10,
                            AutoExposureHighPercent = 90, AutoExposureMinBrightness = -10,
                            LocalExposureHighlightContrastScale = 1, LocalExposureShadowContrastScale = 1,
                            ColorOffset = { X = 0, Y = 0, Z = 0, W = 0 }, ColorSaturationHighlights = { X = 1, Y = 1, Z = 1, W = 1 },
                            ColorSaturationMidtones = { X = 1, Y = 1, Z = 1, W = 1 }, ColorSaturationShadows = { X = 1, Y = 1, Z = 1, W = 1 },
                            WhiteTemp = 6500, AutoExposureMaxBrightness = 20, ColorGamma = { X = 1, Y = 1, Z = 1, W = 1 },
                            ColorGammaShadows = { X = 1, Y = 1, Z = 1, W = 1 }, ColorGainShadows = { X = 1, Y = 1, Z = 1, W = 1 },
                            ColorCorrectionShadowsMax = 0.09, LocalExposureMethod = 0 }, PostProcessBlendWeight = 1 } end
MOCK.viewTargetClass = 'VBP_Bike_C'
MOCK.cm = { ViewTarget = { POV = pov(), Target = nil }, CameraCachePrivate = { POV = pov() } }
MOCK.cm.ViewTarget.Target = {
    get_class = function() return { get_fname = function() return fname(MOCK.viewTargetClass) end } end,
    get_fname = function() return fname(MOCK.viewTargetClass..'_1') end,
    get_outer = function() return { get_outer = function() return { get_fname = function() return fname('L_Test') end } end } end,
}
MOCK.pc = strict('pc', { PlayerCameraManager = MOCK.cm, IsPaused = function() return MOCK.paused or false end })

-- uevr ---------------------------------------------------------------------------------------------
local classes = {}
uevr = {
    api = strict('api', {
        find_uobject = function(self, name)
            if MOCK.uobjects and MOCK.uobjects[name] then return MOCK.uobjects[name] end
            if MOCK.noAreaClass and name:find('SweejAmbience', 1, true) then return nil end
            if name:find('^Class ') or name:find('^ScriptStruct ') then
                classes[name] = classes[name] or class(name)
                return classes[name]
            end
            return nil
        end,
        get_local_pawn = function(self, i) return MOCK.pawn end,
        get_player_controller = function(self, i) return MOCK.pc end,
        execute_command = function(self, c) MOCK.commands[#MOCK.commands + 1] = c end,
        get_engine = function(self) return { NearClipPlane = 10, GameViewport = { World = { get_fname = function() return fname(MOCK.world or 'L_Test_LOOP_A') end,
            -- (the race's recipe: its track; the game's name is a text object)
            -- (the race's recipe per racer: MOCK.racers = { { Player = MOCK.playerState, VehicleCustomisation = recipe } })
            GameState = { EventRecipeState_Replication = { ActiveStage = 0, Racers = MOCK.racers or {} },
                -- (the race's view model: its track and planet; the game's names are text objects)
                -- (MOCK.trackDef false: no track yet)
                RaceEventViewModel = { track = MOCK.trackDef ~= false and { get_fname = function() return fname(MOCK.trackDef or 'TRAK_MAS_LOOP_A_SHORT_02_HARD') end,
                        get_class = function() return { get_fname = function() return fname('TrackDef') end } end } or nil,
                    Planet = { get_fname = function() return fname('PLA_Mastiff') end },
                    -- (MOCK.condition false: the weather can't be read)
                    trackConditions = MOCK.condition ~= false and { TagName = fname(MOCK.condition or 'TrackCondition.Sunset') } or nil } } } } } end,
        get_console_manager = function(self) return { find_variable = function(_, n) return { get_int = function() return 0 end } end } end,
    }),
    sdk = { callbacks = strict('callbacks', {
        on_pre_engine_tick = cb('tick'), on_post_engine_tick = cb('posttick'),
        on_pre_calculate_stereo_view_offset = cb('stereo'), on_post_calculate_stereo_view_offset = cb('poststereo'),
        on_pre_viewport_client_draw = cb('draw'), on_draw_ui = cb('ui'), on_frame = cb('frame'),
        on_script_reset = cb('reset'), on_xinput_get_state = cb('xinput'), on_lua_event = cb('luaevent'),
    }) },
    params = {
        functions = { log_info = function(s) addLog(s) end },
        vr = strict('vr', {
            get_mod_value = function(self, k) return MOCK.mods[k] or '0' end,
            set_mod_value = function(k, v) MOCK.mods[k] = v end,
            get_pose = function(i, p, q) end, get_hmd_index = function() return 0 end,
            set_standing_origin = function(p) end, recenter_view = function() MOCK.recenters = (MOCK.recenters or 0) + 1 end,
        }),
    },
}
json = {
    -- (like the real one: a file is read into new tables and written as a copy, never shared)
    load_file = function(name) return MOCK.copy(MOCK.files[name]) end,
    dump_file = function(name, t) MOCK.files[name] = MOCK.copy(t); MOCK.saves = (MOCK.saves or 0) + 1 end,
}

-- imgui: 'mode' decides what the widgets return (nothing / click everything)
MOCK.ui = { mode = 'idle', texts = {}, labels = {}, scopes = { {} }, dups = {} }
-- every widget label must be unique inside its tree (ImGui IDs come from the label)
local function lbl(l)
    assert(type(l) == 'string', 'imgui label must be a string, got '..type(l))
    MOCK.ui.labels[#MOCK.ui.labels + 1] = l
    local scope = MOCK.ui.scopes[#MOCK.ui.scopes]
    local id = l:match('###(.*)$') or l
    if scope[id] then MOCK.ui.dups[#MOCK.ui.dups + 1] = id end
    scope[id] = true
end
imgui = strict('imgui', {
    tree_node = function(l) lbl(l); MOCK.ui.scopes[#MOCK.ui.scopes + 1] = {}; return true end,
    tree_pop = function() assert(#MOCK.ui.scopes > 1, 'tree_pop without tree_node'); MOCK.ui.scopes[#MOCK.ui.scopes] = nil end,
    text = function(s) assert(type(s) == 'string', 'imgui.text needs a string'); assert(not s:find('%', 1, true), 'no % in imgui.text: '..s); MOCK.ui.texts[#MOCK.ui.texts + 1] = s end,
    separator = function() end, same_line = function() end, spacing = function() end,
    indent = function() MOCK.indentStack = (MOCK.indentStack or 0) + 1 end, unindent = function() MOCK.indentStack = (MOCK.indentStack or 0) - 1 end,
    button = function(l) lbl(l); return MOCK.ui.mode == 'click' end,
    arrow_button = function(id, dir) lbl(id); assert(type(dir) == 'number', 'arrow_button direction'); return MOCK.ui.mode == 'click' end,
    invisible_button = function(id, size) lbl(id); assert(type(size) == 'table' and #size == 2, 'invisible_button size {w, h}'); return false end,
    checkbox = function(l, v) lbl(l); assert(type(v) == 'boolean', 'checkbox value must be boolean ('..l..')')
        if MOCK.ui.mode == 'click' then return true, not v end; return false, v end,
    slider_float = function(l, v, lo, hi, fmt)
        lbl(l); assert(type(v) == 'number', 'slider value must be a number ('..l..')')
        assert(type(lo) == 'number' and type(hi) == 'number', 'slider range ('..l..')')
        if MOCK.ui.mode == 'click' then return true, (lo + hi) / 2 end; return false, v end,
    combo = function(l, idx, items)
        lbl(l); assert(type(idx) == 'number' and type(items) == 'table', 'combo args ('..l..')')
        for _, it in ipairs(items) do assert(type(it) == 'string', 'combo items must be strings ('..l..')') end
        if MOCK.ui.mode == 'click' then return true, #items end; return false, idx end,
    is_item_hovered = function() return MOCK.ui.mode == 'click' end,
    calc_text_size = function(t) assert(type(t) == 'string', 'calc_text_size needs a string'); return { x = #t * 7, y = 14 } end,
    get_window_size = function() return { x = MOCK.winW or 560, y = 800 } end,
    get_cursor_pos = function() return { x = 24, y = 0 } end,
    text_colored = function(s, c) assert(type(s) == 'string' and type(c) == 'number'); assert(not s:find('%', 1, true), 'no % in imgui.text: '..s); MOCK.ui.texts[#MOCK.ui.texts + 1] = s end,
    push_style_color = function(i, c) assert(type(i) == 'number' and type(c) == 'number' and c >= -2147483648 and c <= 2147483647, 'push_style_color takes an int'); MOCK.colorStack = (MOCK.colorStack or 0) + 1 end,
    pop_style_color = function(n) MOCK.colorStack = (MOCK.colorStack or 0) - (n or 1) end,
    set_tooltip = function(s) assert(type(s) == 'string', 'tooltip must be a string'); assert(not s:find('%', 1, true), 'no % in tooltips: '..s); MOCK.tips = (MOCK.tips or 0) + 1 end,
    push_font = function(f) end, pop_font = function() end,
    load_font = function(name, size, ranges) return 'font:'..name end,
    is_key_down = function(k) return MOCK.keyDown == k end,
    ImGuiKey = setmetatable({}, { __index = function(_, k) return k end }),
})

-- item width API: which of the optional functions this fake UEVR has ('next' / 'push' / 'none')
MOCK.widthStack = 0
function MOCK.setWidthApi(mode)
    if mode == 'next' then
        rawset(imgui, 'set_next_item_width', function(w) assert(type(w) == 'number') end)
        rawset(imgui, 'begin_disabled', function(d) MOCK.disabledStack = (MOCK.disabledStack or 0) + 1 end)
        rawset(imgui, 'end_disabled', function() MOCK.disabledStack = (MOCK.disabledStack or 0) - 1 end)
    elseif mode == 'push' then
        rawset(imgui, 'push_item_width', function(w) assert(type(w) == 'number'); MOCK.widthStack = MOCK.widthStack + 1 end)
        rawset(imgui, 'pop_item_width', function() MOCK.widthStack = MOCK.widthStack - 1 end)
    end
end

-- drivers ------------------------------------------------------------------------------------------
function MOCK.fire(name, ...)
    for _, fn in ipairs(MOCK.cbs[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then MOCK.errors[#MOCK.errors + 1] = name..': '..tostring(err) end
    end
end
-- one game frame: tick, draw, both eyes
-- os.clock follows the simulated frames (real-time smoothing in the script behaves like in game)
MOCK.clockT = 0
os.clock = function() return MOCK.clockT end
function MOCK.frame(dt)
    -- (an injected look back lasts one frame)
    if MOCK.injectReset then MOCK.injectReset.LookBackRequested = false; MOCK.injectReset = nil end
    MOCK.clockT = MOCK.clockT + dt
    MOCK.gameTime = (MOCK.gameTime or 0) + (MOCK.paused and 0 or dt)
    -- the driven vehicle moves with its velocity while the game runs (a moving car that doesn't move
    -- looks like the pause menu to the script and its effects switch off)
    local mv = MOCK.lastVehicle
    if mv and not MOCK.paused and MOCK.pawn then
        local t, vel = mv.VehicleTransform.Translation, mv.Velocity
        t.X, t.Y, t.Z = t.X + (vel.X or 0) * dt, t.Y + (vel.Y or 0) * dt, t.Z + (vel.Z or 0) * dt
    end
    MOCK.fire('tick', nil, dt)
    MOCK.fire('frame')
    MOCK.fire('draw')
    for view = 0, 1 do
        local pos, rot = { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }
        MOCK.fire('stereo', nil, view, 1, pos, rot)
        for _, val in ipairs({ pos.x, pos.y, pos.z, rot.x, rot.y, rot.z }) do
            if val ~= val or math.abs(val) > 1e7 then MOCK.errors[#MOCK.errors + 1] = 'bad view value '..tostring(val) end
        end
        MOCK.lastPos, MOCK.lastRot = pos, rot
    end
end
function MOCK.menu(mode)
    MOCK.ui.mode = mode or 'idle'
    MOCK.ui.scopes = { {} }
    MOCK.fire('ui')
    if (MOCK.disabledStack or 0) ~= 0 then MOCK.errors[#MOCK.errors + 1] = 'menu: begin/end_disabled not balanced' end
    if MOCK.widthStack ~= 0 then MOCK.errors[#MOCK.errors + 1] = 'menu: push/pop_item_width not balanced' end
    if (MOCK.colorStack or 0) ~= 0 then MOCK.errors[#MOCK.errors + 1] = 'menu: push/pop_style_color not balanced' end
    if (MOCK.indentStack or 0) ~= 0 then MOCK.errors[#MOCK.errors + 1] = 'menu: indent / unindent not balanced' end
    if #MOCK.ui.scopes ~= 1 then MOCK.errors[#MOCK.errors + 1] = 'menu: tree_node / tree_pop not balanced ('..#MOCK.ui.scopes..')' end
    for _, d in ipairs(MOCK.ui.dups) do MOCK.errors[#MOCK.errors + 1] = 'menu: duplicate widget id "'..d..'"' end
    MOCK.ui.dups = {}
    MOCK.ui.mode = 'idle'
end
