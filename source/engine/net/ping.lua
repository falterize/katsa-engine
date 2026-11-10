-- Application-level round trip time. A transport ping (ENet) cannot see the delay that simulated
-- network conditions add above it, so the server and the client time their own PING/PONG packets
-- through the same Link the game data uses. Both ends keep one of these per connection.
--
--   local ping = Ping.new()
--   if ping:isDue(dt) then send(PING, ping:stamp()) end      -- every `interval` seconds
--   ping:reply(sentAt)                                       -- when a PONG arrives
--   ping:get()                                               -- smoothed milliseconds, or nil
local Ping = {}
Ping.__index = Ping

local INTERVAL = 1
local SMOOTHING = 0.3 -- weight of the newest sample

function Ping.new(interval)
    return setmetatable({ interval = interval or INTERVAL, timer = 0, value = nil, samples = 0 }, Ping)
end

-- True once per interval of accumulated time.
function Ping:isDue(dt)
    self.timer = self.timer + dt
    if self.timer >= self.interval then
        self.timer = self.timer - self.interval
        return true
    end
    return false
end

-- The timestamp to put in an outgoing PING.
function Ping:stamp()
    return katsa.timer.getTime()
end

-- A PONG came back carrying the timestamp of its PING.
function Ping:reply(sentAt)
    local sample = (katsa.timer.getTime() - sentAt) * 1000
    if sample < 0 then
        return
    end
    self.samples = self.samples + 1
    self.value = self.value and (self.value * (1 - SMOOTHING) + sample * SMOOTHING) or sample
end

-- Smoothed round trip in milliseconds, nil before the first answer.
function Ping:get()
    return self.value
end

return Ping
