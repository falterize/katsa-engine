-- Opt-in CPU wall-clock profiler. No GPU timer or FPS prediction.
--
--   local stamp = profiler:begin()           -- nil while disabled, so it costs nothing
--   ... work ...
--   profiler:finish('My stage', stamp)
--   profiler:scope('Pathfinding', function() ... end)   -- same, exception safe
--
-- Every rendered frame calls profiler:frame(). While enabled the profiler keeps the last
-- HISTORY frames (frame time plus every stage's milliseconds in that frame) for percentiles and
-- the panel, and a session recording can capture every frame for export (JSON or CSV in logs/).
local Json = require('vendor.json')
local Csv = require('./csv')
local Version = require('../core.version')

local Profiler = {}
Profiler.__index = Profiler

local HISTORY = 600 -- about ten seconds at 60 Hz
local RECORD_LIMIT = 72000 -- twenty minutes at 60 Hz

function Profiler.new()
    return setmetatable({
        enabled = false,
        samples = {},
        frames = 0,
        current = {},
        history = {},
        head = 0,
        count = 0,
        recording = nil,
        running = {},
        warned = {},
        loading = {},
    }, Profiler)
end

function Profiler:begin()
    if self.enabled then
        return katsa.timer.getTime()
    end
end

function Profiler:finish(name, start)
    if start then
        self:sample(name, (katsa.timer.getTime() - start) * 1000)
    end
end

-- Load phases. They are measured even while the profiler is off (a scene loads before anyone can
-- switch it on), kept in `loading` and added to exports and the diagnostics panel:
--   profiler:beginLoad('Scene multiplayerCars')
--   ... open the package ...    profiler:markLoad('Open package')
--   ... create the world ...    profiler:markLoad('Create world')
-- Each mark records the time since the previous mark (or the begin) as one phase.
function Profiler:beginLoad(scene)
    self.loading = { scene = scene, phases = {}, started = katsa.timer.getTime() }
    self.loadMark = self.loading.started
end

function Profiler:markLoad(name)
    local now = katsa.timer.getTime()
    local loading = self.loading
    if not (loading and loading.phases and self.loadMark) then
        return
    end
    local ms = (now - self.loadMark) * 1000
    self.loadMark = now
    loading.phases[#loading.phases + 1] = { name = name, ms = ms }
    loading.total = (now - loading.started) * 1000
    if self.enabled then
        self:sample('Load: ' .. name, ms)
    end
end

-- Named tasks that can span many frames or nest:
--   profiler:start('generating map')  ...  profiler:stop('generating map')
-- Each stop records one sample of the elapsed milliseconds under that name (so it joins the
-- stage list, the history and the exports). While a task runs it is listed in `running`.
-- Starting a name that is already running nests; stops match the most recent start.
-- Returns the elapsed milliseconds from stop(), or nil while disabled.
function Profiler:start(name)
    assert(type(name) == 'string' and name ~= '', 'Profiler task needs a name')
    if not self.enabled then
        return
    end
    local task = self.running[name]
    if not task then
        task = { stamps = {}, since = katsa.timer.getTime() }
        self.running[name] = task
    end
    task.stamps[#task.stamps + 1] = katsa.timer.getTime()
end

function Profiler:stop(name)
    local task = self.running[name]
    if not task then
        if self.enabled and not self.warned[name] then
            self.warned[name] = true
            katsa.log.write('warn', 'profiler.stop without start: ' .. tostring(name), 'profiler')
        end
        return
    end
    local stamp = table.remove(task.stamps)
    if #task.stamps == 0 then
        self.running[name] = nil
    end
    local elapsed = (katsa.timer.getTime() - stamp) * 1000
    self:sample(name, elapsed)
    return elapsed
end

-- Tasks started and not yet stopped: { name, seconds } sorted by name.
function Profiler:getRunning()
    local list, now = {}, katsa.timer.getTime()
    for name, task in pairs(self.running) do
        list[#list + 1] = { name = name, seconds = now - task.stamps[1], depth = #task.stamps }
    end
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end

-- Times fn(...) as stage `name` and returns its results. Errors pass through.
function Profiler:scope(name, fn, ...)
    local stamp = self:begin()
    if not stamp then
        return fn(...)
    end
    local results = { pcall(fn, ...) }
    self:finish(name, stamp)
    if not results[1] then
        error(results[2], 0)
    end
    return unpack(results, 2, table.maxn(results))
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
    self.current[name] = (self.current[name] or 0) + value
end

-- Call once per rendered frame. `now` (seconds) defaults to the timer; the first call only
-- starts the clock.
function Profiler:frame(now)
    if not self.enabled then
        self.lastFrame = nil
        return
    end
    now = now or katsa.timer.getTime()
    self.frames = self.frames + 1
    if self.frames % 30 == 1 then
        self.luaKiB = collectgarbage('count')
        self.textureBytes = katsa.graphics.getStats().texturememory
    end
    local last = self.lastFrame
    self.lastFrame = now
    if not last then
        self.current = {}
        return
    end
    local row = { ms = (now - last) * 1000, stages = self.current, lua = self.luaKiB }
    self.current = {}
    self.head = self.head % HISTORY + 1
    self.history[self.head] = row
    self.count = math.min(self.count + 1, HISTORY)
    local recording = self.recording
    if recording and #recording.rows < RECORD_LIMIT then
        row.time = now - recording.start
        recording.rows[#recording.rows + 1] = row
        for name in pairs(row.stages) do
            recording.names[name] = true
        end
    end
end

function Profiler:clear()
    self.samples = {}
    self.frames = 0
    self.current = {}
    self.history = {}
    self.head, self.count = 0, 0
    self.lastFrame = nil
    self.running, self.warned = {}, {}
end

-- History rows, oldest first.
function Profiler:rows()
    local rows = {}
    for index = 1, self.count do
        local slot = (self.head - self.count + index - 1) % HISTORY + 1
        rows[index] = self.history[slot]
    end
    return rows
end

local function percentile(sorted, fraction)
    return sorted[math.max(1, math.ceil(#sorted * fraction))] or 0
end

local function frameStats(rows)
    local times, sum = {}, 0
    for index, row in ipairs(rows) do
        times[index] = row.ms
        sum = sum + row.ms
    end
    table.sort(times)
    local count = #times
    local median = percentile(times, 0.5)
    local spikes = 0
    for _, value in ipairs(times) do
        if median > 0 and value > median * 2 then
            spikes = spikes + 1
        end
    end
    -- "1% low": the average frame rate of the slowest one percent of frames.
    local slowCount, slowSum = math.max(1, math.floor(count * 0.01)), 0
    for index = count - slowCount + 1, count do
        slowSum = slowSum + (times[index] or 0)
    end
    return {
        frames = count,
        fps = sum > 0 and count * 1000 / sum or 0,
        meanMilliseconds = count > 0 and sum / count or 0,
        p50Milliseconds = median,
        p95Milliseconds = percentile(times, 0.95),
        p99Milliseconds = percentile(times, 0.99),
        worstMilliseconds = times[count] or 0,
        onePercentLowFps = slowSum > 0 and slowCount * 1000 / slowSum or 0,
        spikes = spikes,
    }
end

-- Frame statistics plus one entry per stage over the history window, slowest average first.
-- Stage `share` is relative to the mean frame time (nested stages overlap, so shares can add
-- up to more than one).
function Profiler:summary(rows)
    rows = rows or self:rows()
    local frame = frameStats(rows)
    local values = {}
    for _, row in ipairs(rows) do
        for name, ms in pairs(row.stages) do
            local list = values[name]
            if not list then
                list = { sum = 0 }
                values[name] = list
            end
            list[#list + 1] = ms
            list.sum = list.sum + ms
        end
    end
    local stages = {}
    for name, list in pairs(values) do
        table.sort(list)
        local mean = list.sum / #rows -- frames without the stage count as zero
        stages[#stages + 1] = {
            name = name,
            meanMilliseconds = mean,
            p95Milliseconds = percentile(list, 0.95),
            peakMilliseconds = list[#list],
            frames = #list,
            share = frame.meanMilliseconds > 0 and mean / frame.meanMilliseconds or 0,
        }
    end
    table.sort(stages, function(a, b)
        if a.meanMilliseconds ~= b.meanMilliseconds then
            return a.meanMilliseconds > b.meanMilliseconds
        end
        return a.name < b.name
    end)
    return { frame = frame, stages = stages }
end

-- Session recording -------------------------------------------------------------------------

-- Starts capturing every enabled frame (up to twenty minutes). `meta` is stored in the export.
function Profiler:startRecording(meta)
    self.enabled = true
    self.recording = { start = katsa.timer.getTime(), rows = {}, names = {}, meta = meta or {} }
end

function Profiler:isRecording()
    return self.recording ~= nil
end

-- Stops the recording and returns it ({ rows, names, meta }).
function Profiler:stopRecording()
    local recording = self.recording
    self.recording = nil
    return recording
end

local function stageNames(recording)
    local names = {}
    for name in pairs(recording.names) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function Profiler.loadingSummary(loading)
    if not (loading and loading.phases) then
        return nil
    end
    return { scene = loading.scene, total_ms = loading.total, phases = loading.phases }
end

-- format: 'json' (summary plus compact rows) or 'csv' (one line per frame).
function Profiler.export(recording, format)
    local names = stageNames(recording)
    local rows = recording.rows
    if format == 'json' then
        local summary = Profiler.summary(setmetatable({}, Profiler), rows)
        local compact = {}
        for index, row in ipairs(rows) do
            local line = { row.frame or index, row.time or 0, row.ms, row.lua or 0 }
            for column, name in ipairs(names) do
                line[4 + column] = row.stages[name] or 0
            end
            compact[index] = line
        end
        return Json.encode({
            schema = 1,
            app_version = Version.value,
            scene = recording.meta.scene,
            started_utc = recording.meta.started,
            loading = Profiler.loadingSummary(recording.meta.loading),
            columns = { 'frame', 'time_s', 'frame_ms', 'lua_kib', unpack(names) },
            summary = summary,
            rows = compact,
        })
    elseif format == 'csv' then
        local header = { 'frame', 'time_s', 'frame_ms', 'lua_kib' }
        for _, name in ipairs(names) do
            header[#header + 1] = name
        end
        local width = #header
        local lines = { Csv.row(header, width) }
        for index, row in ipairs(rows) do
            local values = {
                index,
                string.format('%.4f', row.time or 0),
                string.format('%.3f', row.ms),
                row.lua or 0,
            }
            for _, name in ipairs(names) do
                values[#values + 1] = string.format('%.3f', row.stages[name] or 0)
            end
            lines[#lines + 1] = Csv.row(values, width)
        end
        return table.concat(lines, '\r\n') .. '\r\n'
    end
    error('Unknown profiler export format: ' .. tostring(format))
end

-- Writes a recording to logs/profile-<utc>.<format> in the save directory; returns the path.
function Profiler.save(recording, format)
    local data = Profiler.export(recording, format)
    assert(katsa.filesystem.createDirectory('logs'), 'Could not create the logs directory')
    local stem = 'logs/profile-' .. os.date('!%Y%m%dT%H%M%SZ')
    local path, index = stem .. '.' .. format, 1
    while katsa.filesystem.getInfo(path) do
        path = stem .. '-' .. index .. '.' .. format
        index = index + 1
    end
    assert(katsa.filesystem.write(path, data))
    return path
end

return Profiler
