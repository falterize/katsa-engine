-- Properties panel: the rows of the primary selected node come from the engine's own inspector
-- list (`Properties.list`), so any node class, including plugin nodes, shows up without editor
-- code. With several nodes selected only the rows every node shares are shown, and an edit is
-- written to all of them. Edits go through `ops:setProperty` (the engine's validation, one undo
-- step). The panel rebuilds when the selection changes or after an edit, never every frame.
local Properties = require('source.engine.editor.inspectors.properties')
local Groups = require('../propertyGroups')
local Kit = require('../kit')

local Panel = {}
Panel.__index = Panel

local ROW = 24
local HIDDEN = { parent = true, ['add attribute'] = true }

function Panel.create(state, ui, frame)
    local self = setmetatable({ state = state, ui = ui, widgets = {}, frame = frame, open = {} }, Panel)
    self.title = Kit.label(ui, frame, 'Properties', {
        position = { 0, 8, 0, 4 },
        size = { 1, -16, 0, 20 },
        fontSize = 14,
    }, 'title')
    self.name = Kit.make(ui, 'TextBox', {
        name = 'NameField',
        position = { 0, 8, 0, 28 },
        size = { 1, -16, 0, 24 },
        fontSize = 14,
        placeholderText = 'Name',
        visible = false,
    }, frame, 'field')
    self.name:connect('submitted', function(_, text)
        local node = state.selection:primary()
        if node and state.ops:rename(node, text) then
            self.dirty = true
        end
    end)
    self.scroll = Kit.make(ui, 'ScrollFrame', {
        name = 'PropertyList',
        position = { 0, 4, 0, 58 },
        size = { 1, -8, 1, -62 },
        canvasSize = { 0, 0, 0, 0 },
        scrollBarThickness = 6,
    }, frame, 'list')
    self.dirty = true
    state.selection:onChange(function()
        self.dirty = true
    end)
    return self
end

-- Rows shared by every selected node, in the primary node's order.
local function sharedRows(nodes)
    local rows = Properties.list(nodes[#nodes])
    if #nodes == 1 then
        return rows
    end
    local others = {}
    for index = 1, #nodes - 1 do
        local map = {}
        for _, row in ipairs(Properties.list(nodes[index])) do
            map[row.key] = row
        end
        others[index] = map
    end
    local result = {}
    for _, row in ipairs(rows) do
        local shared = true
        for _, map in ipairs(others) do
            local other = map[row.key]
            if not other or other.kind ~= row.kind then
                shared = false
            end
        end
        if shared then
            result[#result + 1] = row
        end
    end
    return result
end

function Panel:commit(key, component, value, vector)
    local state = self.state
    local ok, message = state.ops:setProperty(state.selection:items(), key, component, value, vector)
    if not ok then
        state:notify(message or 'The value was refused')
    end
    self.dirty = true
end

local function format(value)
    if type(value) == 'number' then
        return ('%.4g'):format(value)
    end
    return tostring(value)
end

function Panel:rebuild()
    for _, widget in ipairs(self.widgets) do
        if not widget.destroyed then
            widget:destroy()
        end
    end
    self.widgets = {}
    local state, ui = self.state, self.ui
    local nodes = state.selection:items()
    local primary = nodes[#nodes]
    self.name.visible = primary ~= nil
    if not primary then
        self.title.text = 'Properties (nothing selected)'
        self.scroll.canvasSize = { 0, 0, 0, 0 }
        return
    end
    self.title.text = #nodes == 1 and ('Properties: ' .. primary.className)
        or ('Properties: %d nodes'):format(#nodes)
    self.name.text = primary.name or ''
    local function add(widget)
        self.widgets[#self.widgets + 1] = widget
        return widget
    end
    local y = 0
    local function drawRow(row)
        local key, kind = row.key, row.kind
        local editable = not row.readOnly and not HIDDEN[key]
        local shown = not HIDDEN[key]
            and (kind == 'boolean' or kind == 'number' or kind == 'string' or kind == 'vector' or kind == 'node')
        if shown then
            add(Kit.label(ui, self.scroll, key, {
                position = { 0, 6, 0, y },
                size = { 0.4, -6, 0, ROW },
            }, 'muted'))
            local at, width = { 0.4, 0, 0, y }, { 0.6, -8, 0, ROW - 2 }
            if kind == 'boolean' and editable then
                local button = add(Kit.make(ui, 'Button', {
                    position = at,
                    size = width,
                    text = row.value and 'true' or 'false',
                    fontSize = 13,
                }, self.scroll, 'tool', row.value and 'on' or nil))
                button:connect('press', function()
                    self:commit(key, nil, not row.value)
                end)
            elseif row.options and editable then
                local button = add(Kit.make(ui, 'Button', {
                    position = at,
                    size = width,
                    text = tostring(row.value),
                    fontSize = 13,
                }, self.scroll, 'tool'))
                button:connect('press', function()
                    -- A scrolling list (searchable when long) instead of cycling by clicks.
                    local items = {}
                    for _, option in ipairs(row.options) do
                        items[#items + 1] = {
                            label = tostring(option),
                            checked = option == row.value,
                            run = function()
                                self:commit(key, nil, option)
                            end,
                        }
                    end
                    local x, y = button:getAbsolutePosition()
                    local _, h = button:getAbsoluteSize()
                    state.panels.popup:show(items, x, y + h + 1, {
                        width = button:getAbsoluteSize(),
                        search = #items > 10,
                    })
                end)
            elseif kind == 'vector' and editable then
                local count = #row.value
                local isColor = key:lower():find('color', 1, true) and (count == 3 or count == 4)
                local swatch = isColor and 24 or 0
                if isColor then
                    local c = row.value
                    local scale = (c[1] > 1 or c[2] > 1 or c[3] > 1) and 255 or 1
                    local button = add(Kit.make(ui, 'Button', {
                        position = { 0.4, 0, 0, y },
                        size = { 0, 22, 0, ROW - 2 },
                        text = '',
                        backgroundColor = { c[1] / scale, c[2] / scale, c[3] / scale, 1 },
                    }, self.scroll, 'swatch'))
                    button:connect('press', function()
                        local x, py = button:getAbsolutePosition()
                        state.panels.colorPicker:show(row, math.max(2, x - 190), py)
                    end)
                end
                for index = 1, count do
                    local box = add(Kit.make(ui, 'TextBox', {
                        position = { 0.4 + 0.6 * (index - 1) / count, swatch * (1 - (index - 1) / count), 0, y },
                        size = { 0.6 / count, -4 - swatch / count, 0, ROW - 2 },
                        fontSize = 12,
                        text = format(row.value[index]),
                    }, self.scroll, 'field'))
                    box:connect('submitted', function(_, text)
                        self:commit(key, index, text)
                    end)
                end
            elseif (kind == 'number' or kind == 'string') and editable then
                local box = add(Kit.make(ui, 'TextBox', {
                    position = at,
                    size = width,
                    fontSize = 13,
                    text = format(row.value),
                }, self.scroll, 'field'))
                box:connect('submitted', function(_, text)
                    self:commit(key, nil, kind == 'number' and text or text)
                end)
            else
                local text = kind == 'vector' and '' or format(row.value)
                if kind == 'node' then
                    text = row.value and tostring(row.value.name or row.value.className) or 'none'
                elseif kind == 'vector' then
                    local parts = {}
                    for index, item in ipairs(row.value) do
                        parts[index] = format(item)
                    end
                    text = table.concat(parts, ', ')
                end
                add(Kit.label(ui, self.scroll, text, { position = at, size = width }, 'muted'))
            end
            y = y + ROW
        end
    end
    local visibleRows = {}
    for _, row in ipairs(sharedRows(nodes)) do
        local kind = row.kind
        if not HIDDEN[row.key] and (kind == 'boolean' or kind == 'number' or kind == 'string' or kind == 'vector' or kind == 'node') then
            visibleRows[#visibleRows + 1] = row
        end
    end
    for _, group in ipairs(Groups.group(visibleRows)) do
        local open = self.open[group.name]
        if open == nil then
            open = not Groups.COLLAPSED[group.name]
        end
        local header = add(Kit.make(ui, 'Button', {
            position = { 0, 2, 0, y },
            size = { 1, -4, 0, ROW },
            text = ('%s  %s  (%d)'):format(open and 'v' or '>', group.name, #group.rows),
            align = 'left',
            fontSize = 13,
        }, self.scroll, 'tab'))
        header:connect('press', function()
            self.open[group.name] = not open
            self.dirty = true
        end)
        y = y + ROW + 2
        if open then
            for _, row in ipairs(group.rows) do
                drawRow(row)
            end
            y = y + 4
        end
    end
    self.scroll.canvasSize = { 0, 0, 0, y }
    state.styler:apply(self.scroll)
end

function Panel:update()
    if self.dirty then
        self.dirty = false
        self:rebuild()
    end
end

return Panel
