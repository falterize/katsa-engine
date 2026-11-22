-- Keep compiled scene/UI traces resident. Repeated global cache flushes cause
-- periodic recompilation stalls in large polymorphic node graphs.
-- The extended rig workload exceeds 8 MiB of code before reaching the trace limit.
local Runtime = { traceBudget = 8000, machineCodeKiB = 32768, configured = false }

-- True when started with --server: no drawing or presenting, the loop only updates and sleeps (at
-- `frameRateLimit`, 60 by default), and a lost window focus never pauses the scene.
Runtime.headless = false

function Runtime.validateFrameRateLimit(value)
    assert(
        type(value) == 'number' and value >= 0 and value < math.huge and value % 1 == 0,
        'frameRateLimit must be zero or a positive integer'
    )
    return value
end

function Runtime.initialize()
    if Runtime.initialized then
        return Runtime.configured
    end
    Runtime.initialized = true
    if not jit then
        return false
    end
    -- The first on-device logs from an arm64 phone show impossible Lua errors ("attempt to compare
    -- number with string" on numbers, a bad argument on a plain assignment): a compiled-trace fault.
    -- Until that is explained Android runs the interpreter; KATSA_JIT=1 turns the JIT back on.
    if require('source.katsa.core.native').os() == 'Android' and os.getenv('KATSA_JIT') ~= '1' then
        jit.off()
        jit.flush()
        Runtime.jitDisabled = 'Android'
        return false
    end
    local ok, options = pcall(require, 'jit.opt')
    if not ok then
        return false
    end
    local applied, message = pcall(
        options.start,
        'maxtrace=' .. Runtime.traceBudget,
        'maxmcode=' .. Runtime.machineCodeKiB
    )
    Runtime.configured = applied
    Runtime.error = not applied and tostring(message) or nil
    -- Changing cache limits never enables JIT or modifies arithmetic optimizations.
    return applied
end

return Runtime
