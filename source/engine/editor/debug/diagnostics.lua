local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs

local D = {}

function D.open(workspace)
    if workspace.popup then
        workspace.popup:close(true)
    end
    workspace.selected = workspace.selected or workspace.scene.world.root
    local popup = require('source.engine.editor.panels.popup').new(
        workspace,
        { key = 'Diagnostics', kind = 'string', value = '', readOnly = true }
    )
    workspace.popup = popup
    local profile, journal = workspace.scene.manager.profiler, workspace.scene.manager.journal
    popup.title.text = 'CPU profiler / error journal'
    popup.message.text = 'CPU wall-clock timings; GPU time is not measured.'
    local y = 0

    local function button(text, fn, x, width)
        popup.ui:button({
            position = { x or 0, 4, 0, y },
            size = { width or 1, -8, 0, 34 },
            text = text,
            fontSize = 13,
            onPress = fn,
        }, popup.body)
    end
    local function row(buttons)
        for index, entry in ipairs(buttons) do
            button(entry[1], entry[2], (index - 1) / #buttons, 1 / #buttons)
        end
        y = y + 38
    end
    local function exportRecording(format)
        local recording = profile.recording or profile.lastRecording
        if not recording or #recording.rows == 0 then
            popup.message.text = 'Record some frames first.'
            return
        end
        local ok, path = pcall(profile.save, recording, format)
        popup.message.text = ok and ('Saved ' .. path) or ('Export failed: ' .. tostring(path))
    end
    row({
        {
            profile.enabled and 'Profiler: ON' or 'Profiler: OFF',
            function()
                profile.enabled = not profile.enabled
                D.open(workspace)
            end,
        },
        {
            profile:isRecording() and 'Stop recording' or 'Record session',
            function()
                if profile:isRecording() then
                    local recording = profile:stopRecording()
                    profile.lastRecording = recording
                else
                    profile:startRecording({
                        scene = workspace.scene.zone,
                        started = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                    })
                end
                D.open(workspace)
            end,
        },
    })
    row({
        {
            'Export JSON',
            function()
                exportRecording('json')
            end,
        },
        {
            'Export CSV',
            function()
                exportRecording('csv')
            end,
        },
        {
            'Clear',
            function()
                profile:clear()
                journal:clear()
                D.open(workspace)
            end,
        },
        {
            'Refresh',
            function()
                D.open(workspace)
            end,
        },
    })
    local summary = profile:summary()
    local frame = summary.frame
    popup.ui:text({
        position = { 0, 8, 0, y },
        size = { 1, -16, 0, 74 },
        text = string.format(
            'Frame %.2f ms avg (%.0f FPS) | p95 %.2f | p99 %.2f | worst %.2f | 1%% low %.0f FPS | '
                .. 'spikes %d\nMemory: Lua %.0f KiB / textures %.2f MiB%s',
            frame.meanMilliseconds,
            frame.fps,
            frame.p95Milliseconds,
            frame.p99Milliseconds,
            frame.worstMilliseconds,
            frame.onePercentLowFps,
            frame.spikes,
            profile.luaKiB or 0,
            (profile.textureBytes or 0) / 1048576,
            profile:isRecording() and ('\nRecording: ' .. #profile.recording.rows .. ' frames')
                or ''
        ),
        fontSize = 12,
        align = 'left',
    }, popup.body)
    y = y + 78
    -- Last frames as bars (red above the 60 Hz budget).
    local rows = profile:rows()
    local shown = math.min(#rows, 120)
    local peak = 1000 / 30
    for index = 1, shown do
        local ms = rows[#rows - shown + index].ms
        peak = math.max(peak, ms)
    end
    popup.ui:container({
        position = { 0, 8, 0, y },
        size = { 1, -16, 0, 60 },
        backgroundColor = { 0.02, 0.03, 0.05 },
    }, popup.body)
    for index = 1, shown do
        local ms = rows[#rows - shown + index].ms
        popup.ui:container({
            position = { (index - 1) / 120, 8, 0, y + 60 - 60 * ms / peak },
            size = { 1 / 120, 0, 0, 60 * ms / peak },
            backgroundColor = ms > 1000 / 60 and { 0.95, 0.35, 0.3 } or { 0.3, 0.8, 0.5 },
        }, popup.body)
    end
    y = y + 68
    for _, task in ipairs(profile:getRunning()) do
        popup.ui:text({
            position = { 0, 8, 0, y },
            size = { 1, -16, 0, 20 },
            text = string.format('RUNNING  %s  %.2f s', task.name, task.seconds),
            fontSize = 13,
            textColor = { 1, 0.82, 0.4 },
            align = 'left',
        }, popup.body)
        y = y + 24
    end
    local top = summary.stages[1] and summary.stages[1].meanMilliseconds or 1
    for _, stage in ipairs(summary.stages) do
        popup.ui:text({
            position = { 0, 8, 0, y },
            size = { 1, -16, 0, 32 },
            text = string.format(
                '%s  %.2f ms avg | p95 %.2f | peak %.2f | %.0f%%',
                stage.name,
                stage.meanMilliseconds,
                stage.p95Milliseconds,
                stage.peakMilliseconds,
                stage.share * 100
            ),
            fontSize = 12,
            align = 'left',
        }, popup.body)
        popup.ui:container({
            position = { 0, 8, 0, y + 34 },
            size = { math.min(1, stage.meanMilliseconds / top), -16, 0, 6 },
            backgroundColor = { 0.3, 0.65, 0.95 },
        }, popup.body)
        y = y + 48
    end
    y = y + 8
    for i = #journal.entries, 1, -1 do
        local e = journal.entries[i]
        popup.ui:text({
            position = { 0, 8, 0, y },
            size = { 1, -16, 0, 96 },
            text = e.system
                .. ' | '
                .. e.node
                .. ' '
                .. e.class
                .. '\n'
                .. e.script
                .. '\n'
                .. e.message,
            textScaled = true,
            maxTextSize = 12,
            align = 'left',
        }, popup.body)
        y = y + 100
    end
    popup.body.length = math.max(y, 120)
end

return D
