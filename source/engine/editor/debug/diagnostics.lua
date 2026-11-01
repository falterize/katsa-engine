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

    local function button(text, fn)
        popup.ui:button({
            position = { 0, 4, 0, y },
            size = { 1, -8, 0, 34 },
            text = text,
            fontSize = 13,
            onPress = fn,
        }, popup.body)
        y = y + 38
    end
    button(profile.enabled and 'Profiler: ON (disable)' or 'Profiler: OFF (enable)', function()
        profile.enabled = not profile.enabled
        D.open(workspace)
    end)
    button('Refresh observations', function()
        D.open(workspace)
    end)
    button('Clear timings and journal', function()
        profile:clear()
        journal:clear()
        D.open(workspace)
    end)
    popup.ui:text({
        position = { 0, 8, 0, y },
        size = { 1, -16, 0, 42 },
        text = string.format(
            'Memory: Lua %.0f KiB / textures %.2f MiB (sampled every 30 frames)',
            profile.luaKiB or 0,
            (profile.textureBytes or 0) / 1048576
        ),
        fontSize = 12,
        align = 'left',
    }, popup.body)
    y = y + 46
    local keys = {}
    for key in pairs(profile.samples) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local sample = profile.samples[key]
        popup.ui:text({
            position = { 0, 8, 0, y },
            size = { 1, -16, 0, 42 },
            text = string.format(
                '%s: %.2f ms / avg %.2f / peak %.2f',
                key,
                sample.last,
                sample.average,
                sample.peak
            ),
            fontSize = 12,
            align = 'left',
        }, popup.body)
        y = y + 46
    end
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
