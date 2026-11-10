-- Simulated network conditions: presets, argument parsing and the Link that applies them.
local Conditions = require('source.engine.net.conditions')
local Link = require('source.engine.net.link')

local Module = {}

-- A peer that records what reaches the wire.
local function wire()
    local sent = {}
    return {
        sent = sent,
        send = function(_, data, channel)
            sent[#sent + 1] = { data = data, channel = channel }
            return true
        end,
    }
end

local function sequence(values)
    local index = 0
    return function()
        index = index % #values + 1
        return values[index]
    end
end

function Module.run(self)
    local c = Conditions.new()
    self:check(not c:isActive() and c:describe() == 'no simulation', 'new conditions simulate nothing')
    c:set('poor')
    self:check(c.latency == 0.12 and c:getPreset() == 'poor', 'a preset sets every value')
    c:set({ latency = 0.3 })
    self:check(c.jitter == 0 and c:getPreset() == nil, 'explicit values replace the preset')
    c:set('terrible')
    self:check(c:cycle() == 'off' and not c:isActive(), 'cycle wraps from the worst preset to off')
    self:check(not pcall(c.set, c, { loss = 2 }), 'a loss above 1 is rejected')
    local parsed = Conditions.fromArguments({ '--sim-latency', '80', '--sim-jitter', '20', '--sim-loss', '5' })
    self:check(
        math.abs(parsed.latency - 0.08) < 1e-9 and math.abs(parsed.loss - 0.05) < 1e-9,
        'launch arguments give milliseconds and percent'
    )

    local peer = wire()
    local link = Link.new(peer, Conditions.new())
    link:send('a', 1)
    self:check(#peer.sent == 1, 'without conditions a packet goes straight out')

    peer = wire()
    link = Link.new(peer, Conditions.new({ latency = 0.1, random = function() return 0 end }))
    link:send('a', 1)
    link:update(0.05)
    local early = #peer.sent
    link:update(0.06)
    self:check(early == 0 and #peer.sent == 1, 'latency holds a packet back until it has elapsed')

    -- Reliable packets keep their order even when jitter would reorder them; unreliable ones may not.
    peer = wire()
    link = Link.new(peer, Conditions.new({ jitter = 1, random = sequence({ 0.9, 0.1, 0.9, 0.1 }) }))
    link:send('r1', 1)
    link:send('r2', 1)
    link:send('u1', 3)
    link:send('u2', 3)
    link:update(2)
    local order = {}
    for _, item in ipairs(peer.sent) do
        order[#order + 1] = item.data
    end
    local r1, r2
    for index, name in ipairs(order) do
        r1 = name == 'r1' and index or r1
        r2 = name == 'r2' and index or r2
    end
    self:check(r1 < r2, 'reliable packets are never reordered by jitter')

    peer = wire()
    link = Link.new(peer, Conditions.new({ loss = 1, random = function() return 0.5 end }))
    for _ = 1, 4 do
        link:send('u', 3)
    end
    link:send('r', 1)
    link:update(1)
    local unreliable, reliable = 0, 0
    for _, item in ipairs(peer.sent) do
        if item.channel == 1 then
            reliable = reliable + 1
        else
            unreliable = unreliable + 1
        end
    end
    self:check(unreliable == 0 and reliable == 1, 'loss drops unreliable packets but never reliable ones')

    peer = wire()
    link = Link.new(peer, Conditions.new({ duplicate = 1, random = function() return 0 end }))
    link:send('u', 3)
    link:update(1)
    self:check(#peer.sent == 2, 'duplicate sends an unreliable packet twice')

    local received = {}
    link = Link.new(wire(), Conditions.new({ latency = 0.1, random = function() return 0 end }))
    link:receive('in', 1, function(data) received[#received + 1] = data end)
    link:update(0.05)
    local before = #received
    link:update(0.06)
    self:check(before == 0 and #received == 1, 'incoming packets are delayed too')
end

return Module
