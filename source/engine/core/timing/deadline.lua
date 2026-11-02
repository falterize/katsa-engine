local WindowsWait = require('./windowsWait')
local systemTimer = katsa.timer

local Deadline = {}

function Deadline.waitUntil(target, timer, sleep)
    local remaining = target - timer.getTime()
    while remaining > 0 do
        -- Native waits advance the system clock only. Injected/virtual clocks
        -- use their own sleep implementation so deterministic tests cannot hang.
        local blocked = sleep and sleep(remaining)
            or not sleep and timer == systemTimer and WindowsWait.sleep(remaining)
        if not blocked then
            -- SDL may truncate fractional milliseconds to zero. Always
            -- block for at least 1 ms on the fallback path, then recheck time.
            timer.sleep(math.max(0.001, remaining))
        end
        remaining = target - timer.getTime()
    end
end

return Deadline
