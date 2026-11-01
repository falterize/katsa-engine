-- Opt-in CPU wall-clock observations. No GPU timer or FPS prediction.
local Profiler = {}
Profiler.__index = Profiler

function Profiler.new()
    return setmetatable({ enabled = false, samples = {}, frames = 0 }, Profiler)
end

function Profiler:begin()
    if self.enabled then
        return love.timer.getTime()
    end
end

function Profiler:finish(name, start)
    if start then
        self:sample(name, (love.timer.getTime() - start) * 1000)
    end
end

function Profiler:sample(name, value)
    if not self.enabled then
        return
    end
    local s = self.samples[name]
    if not s then
        s = { average = value, peak = value, count = 0 }
        self.samples[name] = s
    end
    s.last = value
    s.average = s.average * 0.9 + value * 0.1
    s.peak = math.max(s.peak, value)
    s.count = s.count + 1
end

function Profiler:frame()
    if not self.enabled then
        return
    end
    self.frames = self.frames + 1
    if self.frames % 30 == 0 then
        self.luaKiB = collectgarbage('count')
        self.textureBytes = love.graphics.getStats().texturememory
    end
end

function Profiler:clear()
    self.samples = {}
    self.frames = 0
end

return Profiler
