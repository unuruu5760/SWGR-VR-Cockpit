-- one engine tick for all sections, each protected on its own
do
    local log = V.logger('main')
    callbacks.on_pre_engine_tick(function(engine, dt)
        dt = tonumber(dt) or 0
        V.t = V.t + dt
        for _, tk in ipairs(V.ticks) do
            local ok, err = pcall(tk.fn, dt)
            if not ok and V.t > (tk.errT or 0) then tk.errT = V.t + 5; log(tk.name..' error: '..tostring(err)) end
        end
        V.flushSaves()
    end)
    callbacks.on_script_reset(function()
        for _, fn in ipairs(V.resets) do pcall(fn) end
        V.flushSaves()
    end)
    -- a shared fine-tuning value equal to the recommended one is not the user's own (nor, in a settings
    -- file from before it got a new recommended one, equal to the one before: item.before)
    local pruned = false
    for k, v in pairs(V.cfg.detail) do
        local item = V.TUNE_INDEX[k]
        local old = item and V.cfgFormat < 3 and item.before
        if item and (math.abs(v - item.base) < 0.001 or old and math.abs(v - old) < 0.001) then V.cfg.detail[k] = nil; pruned = true end
    end
    if pruned then V.save() end
    log('loaded v'..VERSION..' ('..LANG..')')
end
