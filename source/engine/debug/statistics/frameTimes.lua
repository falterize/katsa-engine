local FrameTimes = {}
FrameTimes.__index = FrameTimes

function FrameTimes.new(capacity)
    capacity = capacity or 12000
    assert(capacity >= 1 and capacity % 1 == 0, 'Invalid frame sample capacity')
    return setmetatable({ capacity = capacity, values = {}, head = 0, count = 0 }, FrameTimes)
end

function FrameTimes:add(seconds)
    assert(type(seconds) == 'number' and seconds > 0 and seconds < math.huge, 'Invalid frame time')
    self.head = self.head % self.capacity + 1
    self.values[self.head] = seconds * 1000
    self.count = math.min(self.count + 1, self.capacity)
end

-- Sort a copy only when a report is requested, never in the sampling path.
function FrameTimes:summary()
    local ordered, sum, slow = {}, 0, 0
    for index = 1, self.count do
        local value = self.values[index]
        ordered[index] = value
        sum = sum + value
        if value > 1000 / 60 then
            slow = slow + 1
        end
    end
    table.sort(ordered)
    local count = self.count
    return {
        frames = count,
        seconds = sum / 1000,
        fps = sum > 0 and count * 1000 / sum or 0,
        meanMilliseconds = count > 0 and sum / count or 0,
        p95Milliseconds = ordered[math.ceil(count * 0.95)] or 0,
        p99Milliseconds = ordered[math.ceil(count * 0.99)] or 0,
        worstMilliseconds = ordered[count] or 0,
        framesOver60HzBudget = slow,
    }
end

return FrameTimes
