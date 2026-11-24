-- Watches LuaJIT's trace events. A healthy run flushes the trace cache a handful of times (scene
-- changes); a run that flushes it dozens of times a second spends nearly all its time compiling
-- the same code again (seen on a phone: 0.3 fps while dragging a menu). The guard then turns the
-- JIT off for the rest of the run, so the game stays playable in the interpreter.
local JitGuard = {
    stats = { started = 0, stopped = 0, aborted = 0, flushes = 0, reasons = {} },
    window = 2, -- seconds
    limit = 30, -- flushes within one window
    disabled = false,
}

local installed = false
local recent, windowStart = 0, nil

-- Names of the abort codes, when LuaJIT's own table is shipped with the build.
local function reasonName(code)
    local ok, vmdef = pcall(require, 'jit.vmdef')
    local name = ok and vmdef.traceerr and vmdef.traceerr[code]
    return name or ('code ' .. tostring(code))
end

function JitGuard.install()
    if installed or not jit or not jit.attach then
        return false
    end
    installed = true
    local stats = JitGuard.stats
    -- Runs inside the compiler: only counts, never calls back into the engine.
    jit.attach(function(what, _, _, _, code)
        if what == 'start' then
            stats.started = stats.started + 1
        elseif what == 'stop' then
            stats.stopped = stats.stopped + 1
        elseif what == 'abort' then
            stats.aborted = stats.aborted + 1
            stats.reasons[code] = (stats.reasons[code] or 0) + 1
        elseif what == 'flush' then
            stats.flushes = stats.flushes + 1
            recent = recent + 1
        end
    end, 'trace')
    return true
end

-- Called once per frame with the current time in seconds.
function JitGuard.update(now)
    if JitGuard.disabled or not installed then
        return
    end
    windowStart = windowStart or now
    if now - windowStart < JitGuard.window then
        return
    end
    local flushes = recent
    recent, windowStart = 0, now
    if flushes >= JitGuard.limit then
        JitGuard.disabled = true
        jit.off()
        jit.flush()
        if katsa and katsa.log then
            katsa.log.warn(
                ('LuaJIT flushed its trace cache %d times in %d s; the JIT is turned off'):format(
                    flushes,
                    JitGuard.window
                ),
                'jit',
                false
            )
        end
    end
end

-- The commonest abort reasons as "name xN" strings, most frequent first.
function JitGuard.topReasons(count)
    local rows = {}
    for code, total in pairs(JitGuard.stats.reasons) do
        rows[#rows + 1] = { code, total }
    end
    table.sort(rows, function(a, b)
        return a[2] > b[2]
    end)
    local top = {}
    for i = 1, math.min(count, #rows) do
        top[i] = ('%s x%d'):format(reasonName(rows[i][1]), rows[i][2])
    end
    return top
end

return JitGuard
