-- Properties panel: the rows of the primary selected node come from the engine's own inspector
-- list (`Properties.list`), so any node class, including plugin nodes, shows up without editor
-- code. With several nodes selected only the rows every node shares are shown, and an edit is
-- written to all of them. Edits go through `ops:setProperty` (the engine's validation, one undo
-- step). The panel rebuilds when the selection changes or after an edit, never every frame.
local Properties = require('source.engine.editor.inspectors.properties')
local Theme = require('../theme')

local Panel = {}
Panel.__index = Panel

local ROW = 24
local HIDDEN = { parent = true, ['add attribute'] = true }

function Panel.create(state, ui)
    local self = setmetatable({ state = state, ui = ui, widgets = {} }, Panel)
    self.frame = ui:container({
        name = 'PropertiesPanel',
        position = { 1, 0, 0, Theme.top },
        anchorPoint = { 1, 0 },
        size = { 0, Theme.right, 1, -(Theme.top + Theme.bottom) },
        backgroundColor = Theme.panel,
        zIndex = 5,
    }, ui.content)
    self.title = ui:create('Label', {
        position = { 0, 8, 0, 4 },
        size = { 1, -16, 0, 20 },
        fontSize = 15,
        align = 'left',
        text = 'Properties',
        textColor = Theme.text,
        interactable = false,
    }, self.frame)
    self.name = ui:create('TextBox', {
        name = 'NameField',
        position = { 0, 8, 0, 28 },
        size = { 1, -16, 0, 24 },
        fontSize = 14,
        backgroundColor = Theme.field,
        placeholderText = 'Name',
        visible = false,
    }, self.frame)
    self.name:connect('submitted', function(_, text)
        local node = state.selection:primary()
        if node and state.ops:rename(node, text) then
            self.dirty = true
        end
    end)
    self.scroll = ui:scroll({
        name = 'PropertyList',
        position = { 0, 4, 0, 58 },
        size = { 1, -8, 1, -62 },
        canvasSize = { 0, 0, 0, 0 },
        scrollBarThickness = 6,
        backgroundColor = Theme.bar,
    }, self.frame)
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
    for _, row in ipairs(sharedRows(nodes)) do
        local key, kind = row.key, row.kind
        local editable = not row.readOnly and not HIDDEN[key]
        local shown = not HIDDEN[key]
            and (kind == 'boolean' or kind == 'number' or kind == 'string' or kind == 'vector' or kind == 'node')
        if shown then
            add(ui:create('Label', {
                position = { 0, 6, 0, y },
                size = { 0.4, -6, 0, ROW },
                fontSize = 13,
                align = 'left',
                text = key,
                textColor = Theme.dim,
                interactable = false,
            }, self.scroll))
            local at, width = { 0.4, 0, 0, y }, { 0.6, -8, 0, ROW - 2 }
            if kind == 'boolean' and editable then
                local button = add(ui:button({
                    position = at,
                    size = width,
                    text = row.value and 'true' or 'false',
                    fontSize = 13,
                    backgroundColor = row.value and Theme.buttonOn or Theme.button,
                }, self.scroll))
                button:connect('press', function()
                    self:commit(key, nil, not row.value)
                end)
            elseif row.options and editable then
                local button = add(ui:button({
                    position = at,
                    size = width,
                    text = tostring(row.value),
                    fontSize = 13,
                    backgroundColor = Theme.button,
                }, self.scroll))
                button:connect('press', function()
                    local list, index = row.options, 1
                    for position, option in ipairs(list) do
                        if option == row.value then
                            index = position
                        end
                    end
                    self:commit(key, nil, list[index % #list + 1])
                end)
            elseif kind == 'vector' and editable then
                local count = #row.value
                for index = 1, count do
                    local box = add(ui:create('TextBox', {
                        position = { 0.4 + 0.6 * (index - 1) / count, 0, 0, y },
                        size = { 0.6 / count, -4, 0, ROW - 2 },
                        fontSize = 12,
                        text = format(row.value[index]),
                        backgroundColor = Theme.field,
                    }, self.scroll))
                    box:connect('submitted', function(_, text)
                        self:commit(key, index, text)
                    end)
                end
            elseif (kind == 'number' or kind == 'string') and editable then
                local box = add(ui:create('TextBox', {
                    position = at,
                    size = width,
                    fontSize = 13,
                    text = format(row.value),
                    backgroundColor = Theme.field,
                }, self.scroll))
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
                add(ui:create('Label', {
                    position = at,
                    size = width,
                    fontSize = 13,
                    align = 'left',
                    text = text,
                    textColor = Theme.dim,
                    interactable = false,
                }, self.scroll))
            end
            y = y + ROW
        end
    end
    self.scroll.canvasSize = { 0, 0, 0, y }
end

function Panel:update()
    if self.dirty then
        self.dirty = false
        self:rebuild()
    end
end

return Panel
