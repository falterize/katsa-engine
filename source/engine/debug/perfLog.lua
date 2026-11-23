-- Frame-time summary written to the log every few seconds (Android by default, KATSA_PERFLOG=1
-- elsewhere), so a phone without a cable still reports where a slow frame goes: the phone console
-- and the crash report show the log. All values are milliseconds per frame averaged over the window.
local PerfLog = {}
PerfLog.__index = PerfLog

local WINDOW = 3
local PROFILE_DELAY = 8 -- seconds after a scene starts, once its loading hitches are over
local PROFILE_LENGTH = 6
local PROFILE_ROWS = 14

-- vmstate letters of LuaJIT's sampling profiler.
local STATES = {
    N = 'native/ffi (GL, C code)',
    I = 'interpreter',
    C = 'compiled traces',
    G = 'garbage collector',
    J = 'jit compiler',
}

function PerfLog.enabled()
    local flag = os.getenv('KATSA_PERFLOG')
    if flag then
        return flag == '1'
    end
    return katsa.system.getOS() == 'Android'
end

function PerfLog.new()
    return setmetatable({ frames = 0, started = nil, sum = {}, worst = 0 }, PerfLog)
end

-- Counters are reset when the frame is presented, so they are read just before that.
function PerfLog:capture()
    self.stats = katsa.graphics.getStats(self.stats)
end

-- Sampling profile of one scene (LuaJIT jit.profile, 10 ms): where Lua time goes by vm state and
-- by source line, logged once so a phone without a cable still says what is slow.
function PerfLog:startProfile()
    local ok, profile = pcall(require, 'jit.profile')
    if not ok then
        return
    end
    local lines, states, total = {}, {}, 0
    profile.start('i10', function(thread, samples, vmstate)
        local line = profile.dumpstack(thread, 'pl', 1)
        lines[line] = (lines[line] or 0) + samples
        states[vmstate] = (states[vmstate] or 0) + samples
        total = total + samples
    end)
    self.profile = { lines = lines, states = states, stop = profile.stop, total = function() return total end }
end

function PerfLog:finishProfile()
    local run = self.profile
    self.profile = nil
    run.stop()
    local total = math.max(run.total(), 1)
    local parts = {}
    for letter, name in pairs(STATES) do
        local count = run.states[letter] or 0
        if count > 0 then
            parts[#parts + 1] = ('%s %.0f%%'):format(name, count / total * 100)
        end
    end
    katsa.log.write('log', ('profile of %d samples: %s'):format(total, table.concat(parts, ', ')), 'perf')
    local rows = {}
    for line, count in pairs(run.lines) do
        rows[#rows + 1] = { line, count }
    end
    table.sort(rows, function(a, b)
        return a[2] > b[2]
    end)
    for i = 1, math.min(PROFILE_ROWS, #rows) do
        katsa.log.write('log', ('  %4.1f%% %s'):format(rows[i][2] / total * 100, rows[i][1]), 'perf')
    end
end

function PerfLog:trackScene(now)
    local scene = require('source.engine.core.runtime').activeScene
    scene = scene and scene()
    if scene ~= self.scene then
        self.scene, self.sceneStarted, self.profiled = scene, now, false
        if self.profile then
            self:finishProfile()
        end
    end
    local age = now - self.sceneStarted
    if not self.profiled and not self.profile and age > PROFILE_DELAY then
        self:startProfile()
        self.profiled = true
    elseif self.profile and age > PROFILE_DELAY + PROFILE_LENGTH then
        self:finishProfile()
    end
end

-- `timings` is Runtime.timings after the frame; `frameMs` the whole frame including the wait.
function PerfLog:sample(timings, frameMs)
    local now = katsa.timer.getTime()
    self.started = self.started or now
    self.frames = self.frames + 1
    for _, key in ipairs({ 'events', 'update', 'draw', 'present', 'sleep' }) do
        self.sum[key] = (self.sum[key] or 0) + timings[key]
    end
    self.worst = math.max(self.worst, frameMs)
    self:trackScene(now)
    if now - self.started < WINDOW then
        return
    end
    local n = self.frames
    local stats = self.stats or {}
    katsa.log.write(
        'log',
        ('perf: %.0f fps, frame %.1f ms (worst %.0f) | events %.1f update %.1f draw %.1f present %.1f '
            .. 'sleep %.1f | drawcalls %s (batched %s) canvas switches %s shader switches %s'):format(
            n / (now - self.started),
            (now - self.started) / n * 1000,
            self.worst,
            self.sum.events / n,
            self.sum.update / n,
            self.sum.draw / n,
            self.sum.present / n,
            self.sum.sleep / n,
            tostring(stats.drawcalls),
            tostring(stats.drawcallsbatched),
            tostring(stats.canvasswitches),
            tostring(stats.shaderswitches)
        ),
        'perf'
    )
    self.frames, self.started, self.sum, self.worst = 0, now, {}, 0
end

return PerfLog
