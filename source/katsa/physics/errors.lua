-- Errors raised inside native callbacks cannot unwind through C; they are stored and rethrown once
-- the native call returns.
local pending

local Errors = {}

function Errors.guard(fn)
    return function(...)
        local ok, first, second = pcall(fn, ...)
        if not ok then
            pending = pending or first
            return 0
        end
        return first, second
    end
end

function Errors.rethrow()
    if pending then
        local err = pending
        pending = nil
        error(err, 0)
    end
end

return Errors
