-- Wraps a katsa.net peer so every packet can be delayed, dropped or duplicated on its way out and
-- on its way in (see conditions.lua). Delivery times use a virtual clock advanced by `update(dt)`,
-- so results are reproducible with a seeded `random`. Without active conditions it forwards
-- straight to the peer.
local Link = {}
Link.__index = Link

-- conditions: a Conditions object, or any table with latency/jitter/loss/duplicate/random fields.
function Link.new(peer, conditions)
    return setmetatable({
        peer = peer,
        conditions = conditions,
        queue = {},
        now = 0,
        -- Reliable packets keep their order: a later one never overtakes an earlier one.
        lastDue = { out = 0, ['in'] = 0 },
    }, Link)
end

local function active(conditions)
    if not conditions then
        return false
    end
    if conditions.isActive then
        return conditions:isActive()
    end
    return true
end

-- Decides what happens to one packet. Returns nil when it is lost, otherwise the list of delays
-- (two entries when it is duplicated).
local function plan(self, direction, channel)
    local conditions = self.conditions
    local random = conditions.random or math.random
    local unreliable = channel ~= 1
    if unreliable and (conditions.loss or 0) > 0 and random() < conditions.loss then
        return nil
    end
    local delay = (conditions.latency or 0) + (conditions.jitter or 0) * random()
    if not unreliable then
        delay = math.max(self.now + delay, self.lastDue[direction]) - self.now
        self.lastDue[direction] = self.now + delay
    end
    local delays = { delay }
    if unreliable and (conditions.duplicate or 0) > 0 and random() < conditions.duplicate then
        delays[2] = delay + (conditions.jitter or 0) * random() + 0.001
    end
    return delays
end

local function enqueue(self, direction, data, channel, deliver)
    local delays = plan(self, direction, channel)
    if delays then
        for _, delay in ipairs(delays) do
            self.queue[#self.queue + 1] = {
                due = self.now + delay,
                data = data,
                channel = channel,
                deliver = deliver,
                order = #self.queue,
            }
        end
    end
end

function Link:send(data, channel)
    if not active(self.conditions) then
        return self.peer:send(data, channel)
    end
    enqueue(self, 'out', data, channel, nil)
    return true
end

-- An incoming packet: `deliver(data, channel)` runs now, or later when conditions delay it.
function Link:receive(data, channel, deliver)
    if not active(self.conditions) then
        return deliver(data, channel)
    end
    enqueue(self, 'in', data, channel, deliver)
end

-- Releases the packets whose delay has elapsed, in the order they fall due.
function Link:update(dt)
    self.now = self.now + dt
    local queue = self.queue
    if #queue == 0 then
        return
    end
    local ready, remaining = {}, {}
    for _, item in ipairs(queue) do
        if item.due <= self.now then
            ready[#ready + 1] = item
        else
            remaining[#remaining + 1] = item
        end
    end
    self.queue = remaining
    table.sort(ready, function(a, b)
        if a.due ~= b.due then
            return a.due < b.due
        end
        return a.order < b.order
    end)
    for _, item in ipairs(ready) do
        if item.deliver then
            item.deliver(item.data, item.channel)
        else
            self.peer:send(item.data, item.channel)
        end
    end
end

function Link:getPeer()
    return self.peer
end

return Link
