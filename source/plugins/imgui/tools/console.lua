-- Console window (F1): the tail of katsa.log with a level filter, a text filter, JSON/CSV export
-- and Clear. The legacy panel is source/engine/debug/consolePanel.lua.
local Export = require('source.engine.debug.logExport')

local Console = { id = 'console', title = 'Console', key = 'f1' }

local LINES = 500
local LEVELS = { { 'All', nil }, { 'Warn+', 'warn' }, { 'Errors', 'error' } }
local COLORS = { log = { 0.85, 0.85, 0.85 }, warn = { 1, 0.82, 0.4 }, error = { 1, 0.45, 0.4 } }

function Console.new()
    return { level = nil, filter = '', message = nil, shown = {}, count = -1, key = nil, stick = true }
end

-- Rebuilds the visible lines only when entries arrived or a filter changed.
local function refresh(state)
    local count = katsa.log.count()
    local key = tostring(state.level) .. '|' .. state.filter
    if count == state.count and key == state.key then
        return
    end
    state.count, state.key = count, key
    local needle = state.filter:lower()
    local lines = {}
    for _, entry in ipairs(katsa.log.entries(state.level)) do
        local text = entry.message:gsub('\n.*', ' ...')
        if needle == '' or text:lower():find(needle, 1, true) then
            lines[#lines + 1] = { level = entry.level, text = ('%8.2f  %s'):format(entry.time, text) }
        end
    end
    local first = math.max(1, #lines - LINES + 1)
    state.shown = { unpack(lines, first, #lines) }
    state.grew = true
end

local function save(state, format)
    local ok, result = pcall(function()
        return Export.save(katsa.log.entries(state.level), format)
    end)
    state.message = ok and ('Saved ' .. result) or ('Export failed: ' .. tostring(result))
end

function Console.draw(ig, scene, state, host)
    local width, height = katsa.graphics.getDimensions()
    ig.setNextWindowPos(12, 12)
    ig.setNextWindowSize(math.max(320, width - 24), math.max(200, height * 0.45))
    local visible, open = ig.begin('Console', true)
    if visible then
        refresh(state)
        for index, item in ipairs(LEVELS) do
            if index > 1 then
                ig.sameLine()
            end
            if ig.button(item[1]) then
                state.level, state.message = item[2], nil
            end
        end
        ig.sameLine()
        if ig.button('JSON') then
            save(state, 'json')
        end
        ig.sameLine()
        if ig.button('CSV') then
            save(state, 'csv')
        end
        ig.sameLine()
        if ig.button('Clear') then
            katsa.log.clear()
            state.message = nil
        end
        ig.sameLine()
        ig.setNextItemWidth(200)
        local _
        _, state.filter = ig.inputText('Filter', state.filter)
        ig.text(
            state.message
                or ('%d entries | %d warnings | %d errors'):format(
                    katsa.log.count(),
                    katsa.log.count('warn'),
                    katsa.log.count('error')
                )
        )
        if ig.beginChild('lines', 0, 0, true) then
            for _, line in ipairs(state.shown) do
                local color = COLORS[line.level] or COLORS.log
                ig.textColored(color[1], color[2], color[3], 1, '%s', line.text)
            end
            -- Follow new lines while the view sits at the bottom.
            if state.grew and state.stick then
                ig.scrollToEnd()
            end
            state.grew = false
            state.stick = ig.scrollY() >= ig.scrollMaxY() - 4
        end
        ig.endChild()
    end
    ig.finish()
    if not open then
        host:close('console')
    end
end

return Console
