local Wait = {}
local ffi, kernel, handle, due
local initialized = false

local function initialize()
    if initialized then
        return handle ~= nil
    end
    initialized = true
    ffi = require('ffi')
    if ffi.os ~= 'Windows' then
        return false
    end
    ffi.cdef([[
        void * __stdcall CreateWaitableTimerExW(void *, const uint16_t *, unsigned long, unsigned long);
        int __stdcall SetWaitableTimer(void *, const int64_t *, long, void *, void *, int);
        unsigned long __stdcall WaitForSingleObject(void *, unsigned long);
        int __stdcall CloseHandle(void *);
    ]])
    kernel = ffi.load('kernel32')
    -- Windows 10 supports high-resolution relative waits without changing the
    -- system timer period. Older systems use the portable deadline fallback.
    local ok, timer = pcall(function()
        return kernel.CreateWaitableTimerExW(nil, nil, 2, 0x1F0003)
    end)
    if not ok or timer == nil then
        return false
    end
    handle = ffi.gc(timer, kernel.CloseHandle)
    due = ffi.new('int64_t[1]')
    return true
end

function Wait.sleep(seconds)
    if not initialize() then
        return false
    end
    -- Negative values are relative intervals in 100 ns units.
    due[0] = -math.max(1, math.ceil(seconds * 10000000))
    if kernel.SetWaitableTimer(handle, due, 0, nil, nil, 0) == 0 then
        return false
    end
    return kernel.WaitForSingleObject(handle, 0xFFFFFFFF) == 0
end

return Wait
