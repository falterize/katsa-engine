-- Simulated network conditions for testing: delay, jitter, packet loss and duplicates. One object
-- is shared by every Link of a Server (or by a Client's link), so changing it at run time affects
-- all connections at once.
--
--   local conditions = Conditions.new({ latency = 0.08, jitter = 0.02, loss = 0.03 })
--   conditions:set('poor')               -- a preset
--   conditions:set({ latency = 0.2 })    -- or explicit values (missing ones become 0)
--   conditions:isActive()                -- false when nothing is simulated
--
-- Units: `latency` and `jitter` are seconds added to every packet in each direction (so the round
-- trip grows by twice the latency); `loss` and `duplicate` are probabilities 0..1 and apply to
-- unreliable channels only, because reliable packets are retransmitted by the transport anyway.
local Conditions = {}
Conditions.__index = Conditions

Conditions.presets = {
    off = { latency = 0, jitter = 0, loss = 0, duplicate = 0 },
    good = { latency = 0.02, jitter = 0.005, loss = 0, duplicate = 0 },
    mobile = { latency = 0.05, jitter = 0.02, loss = 0.01, duplicate = 0 },
    poor = { latency = 0.12, jitter = 0.05, loss = 0.04, duplicate = 0 },
    terrible = { latency = 0.25, jitter = 0.1, loss = 0.12, duplicate = 0.02 },
}

-- Preset names from mildest to worst, for a cycling button.
Conditions.order = { 'off', 'good', 'mobile', 'poor', 'terrible' }

local FIELDS = { 'latency', 'jitter', 'loss', 'duplicate' }

local function check(values)
    for _, key in ipairs(FIELDS) do
        local value = values[key]
        assert(
            value == nil or (type(value) == 'number' and value >= 0 and value < math.huge),
            'Network condition ' .. key .. ' must be a non-negative number'
        )
    end
    assert((values.loss or 0) <= 1 and (values.duplicate or 0) <= 1, 'loss and duplicate are 0..1')
end

function Conditions.new(values)
    local self = setmetatable({ latency = 0, jitter = 0, loss = 0, duplicate = 0 }, Conditions)
    if values then
        self:set(values)
    end
    return self
end

-- Replaces every value: a preset name, or a table (`random` may supply a seeded random function).
function Conditions:set(values)
    if type(values) == 'string' then
        values = assert(Conditions.presets[values], 'Unknown network preset: ' .. values)
    end
    check(values)
    for _, key in ipairs(FIELDS) do
        self[key] = values[key] or 0
    end
    self.random = values.random
    return self
end

function Conditions:isActive()
    return self.latency > 0 or self.jitter > 0 or self.loss > 0 or self.duplicate > 0
end

-- The preset that matches the current values, or nil.
function Conditions:getPreset()
    for name, preset in pairs(Conditions.presets) do
        local same = true
        for _, key in ipairs(FIELDS) do
            same = same and math.abs(self[key] - preset[key]) < 1e-9
        end
        if same then
            return name
        end
    end
end

-- Moves to the next preset of `order` (after the current one, or the first when it is custom).
function Conditions:cycle()
    local current = self:getPreset()
    local index = 0
    for i, name in ipairs(Conditions.order) do
        if name == current then
            index = i
        end
    end
    local name = Conditions.order[index % #Conditions.order + 1]
    self:set(name)
    return name
end

function Conditions:describe()
    if not self:isActive() then
        return 'no simulation'
    end
    return ('%.0f ms +%.0f ms jitter, %.1f%% loss, %.1f%% duplicates'):format(
        self.latency * 1000,
        self.jitter * 1000,
        self.loss * 100,
        self.duplicate * 100
    )
end

-- Reads --sim-latency <ms>, --sim-jitter <ms>, --sim-loss <percent>, --sim-duplicate <percent> and
-- --sim-preset <name> from a launch argument list. Returns a Conditions object.
function Conditions.fromArguments(arguments)
    local result = Conditions.new()
    local values = {}
    for index, argument in ipairs(arguments or {}) do
        local value = tonumber(arguments[index + 1])
        if argument == '--sim-preset' then
            values = {}
            for key, preset in pairs(assert(Conditions.presets[arguments[index + 1]], 'Unknown --sim-preset')) do
                values[key] = preset
            end
        elseif argument == '--sim-latency' and value then
            values.latency = value / 1000
        elseif argument == '--sim-jitter' and value then
            values.jitter = value / 1000
        elseif argument == '--sim-loss' and value then
            values.loss = value / 100
        elseif argument == '--sim-duplicate' and value then
            values.duplicate = value / 100
        end
    end
    return result:set(values)
end

return Conditions
