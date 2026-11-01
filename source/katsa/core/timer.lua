-- katsa.timer: monotonic clock, frame delta and FPS (same behaviour as love.timer).
local ffi = require('ffi')

local Timer = {}

local now, sleep

if ffi.os == 'Windows' then
    ffi.cdef([[
        int QueryPerformanceCounter(int64_t* count);
        int QueryPerformanceFrequency(int64_t* frequency);
        void Sleep(uint32_t milliseconds);
    ]])
    local kernel = ffi.C
    local frequency = ffi.new('int64_t[1]')
    kernel.QueryPerformanceFrequency(frequency)
    local scale = 1 / tonumber(frequency[0])
    local counter = ffi.new('int64_t[1]')
    local origin
    now = function()
        kernel.QueryPerformanceCounter(counter)
        origin = origin or counter[0]
        return tonumber(counter[0] - origin) * scale
    end
    sleep = function(seconds)
        kernel.Sleep(math.floor(seconds * 1000 + 0.5))
    end
else
    ffi.cdef([[
        typedef struct { long tv_sec; long tv_nsec; } katsa_timespec;
        int clock_gettime(int clock, katsa_timespec* spec);
        int nanosleep(const katsa_timespec* request, katsa_timespec* remaining);
    ]])
    local spec = ffi.new('katsa_timespec')
    local request = ffi.new('katsa_timespec')
    -- CLOCK_MONOTONIC is 1 on Linux and Android; macOS uses 6 (CLOCK_UPTIME_RAW) semantics via 1 as well.
    local clock = 1
    local origin
    now = function()
        ffi.C.clock_gettime(clock, spec)
        local t = tonumber(spec.tv_sec) + tonumber(spec.tv_nsec) * 1e-9
        origin = origin or t
        return t - origin
    end
    sleep = function(seconds)
        if seconds <= 0 then
            return
        end
        local whole = math.floor(seconds)
        request.tv_sec = whole
        request.tv_nsec = math.floor((seconds - whole) * 1e9)
        ffi.C.nanosleep(request, nil)
    end
end

Timer.getTime = now
Timer.sleep = sleep

local previous, delta, fps = now(), 0, 0
local frames, window = 0, now()

-- Advances the frame clock and returns the time since the previous step.
function Timer.step()
    local t = now()
    delta = t - previous
    previous = t
    frames = frames + 1
    if t - window >= 1 then
        fps = frames / (t - window)
        frames, window = 0, t
    end
    return delta
end

function Timer.getDelta()
    return delta
end

function Timer.getFPS()
    return math.floor(fps + 0.5)
end

function Timer.getAverageDelta()
    return fps > 0 and 1 / fps or 0
end

return Timer
