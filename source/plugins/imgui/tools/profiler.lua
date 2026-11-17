-- Profiler window: CPU wall-clock stage timings, frame statistics, a frame-time graph, session
-- recording with JSON/CSV export, the loading phases and the error journal. GPU time is not
-- measured. Opened from the Tools menu or the Debug window.
local Profiler = { id = 'profiler', title = 'Profiler' }

local SHOWN = 120

function Profiler.new()
    return { message = nil }
end

local function export(profile, state, format)
    local recording = profile.recording or profile.lastRecording
    if not recording or #recording.rows == 0 then
        state.message = 'Record some frames first.'
        return
    end
    local ok, path = pcall(profile.save, recording, format)
    state.message = ok and ('Saved ' .. path) or ('Export failed: ' .. tostring(path))
end

local function controls(ig, scene, profile, journal, state)
    local _, enabled = ig.checkbox('Profiler enabled', profile.enabled)
    profile.enabled = enabled
    ig.sameLine()
    if ig.button(profile:isRecording() and 'Stop recording' or 'Record session') then
        if profile:isRecording() then
            profile.lastRecording = profile:stopRecording()
        else
            profile:startRecording({
                scene = scene.zone,
                loading = profile.loading,
                started = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            })
        end
    end
    if ig.button('Export JSON') then
        export(profile, state, 'json')
    end
    ig.sameLine()
    if ig.button('Export CSV') then
        export(profile, state, 'csv')
    end
    ig.sameLine()
    if ig.button('Clear') then
        profile:clear()
        journal:clear()
        state.message = nil
    end
    ig.textDisabled(state.message or 'CPU wall-clock timings; GPU time is not measured.')
end

local function loading(ig, profile)
    local info = profile.loading
    if info and info.phases and #info.phases > 0 and ig.collapsingHeader('Loading') then
        ig.text('%s: %.0f ms', tostring(info.scene), info.total or 0)
        for _, phase in ipairs(info.phases) do
            ig.text('  %-34s %.1f ms', phase.name, phase.ms)
        end
    end
end

local function frames(ig, profile, summary)
    local frame = summary.frame
    ig.text(
        'Frame %.2f ms avg (%.0f FPS) | p95 %.2f | p99 %.2f | worst %.2f | 1%% low %.0f FPS | spikes %d',
        frame.meanMilliseconds,
        frame.fps,
        frame.p95Milliseconds,
        frame.p99Milliseconds,
        frame.worstMilliseconds,
        frame.onePercentLowFps,
        frame.spikes
    )
    ig.text(
        'Memory: Lua %.0f KiB / textures %.2f MiB%s',
        profile.luaKiB or 0,
        (profile.textureBytes or 0) / 1048576,
        profile:isRecording() and (' | recording ' .. #profile.recording.rows .. ' frames') or ''
    )
    local rows = profile:rows()
    local shown = math.min(#rows, SHOWN)
    if shown > 1 then
        local values, peak = {}, 1000 / 30
        for index = 1, shown do
            local ms = rows[#rows - shown + index].ms
            values[index] = ms
            peak = math.max(peak, ms)
        end
        ig.plotHistogram('##frames', values, 'last frames (ms)', 0, peak, -1, 60)
    end
    for _, task in ipairs(profile:getRunning()) do
        ig.textColored(1, 0.82, 0.4, 1, 'RUNNING  %s  %.2f s', task.name, task.seconds)
    end
end

local function stages(ig, summary)
    if not ig.collapsingHeader('Stages', true) then
        return
    end
    local top = summary.stages[1] and summary.stages[1].meanMilliseconds or 1
    if ig.beginTable('stages', 5, nil, 0, 260) then
        ig.tableSetupColumn('Stage', 0, 220)
        ig.tableSetupColumn('avg ms', 0, 70)
        ig.tableSetupColumn('p95', 0, 70)
        ig.tableSetupColumn('peak', 0, 70)
        ig.tableSetupColumn('share', 0, 140)
        ig.tableHeadersRow()
        for _, stage in ipairs(summary.stages) do
            ig.tableNextRow()
            ig.tableNextColumn()
            ig.text(stage.name)
            ig.tableNextColumn()
            ig.text('%.2f', stage.meanMilliseconds)
            ig.tableNextColumn()
            ig.text('%.2f', stage.p95Milliseconds)
            ig.tableNextColumn()
            ig.text('%.2f', stage.peakMilliseconds)
            ig.tableNextColumn()
            ig.progressBar(
                math.min(1, stage.meanMilliseconds / top),
                -1,
                14,
                ('%.0f%%'):format(stage.share * 100)
            )
        end
        ig.endTable()
    end
end

local function errors(ig, journal)
    if #journal.entries == 0 or not ig.collapsingHeader('Error journal (' .. #journal.entries .. ')') then
        return
    end
    for index = #journal.entries, 1, -1 do
        local entry = journal.entries[index]
        ig.pushID(index)
        ig.textColored(1, 0.45, 0.4, 1, '%s | %s %s', entry.system, entry.node, entry.class)
        ig.textWrapped('%s\n%s', entry.script, entry.message)
        ig.separator()
        ig.popID()
    end
end

function Profiler.draw(ig, scene, state, host)
    local width, height = katsa.graphics.getDimensions()
    ig.setNextWindowPos(math.max(10, width - 620), 60)
    ig.setNextWindowSize(math.min(600, width - 20), math.min(620, height * 0.8))
    local visible, open = ig.begin('Profiler', true)
    if visible then
        local profile, journal = scene.manager.profiler, scene.manager.journal
        controls(ig, scene, profile, journal, state)
        ig.separator()
        local summary = profile:summary()
        loading(ig, profile)
        frames(ig, profile, summary)
        stages(ig, summary)
        errors(ig, journal)
    end
    ig.finish()
    if not open then
        host:close('profiler')
    end
end

return Profiler
