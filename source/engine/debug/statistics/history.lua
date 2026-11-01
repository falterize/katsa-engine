-- Bounded time buckets preserve spikes as well as means. No per-sample allocation.
local History = {}
History.__index = History

function History.new(capacity, interval, aggregation)
    capacity, interval = capacity or 120, interval or 0.25
    assert(capacity >= 1 and capacity % 1 == 0, 'History capacity must be a positive integer')
    assert(interval > 0 and interval < math.huge, 'History interval must be finite and positive')
    assert(aggregation == nil or aggregation == 'rate', 'Unknown history aggregation')
    return setmetatable({
        aggregation = aggregation,
        capacity = capacity,
        interval = interval,
        buckets = {},
        count = 0,
        head = 0,
        lastTime = -math.huge,
        revision = 0,
    }, History)
end

function History:sample(time, value)
    assert(
        type(time) == 'number' and time >= self.lastTime and time < math.huge,
        'History time must be finite and monotonic'
    )
    assert(
        type(value) == 'number' and value == value and math.abs(value) < math.huge,
        'History values must be finite'
    )
    assert(not self.aggregation or value > 0, 'Rate samples must be positive')
    self.lastTime, self.last = time, value
    local bucket = self.buckets[self.head]
    local period = math.floor(time / self.interval)
    if not bucket or bucket.period ~= period then
        self.head = self.head % self.capacity + 1
        bucket = self.buckets[self.head] or {}
        self.buckets[self.head] = bucket
        bucket.period, bucket.sum, bucket.samples, bucket.duration = period, 0, 0, 0
        bucket.low, bucket.high = value, value
        self.count = math.min(self.count + 1, self.capacity)
    end
    bucket.time, bucket.last = time, value
    bucket.sum, bucket.samples = bucket.sum + value, bucket.samples + 1
    bucket.low, bucket.high = math.min(bucket.low, value), math.max(bucket.high, value)
    -- Rates represent completed events: frames / elapsed seconds, not mean(1 / dt).
    if self.aggregation == 'rate' then
        bucket.duration = bucket.duration + 1 / value
    end
    bucket.mean = self.aggregation and bucket.samples / bucket.duration
        or bucket.sum / bucket.samples
    self.revision = self.revision + 1
end

function History:get(index)
    if index < 1 or index > self.count then
        return
    end
    return self.buckets[(self.head - self.count + index - 1) % self.capacity + 1]
end

function History:summary(seconds, out, time)
    out = out or {}
    local sum, samples, count, duration = 0, 0, 0, 0
    local low, high = math.huge, -math.huge
    local cutoff = (time or self.lastTime) - (seconds or self.capacity * self.interval)
    for index = 1, self.count do
        local bucket = self:get(index)
        if bucket.time >= cutoff then
            sum, samples, count = sum + bucket.sum, samples + bucket.samples, count + 1
            duration = duration + bucket.duration
            low, high = math.min(low, bucket.low), math.max(high, bucket.high)
        end
    end
    out.mean, out.low, out.high =
        samples > 0 and (self.aggregation and samples / duration or sum / samples) or 0,
        samples > 0 and low or 0,
        samples > 0 and high or 0
    out.last, out.count = self.last or 0, count
    out.samples, out.duration = samples, duration
    return out
end

return History
