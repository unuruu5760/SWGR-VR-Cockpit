-- Near clip: don't draw what is right at the eye. The pilot body is one mesh with the hands, so it
-- can't be hidden while keeping the hands; when the body comes into the eye (landing press, bike
-- jumps) the near plane is pushed out so its inside is cut away while the hands / handlebars stay.
-- Only while the cockpit places the view; the engine's own value is restored otherwise.
local log = V.logger('nearclip')
local S = V.cam
local MIN_NEAR = 3.0
-- the cut distance: set in the View menu for the vehicle driven (untouched = the shared value)
V.tunable('view', 'near', 10.0, 3, 30, 'Cut distance (cm)', '안 그리는 거리 (cm)',
    'Nothing closer to your eyes than this is drawn, so you don\'t see the inside of the pilot body. Dashboard or hands cut away: lower it. Inside of the body visible: raise it.',
    '눈에서 이 거리보다 가까운 건 안 그려서 조종사 몸통 안쪽이 안 보여요. 계기판이나 손이 잘려 보이면 낮추고, 몸통 안쪽이 보이면 올리세요.').main = true
V.tunable('view', 'nearLow', 5.0, 0, 20, 'Landing: extra cut (cm)', '착지 때 더 안 그리기 (cm)', 'Only while a landing presses the view down: this much is added to the "Cut distance", so even more right in front of your eyes is not drawn (hides the inside of the pilot body). Inside of the body visible on landings: raise it. Dashboard / hands vanish for a moment on landings: lower it. 0 = no extra cut.', '착지로 시점이 아래로 눌릴 때만, "안 그리는 거리"에 이만큼 더해서 눈앞을 더 넓게 안 그려요 (몸통 안쪽이 안 보이게). 착지 순간 몸통 안쪽이 보이면 올리고, 계기판·손이 잠깐 사라지면 내리세요. 0 = 착지 때도 더 안 자름.')
-- older data had one shared value per vehicle type. A vehicle's own type value becomes its own
-- value; a type value the user had changed (more than 1 cm from the new shared default) is kept for
-- the saved vehicles of that type; everything else follows the shared value.
if V.vehFormat < 3 then
    local base = V.TUNE_INDEX.near.base
    local saved = {}
    for _, tbl in ipairs({ V.veh.eyes, V.veh.feel, V.veh.detail }) do
        for m in pairs(tbl) do saved[m] = true end
    end
    for _, ty in ipairs(V.TYPES) do
        local key = 'near'..ty
        local typeVal = tonumber(V.cfg.detail[key])
        V.cfg.detail[key] = nil
        for m in pairs(saved) do
            if m:sub(1, #ty + 1) == ty..'/' and not V.ownVal('detail', m, 'near') then
                local own = V.ownVal('detail', m, key)
                if own then
                    V.setOwnVal('detail', m, 'near', own)
                elseif typeVal and math.abs(typeVal - base) > 1 then
                    V.setOwnVal('detail', m, 'near', typeVal)
                end
            end
            V.clearOwnVal('detail', m, key)
        end
    end
    V.save(); V.saveVeh()
end

local function command(c)
    local ok, err = pcall(function() api:execute_command(c) end)
    if not ok then log('command failed: '..c..' : '..tostring(err)) end
end
local origNear = 10.0
do
    local ok, v = pcall(function() return api:get_engine().NearClipPlane end)
    if ok and tonumber(v) and tonumber(v) > 0 then origNear = tonumber(v) end
end
local active, lastSet = false, nil
local function restore()
    if not active then return end
    command(string.format('r.SetNearClipPlane %.2f', origNear))
    active, lastSet = false, nil
end
local function cockpitPlacing()
    return S.enabled and S.anchor ~= nil and not S.yielding()
end
V.onTick('nearclip', function()
    if not V.cfg.extras or not V.cfg.nearClip or not cockpitPlacing() then restore(); return end
    local down = tonumber(V.feelDown) or 0
    -- forward lunges move the eye toward the dashboard: pull the plane back by the same amount
    local fwd = math.max(0, tonumber(V.feelFwd) or 0)
    local want = math.max(MIN_NEAR, V.val('near') + (down > 2 and V.val('nearLow') or 0) - fwd)
    want = math.floor(want * 2 + 0.5) / 2               -- 0.5 cm steps: only send real changes
    active = true
    if want ~= lastSet then
        command(string.format('r.SetNearClipPlane %.2f', want))
        lastSet = want
    end
end)
V.onReset(restore)
