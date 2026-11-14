-- Performance regression suite. It compares deterministic render counters (draw calls, triangles,
-- shadow work, Lua heap) of a fixed set of scenes with recorded budgets. Counters do not depend
-- on the machine, so a failure means the workload grew (a bug or a feature), not that the
-- sandbox is slow. Frame times are measured and shown, never enforced.
--
--   --test-perf     compare with validation/tests/performance/budgets.lua (fails on growth)
--   --perf-record   measure and rewrite budgets.lua (use after an intended change)
--
-- Both write validation/logs/perf.html (bars: budget vs current) and perf.md.
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

local WARMUP, SAMPLE = 60, 30
-- Counters that fail the test when they grow beyond `tolerance` (relative) plus `slack` (absolute).
local counters = {
    { 'drawCalls', 0.10, 3 },
    { 'objects', 0.10, 3 },
    { 'mainTriangles', 0.10, 500 },
    { 'shadowDrawCalls', 0.15, 3 },
    { 'shadowTriangles', 0.15, 500 },
    { 'shadowCasterSubmissions', 0.15, 3 },
    { 'depthPrepassDrawCalls', 0.10, 3 },
    { 'lights', 0.0, 0 },
    { 'luaKB', 0.20, 512 },
}
-- Each case loads a scene and samples it after WARMUP frames. `after` continues the same scene.
local cases = {
    { name = 'lights', scene = 'lights' },
    { name = 'shadows', scene = 'shadows' },
    { name = 'graphicsLab', scene = 'graphicsLab' },
    { name = 'particles', scene = 'particles' },
    { name = 'ribbonLab', scene = 'ribbonLab' },
    { name = 'shaderLab', scene = 'shaderLab' },
    { name = 'surfaceGallery', scene = 'surfaceGallery' },
    { name = 'platformer', scene = 'platformer' },
    { name = 'stareShooter', scene = 'stareShooter' },
    {
        name = 'multiplayerCars: on foot',
        scene = 'multiplayerCars',
        prepare = function(host)
            host.demo:host('Perf', 47900 + math.floor(os.clock() * 100) % 90, { separate = false })
        end,
        followUp = {
            name = 'multiplayerCars: in car',
            prepare = function(host)
                host.demo.server.game.bot.sightRadius = 0
                host.demo:changeCar()
            end,
        },
    },
}

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.mode = 'check'
    self.index, self.frame, self.rows = 0, 0, {}
    return self
end

function Tests:update() end

local function measure(host)
    local renderer = host.world and host.world._activeRenderer
    local stats = renderer and renderer.stats or {}
    local shadows = renderer and renderer.shadows
    local out = {
        drawCalls = stats.drawCalls,
        objects = stats.objects,
        mainTriangles = stats.mainTriangles,
        shadowDrawCalls = stats.shadowDrawCalls,
        shadowTriangles = stats.shadowTriangles or shadows and shadows.triangles,
        shadowCasterSubmissions = stats.shadowCasterSubmissions,
        depthPrepassDrawCalls = stats.depthPrepassDrawCalls,
        lights = stats.lights,
    }
    collectgarbage()
    collectgarbage()
    out.luaKB = math.floor(collectgarbage('count'))
    for key, value in pairs(out) do
        out[key] = math.floor(value + 0.5)
    end
    return out
end

function Tests:begin(case)
    if self.host then
        self.host:release()
        self.host = nil
    end
    self.current, self.frame = case, 0
    self.timing = { update = 0, draw = 0, n = 0 }
    self.host = require('source.game.runtime.application').new(self.manager, case.scene)
    self.host:load()
    if case.prepare then
        case.prepare(self.host)
    end
end

function Tests:draw()
    if self.finished then
        return
    end
    if not self.current then
        self:begin(cases[1])
        self.index = 1
    end
    local host = self.host
    local t0 = os.clock()
    host:update(1 / 60, 1 / 60)
    local t1 = os.clock()
    host:draw()
    local t2 = os.clock()
    self.frame = self.frame + 1
    if self.frame > WARMUP then
        local timing = self.timing
        timing.update, timing.draw, timing.n = timing.update + (t1 - t0), timing.draw + (t2 - t1), timing.n + 1
    end
    if self.frame < WARMUP + SAMPLE then
        return
    end
    local case = self.current
    local values = measure(host)
    values.updateMs = self.timing.update / self.timing.n * 1000
    values.drawMs = self.timing.draw / self.timing.n * 1000
    self.rows[#self.rows + 1] = { name = case.name, values = values }
    if case.followUp then
        local follow = case.followUp
        follow.scene = case.scene
        local previousPrepare = follow.prepare
        -- The same scene continues: seat the player, then warm up again without reloading.
        self.current = follow
        self.frame = 0
        self.timing = { update = 0, draw = 0, n = 0 }
        previousPrepare(host)
        return
    end
    local nextCase = cases[self.index + 1]
    if nextCase then
        self.index = self.index + 1
        self:begin(nextCase)
        return
    end
    host:release()
    self.host = nil
    self.finished = true
    self:finish()
end

local function loadBudgets()
    local ok, budgets = pcall(require, 'validation.tests.performance.budgets')
    return ok and budgets or {}
end

local function writeBudgets(rows)
    local lines = { '-- Written by `--perf-record`. Counters are machine independent; do not edit by hand.', 'return {' }
    for _, row in ipairs(rows) do
        local parts = {}
        for _, counter in ipairs(counters) do
            parts[#parts + 1] = ('%s = %d'):format(counter[1], row.values[counter[1]] or 0)
        end
        lines[#lines + 1] = ("    ['%s'] = { %s },"):format(row.name, table.concat(parts, ', '))
    end
    lines[#lines + 1] = '}'
    local file = assert(io.open('validation/tests/performance/budgets.lua', 'wb'))
    file:write(table.concat(lines, '\n'), '\n')
    file:close()
end

local function report(rows, budgets, verdicts)
    os.execute('mkdir -p validation/logs')
    local html = {
        '<!doctype html><meta charset="utf-8"><title>Katsa performance</title>',
        '<style>body{font:14px sans-serif;margin:24px;background:#10151c;color:#dde}table{border-collapse:collapse}',
        'td,th{padding:3px 10px;text-align:right}th:first-child,td:first-child{text-align:left}',
        '.bar{display:inline-block;height:9px;background:#4a90d9}.ok{color:#7c7}.grew{color:#f77;font-weight:bold}',
        '.less{color:#fc6}h2{margin:22px 0 6px}</style><h1>Katsa performance counters</h1>',
        '<p>Bars: current value against the budget (grey tick). Frame times are information only.</p>',
    }
    local md = { '# Katsa performance counters', '' }
    for _, row in ipairs(rows) do
        local budget = budgets[row.name] or {}
        html[#html + 1] = '<h2>' .. row.name .. ('</h2><table><tr><th>counter</th><th>budget</th><th>now</th><th></th><th>change</th></tr>')
        md[#md + 1] = '## ' .. row.name
        md[#md + 1] = '| counter | budget | now | change |'
        md[#md + 1] = '| --- | ---: | ---: | ---: |'
        for _, counter in ipairs(counters) do
            local key = counter[1]
            local now, was = row.values[key] or 0, budget[key]
            local change = was and was > 0 and (now - was) / was * 100 or 0
            local state = verdicts[row.name .. '/' .. key] or 'ok'
            local width = math.min(260, math.floor(now / math.max(now, was or 1, 1) * 260))
            html[#html + 1] = ('<tr><td>%s</td><td>%s</td><td class="%s">%d</td><td><span class="bar" style="width:%dpx"></span></td><td class="%s">%+.1f%%</td></tr>'):format(
                key, was and tostring(was) or '-', state, now, width, state, change)
            md[#md + 1] = ('| %s | %s | %d | %+.1f%% |'):format(key, was and tostring(was) or '-', now, change)
        end
        html[#html + 1] = ('</table><small>update %.2f ms, draw %.2f ms (this machine)</small>'):format(row.values.updateMs, row.values.drawMs)
        md[#md + 1] = ('update %.2f ms, draw %.2f ms (this machine)'):format(row.values.updateMs, row.values.drawMs)
        md[#md + 1] = ''
    end
    local function save(path, lines)
        local file = io.open(path, 'wb')
        if file then
            file:write(table.concat(lines, '\n'), '\n')
            file:close()
        end
    end
    save('validation/logs/perf.html', html)
    save('validation/logs/perf.md', md)
end

function Tests:finish()
    local budgets = loadBudgets()
    local verdicts, failures = {}, 0
    print(('%-26s %-24s %9s %9s %8s'):format('scene', 'counter', 'budget', 'now', 'change'))
    for _, row in ipairs(self.rows) do
        local budget = budgets[row.name]
        for _, counter in ipairs(counters) do
            local key, tolerance, slack = counter[1], counter[2], counter[3]
            local now = row.values[key] or 0
            local was = budget and budget[key]
            local change = was and was > 0 and (now - was) / was * 100 or 0
            local state = 'ok'
            if self.mode == 'check' and was then
                if now > was * (1 + tolerance) + slack then
                    state, failures = 'grew', failures + 1
                    self:check(false, ('%s: %s grew from %d to %d (+%.1f%%)'):format(row.name, key, was, now, change))
                elseif now < was * (1 - tolerance) - slack then
                    state = 'less'
                end
            end
            verdicts[row.name .. '/' .. key] = state
            if was ~= now or state ~= 'ok' then
                print(('%-26s %-24s %9s %9d %+7.1f%% %s'):format(row.name, key, was and tostring(was) or '-', now, change, state))
            end
        end
        if not budget and self.mode == 'check' then
            self:check(false, row.name .. ' has no budget: run --perf-record')
        else
            print(('PERF %-26s update %.2f ms  draw %.2f ms  (information only)'):format(row.name, row.values.updateMs, row.values.drawMs))
        end
    end
    report(self.rows, budgets, verdicts)
    if self.mode == 'record' then
        writeBudgets(self.rows)
        print('Budgets written: validation/tests/performance/budgets.lua')
    else
        self:check(failures == 0, 'No performance counter grew past its budget')
        print('Report: validation/logs/perf.html')
    end
    print('PASSED ' .. self.count .. ' perf checks')
    katsa.event.quit()
end

return Tests
