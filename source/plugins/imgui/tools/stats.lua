-- Stats window: the engine's metrics (the same definitions the legacy panel reads), a filter, a
-- history graph for the selected row and the CSV export. Opened by F3 / the Stats button.
local Stats = { id = 'stats', title = 'Stats' }

local HISTORY = 240
local INTERVAL = 0.1

local function format(definition, value)
    local unit = definition.unit
    local text = value == math.floor(value) and math.abs(value) < 1e9 and ('%d'):format(value)
        or ('%.2f'):format(value)
    return unit and unit ~= '0/1' and (text .. ' ' .. unit) or text
end

-- Reads every definition at a fixed rate and keeps a short history of each.
local function sample(scene, state)
    local statistics = scene.statistics
    local now = katsa.timer.getTime()
    if now < state.next then
        return
    end
    state.next = now + INTERVAL
    katsa.graphics.getStats(statistics.graphics)
    for _, definition in ipairs(statistics.panel.definitions) do
        local value = definition.read(statistics.context)
        state.values[definition.id] = value
        if type(value) == 'number' then
            local list = state.history[definition.id]
            if not list then
                list = {}
                state.history[definition.id] = list
            end
            list[#list + 1] = value
            if #list > HISTORY then
                table.remove(list, 1)
            end
        end
    end
end

function Stats.new()
    return { next = 0, values = {}, history = {}, filter = '', selected = nil }
end

function Stats.draw(ig, scene, state)
    -- The first size keeps the lower left (on-screen joystick) free on small screens.
    local width, height = katsa.graphics.getDimensions()
    ig.setNextWindowPos(10, 60)
    ig.setNextWindowSize(math.min(460, width * 0.45), math.min(560, height * 0.5))
    local visible, open = ig.begin('Stats', true)
    if visible then
        sample(scene, state)
        local statistics = scene.statistics
        ig.textWrapped(statistics.panel.header.text)
        if ig.button('Export logs (30 s)') then
            statistics:export(30)
        end
        ig.sameLine()
        ig.setNextItemWidth(180)
        local _
        _, state.filter = ig.inputText('Filter', state.filter)
        ig.separator()
        local needle = state.filter:lower()
        local height = state.selected and 220 or 0
        if ig.beginTable('metrics', 2, nil, 0, -height) then
            ig.tableSetupColumn('Metric', 0, 260)
            ig.tableSetupColumn('Value', 0, 150)
            ig.tableHeadersRow()
            for _, definition in ipairs(statistics.panel.definitions) do
                local value = state.values[definition.id]
                if value ~= nil and (needle == '' or definition.label:lower():find(needle, 1, true)) then
                    ig.tableNextRow()
                    ig.tableNextColumn()
                    ig.pushID(definition.id)
                    if ig.selectable(definition.label, state.selected == definition.id) then
                        state.selected = state.selected ~= definition.id and definition.id or nil
                    end
                    ig.popID()
                    ig.tableNextColumn()
                    ig.text(type(value) == 'number' and format(definition, value) or tostring(value))
                end
            end
            ig.endTable()
        end
        local list = state.selected and state.history[state.selected]
        if list and #list > 1 then
            local low, high = math.huge, -math.huge
            for _, value in ipairs(list) do
                low, high = math.min(low, value), math.max(high, value)
            end
            ig.plotLines('##history', list, ('%s: %.2f .. %.2f'):format(state.selected, low, high), low, high, -1, 200)
        end
    end
    ig.finish()
    if not open then
        scene.showStats = false
    end
end

return Stats
