-- Test-only bridge for the available Lua 5.3 runner. Production uses LuaJIT.
unpack = unpack or table.unpack
if not setfenv then
    function setfenv(fn, environment)
        local index = 1
        while true do
            local name = debug.getupvalue(fn, index)
            if not name then
                break
            end
            if name == '_ENV' then
                local function holder()
                    return environment
                end
                debug.upvaluejoin(fn, index, holder, 1)
                break
            end
            index = index + 1
        end
        return fn
    end
end
if bit32 then
    package.preload.bit32 = function()
        return bit32
    end
    package.preload.bit = function()
        return bit32
    end
end
math.atan2 = math.atan2 or function(y, x)
    return math.atan(y, x)
end

return true
