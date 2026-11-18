-- A tiny per-section timer for the editor's own update, so a slow frame can be traced to a part
-- of it. Sections are timed with os.clock (CPU seconds) and averaged over about a second; the
-- result is a one-line text for the status bar (View > Performance info). Pure Lua.
local Profiler = {}
Profiler.__index = Profiler

-- `engine` is the optional engine profiler (`katsa.profiler`): while it records, every section is
-- also a stage named `Editor: <section>` in the ImGui Profiler window and in --profile logs.
function Profiler.new(clock, engine)
    return setmetatable({
        clock = clock or os.clock,
        engine = engine,
        sums = {},
        order = {},
        frames = 0,
        elapsed = 0,
        text = '',
    }, Profiler)
end

-- Times `fn`; the name is remembered in first-use order.
function Profiler:run(name, fn, ...)
    local start = self.clock()
    local a, b
    local engine = self.engine
    if engine and engine.isEnabled() then
        a, b = engine.scope('Editor: ' .. name, fn, ...)
    else
        a, b = fn(...)
    end
    local took = self.clock() - start
    local sums = self.sums
    if not sums[name] then
        sums[name] = 0
        self.order[#self.order + 1] = name
    end
    sums[name] = sums[name] + took
    return a, b
end

-- Call once per frame with the frame time; rebuilds `text` about once a second.
function Profiler:frame(dt)
    self.frames, self.elapsed = self.frames + 1, self.elapsed + dt
    if self.elapsed < 1 then
        return
    end
    local parts, total = {}, 0
    for _, name in ipairs(self.order) do
        local ms = self.sums[name] / self.frames * 1000
        total = total + ms
        self.sums[name] = 0
        if ms >= 0.05 then
            parts[#parts + 1] = ('%s %.2f'):format(name, ms)
        end
    end
    self.text = ('editor %.1f ms | %s'):format(total, table.concat(parts, ', '))
    self.frames, self.elapsed = 0, 0
end

return Profiler
