-- Desktop-only profiling adapter. Never used by the renderer or on Android.
-- katsa has no portable GPU timer API; unsupported contexts report unavailable.
local Timer = {}

function Timer.new()
    if katsa.system.getOS() ~= 'Linux' or katsa.graphics.getRendererInfo() ~= 'OpenGL' then
        return
    end
    local ok, result = pcall(function()
        local ffi = require('ffi')
        ffi.cdef([[
            void glGenQueries(int n, unsigned int *ids);
            void glDeleteQueries(int n, const unsigned int *ids);
            void glBeginQuery(unsigned int target, unsigned int id);
            void glEndQuery(unsigned int target);
            void glGetQueryObjectui64v(unsigned int id, unsigned int pname, uint64_t *params);
        ]])
        local gl = ffi.load('libGL.so.1')
        local ids = ffi.new('unsigned int[2]')
        gl.glGenQueries(2, ids)
        return {
            begin = function(_, i)
                gl.glBeginQuery(0x88BF, ids[i])
            end,
            finish = function()
                gl.glEndQuery(0x88BF)
            end,
            read = function(_, i)
                local value = ffi.new('uint64_t[1]')
                gl.glGetQueryObjectui64v(ids[i], 0x8866, value)
                return tonumber(value[0]) / 1000000
            end,
            release = function()
                gl.glDeleteQueries(2, ids)
            end,
        }
    end)
    if ok then
        return result
    end
end

return Timer
