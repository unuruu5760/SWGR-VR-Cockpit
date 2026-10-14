-- Banking: bikes / plane-like vehicles bank hard in turns (up to ~90 degrees drifting). Only the
-- view roll is changed, with a soft maximum: view roll = % * MAX * tanh(roll * amount / MAX).
-- Menu: "Banking" % right in the View menu, saved per vehicle. 100 = the lean set by the two values
-- below, 50 = half of that everywhere, 0 = always level.
V.tunable('view', 'rollAmount', 0.65, 0, 1.5, 'Banking amount (at Banking 100)',
    'How much of the vehicle\'s lean the view follows in normal turns when "Banking" is 100. 1 = exactly as much as the vehicle.')
V.tunable('view', 'rollMax', 50.92, 5, 90, 'Banking maximum (degrees, at Banking 100)',
    'When "Banking" is 100 the view never leans more than this, however hard the vehicle banks (soft limit).')
-- older data had other recommended values: drop the old shared ones, and a vehicle's own ones that
-- equal the new defaults, so "Banking 100" means the new defaults everywhere
if V.migrating then
    for _, key in ipairs({ 'rollAmount', 'rollMax' }) do
        V.cfg.detail[key] = nil
        local base = V.TUNE_INDEX[key].base
        for m, vd in pairs(V.veh.detail) do
            local v = type(vd) == 'table' and tonumber(vd[key])
            if v and math.abs(v - base) < 0.01 then V.clearOwnVal('detail', m, key) end
        end
    end
    V.save()
end

local function tanh(x)
    if x > 20 then return 1 elseif x < -20 then return -1 end
    local e = math.exp(2 * x)
    return (e - 1) / (e + 1)
end
V.hooks.roll = function(view, position, rotation)
    if not V.cfg.extras then return end
    local k = V.pctFor(V.model, 'roll') / 100
    local amount = V.val('rollAmount')
    local maxRoll = math.max(1, V.val('rollMax'))
    local roll = ((rotation.z + 180) % 360) - 180
    rotation.z = k * maxRoll * tanh(roll * amount / maxRoll)
end
