-- Wraps a katsa.net peer so tests and tools can simulate latency, jitter and packet loss.
-- Delivery times use a virtual clock advanced by `update(dt)`, so results are reproducible
-- (the random source is seedable). Without simulation options it forwards straight to the peer.
local Link = {}
Link.__index = Link

-- simulate: { latency = seconds one way, jitter = seconds, loss = 0..1, random = function }
function Link.new(peer, simulate)
    return setmetatable({ peer = peer, simulate = simulate, queue = {}, now = 0 }, Link)
end

function Link:send(data, channel)
    local simulate = self.simulate
    if not simulate then
        return self.peer:send(data, channel)
    end
    local random = simulate.random or math.random
    if channel ~= 1 and (simulate.loss or 0) > 0 and random() < simulate.loss then
        return true
    end
    local delay = (simulate.latency or 0) + (simulate.jitter or 0) * random()
    self.queue[#self.queue + 1] = { due = self.now + delay, data = data, channel = channel }
    return true
end

-- Releases packets whose delay has elapsed. Reliable packets keep their order.
function Link:update(dt)
    self.now = self.now + dt
    local queue = self.queue
    if #queue == 0 then
        return
    end
    local remaining = {}
    for _, item in ipairs(queue) do
        if item.due <= self.now then
            self.peer:send(item.data, item.channel)
        else
            remaining[#remaining + 1] = item
        end
    end
    self.queue = remaining
end

function Link:getPeer()
    return self.peer
end

return Link
