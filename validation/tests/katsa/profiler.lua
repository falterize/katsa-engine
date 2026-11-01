-- Profiler: scopes, frame history, percentiles and session export.
return function(T)
    katsa = katsa or require('source.katsa')
    local Profiler = require('source.engine.debug.profiler')
    local p = Profiler.new()
    T.check(p:begin() == nil, 'profiler: disabled profilers hand out no stamps')
    p:sample('X', 1)
    T.check(next(p.samples) == nil, 'profiler: disabled profilers store nothing')

    p.enabled = true
    p.textureBytes, p.luaKiB = 0, 0
    -- Fake clock: 100 frames of 10 ms, one of 100 ms; stage "A" is 4 ms, "B" appears every other frame.
    local clock = 0
    p:frame(clock)
    for frame = 1, 100 do
        p:sample('A', 4)
        if frame % 2 == 0 then
            p:sample('B', 2)
        end
        clock = clock + (frame == 50 and 0.1 or 0.01)
        p:frame(clock)
    end
    local summary = p:summary()
    T.check(summary.frame.frames == 100, 'profiler: frames are recorded in the history')
    T.check(
        math.abs(summary.frame.worstMilliseconds - 100) < 1e-6,
        'profiler: worst frame is found'
    )
    T.check(math.abs(summary.frame.p50Milliseconds - 10) < 1e-6, 'profiler: median frame time')
    T.check(summary.frame.spikes == 1, 'profiler: a frame over twice the median is a spike')
    T.check(summary.frame.onePercentLowFps < 15, 'profiler: 1% low reflects the slowest frame')
    T.check(
        summary.stages[1].name == 'A' and math.abs(summary.stages[1].meanMilliseconds - 4) < 1e-6,
        'profiler: stages are sorted by mean time'
    )
    T.check(
        math.abs(summary.stages[2].meanMilliseconds - 1) < 1e-6,
        'profiler: frames without a stage count as zero'
    )

    local results = { p:scope('Scoped', function(a, b)
        return a + b, 'ok'
    end, 1, 2) }
    T.check(
        results[1] == 3 and results[2] == 'ok' and p.samples.Scoped.count == 1,
        'profiler: scope returns the results and times the stage'
    )
    T.check(not pcall(p.scope, p, 'Boom', function()
        error('x')
    end) and p.samples.Boom.count == 1, 'profiler: scope times and rethrows errors')

    -- Named tasks that span frames and nest.
    local clockNow = 100
    local realTime = katsa.timer.getTime
    katsa.timer.getTime = function()
        return clockNow
    end
    local t = Profiler.new()
    T.check(t:start('off') == nil, 'profiler: start is a no-op while disabled')
    t.enabled = true
    t:start('generating map')
    clockNow = 100.25
    t:start('generating map')
    local running = t:getRunning()
    T.check(
        #running == 1 and running[1].depth == 2 and math.abs(running[1].seconds - 0.25) < 1e-9,
        'profiler: a running task is listed with its elapsed time and nesting depth'
    )
    clockNow = 100.5
    local inner = t:stop('generating map')
    clockNow = 101
    local outer = t:stop('generating map')
    T.check(
        math.abs(inner - 250) < 1e-6 and math.abs(outer - 1000) < 1e-6 and #t:getRunning() == 0,
        'profiler: stops match the most recent start'
    )
    T.check(t.samples['generating map'].count == 2, 'profiler: each stop becomes a sample')
    katsa.log.clear()
    t:stop('never started')
    t:stop('never started')
    T.check(katsa.log.count('warn') == 1, 'profiler: a stop without a start warns once')
    katsa.timer.getTime = realTime

    -- Recording and export.
    local q = Profiler.new()
    q:startRecording({ scene = 'demo', started = '2026-01-01T00:00:00Z' })
    local now = 0
    q:frame(now)
    for _ = 1, 5 do
        q:sample('Update', 3)
        q:sample('Draw, "quoted"', 5)
        now = now + 0.016
        q:frame(now)
    end
    local recording = q:stopRecording()
    T.check(
        #recording.rows == 5 and not q:isRecording(),
        'profiler: a recording captures every frame'
    )
    local csv = Profiler.export(recording, 'csv')
    local lines = {}
    for line in csv:gmatch('[^\r\n]+') do
        lines[#lines + 1] = line
    end
    T.check(
        #lines == 6 and lines[1]:find('frame_ms') and lines[1]:find('"Draw, ""quoted"""'),
        'profiler: CSV has a header and one line per frame with quoted names'
    )
    local json = require('vendor.json').decode(Profiler.export(recording, 'json'))
    T.check(
        json.schema == 1
            and json.scene == 'demo'
            and #json.rows == 5
            and json.columns[5] == 'Draw, "quoted"'
            and json.rows[1][6] == 3,
        'profiler: JSON carries columns, summary and compact rows'
    )
    T.check(
        not pcall(Profiler.export, recording, 'xml'),
        'profiler: unknown export format is rejected'
    )
end
