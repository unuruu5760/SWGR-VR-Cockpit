-- Banking: bikes / plane-like vehicles bank hard in turns (up to ~90 degrees drifting). Only the
-- view roll is changed, with a soft maximum: view roll = % * MAX * tanh(roll * amount / MAX).
-- Menu: "Banking" % right in the View menu, saved per vehicle. 100 = the lean set by the two values
-- below, 50 = half of that everywhere, 0 = always level.
local log = V.logger('roll')
V.tunable('view', 'rollAmount', 0.65, 0, 1.5, 'Banking amount (at Banking 100)',
    'How much of the vehicle\'s lean the view follows in normal turns when "Banking" is 100. 1 = exactly as much as the vehicle. Our recommended values are 0.65 here and 50.92 for the maximum. The lean the game itself designed (as in the original cockpit script) is Banking 200, maximum 90 and amount 0.55; for more than that, raise the amount.')
V.tunable('view', 'rollMax', 50.92, 5, 90, 'Banking maximum (degrees, at Banking 100)',
    'When "Banking" is 100 the view never leans more than this, however hard the vehicle banks (soft limit). The lean the game itself designed (as in the original cockpit script) is Banking 200, maximum 90 and amount 0.55; raise the amount for more.')
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

-- "Exactly like the vehicle" (the pilot follow mode) gets the game's own lean: Banking 200, maximum 90,
-- amount 0.55 (about the original cockpit script, which follows the vehicle 1:1: the same up to ~60
-- degrees, a little less beyond). The other modes keep the recommended banking. The shared values
-- swap when the mode group changes, so what was set in each group is kept. Banking set for a vehicle
-- (while driving it) is that vehicle's own and stays, in every mode: it is never overwritten here.
function V.syncBankingMode(lock)
    local want = lock == 'pilot' and 'Pilot' or 'Other'
    local cur = V.cfg.bankMode == 'pilot' and 'Pilot' or 'Other'
    if want == cur then return false end
    V.cfg['bank'..cur..'Roll'] = V.sharedPct('roll')
    V.cfg['bank'..cur..'Max'] = V.sharedVal('rollMax')
    V.cfg['bank'..cur..'Amount'] = V.sharedVal('rollAmount')
    V.cfg.roll = V.cfg['bank'..want..'Roll']
    V.cfg.detail.rollMax = V.cfg['bank'..want..'Max']
    V.cfg.detail.rollAmount = V.cfg['bank'..want..'Amount']
    V.cfg.bankMode = want == 'Pilot' and 'pilot' or 'other'
    V.save()
    log(string.format('banking for %s: %d %%, max %.1f, amount %.2f', want == 'Pilot' and '"exactly like the vehicle"' or 'the other follow modes',
        V.cfg.roll, V.cfg.detail.rollMax, V.cfg.detail.rollAmount))
    return true
end
V.syncBankingMode(V.cfg.cameraLock)       -- (already on "exactly like the vehicle" from an older version)

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
