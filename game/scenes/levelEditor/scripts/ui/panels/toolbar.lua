-- Tool strip under the menu bar: undo/redo, tools, space/pivot, snap with editable steps, surface
-- snap, grid and play-test. Items wrap onto more rows when the window is narrow (Flow), so no
-- button ever leaves the screen. Toggle buttons carry the `on` tag while active.
local Flow = require('../flow')
local Kit = require('../kit')

local Toolbar = {}
Toolbar.__index = Toolbar

local ROW, GAP, PAD = 26, 4, 5
local MENU = 28 -- height of the menu row above the tool strip

function Toolbar.create(state, ui, parent)
    local self = setmetatable({ state = state, ui = ui, items = {}, toggles = {}, refreshers = {} }, Toolbar)
    self.frame = parent
    local function add(item)
        self.items[#self.items + 1] = item
        return item
    end
    local function tool(text, width, action, gap)
        local button = Kit.button(ui, parent, text, width, ROW, action, 'tool')
        add({ w = width, gap = gap, nodes = { { node = button, dx = 0 } } })
        return button
    end
    local function toggle(text, width, action, isOn, gap)
        local button = tool(text, width, action, gap)
        self.toggles[#self.toggles + 1] = { button = button, isOn = isOn }
        return button
    end
    local function field(label, labelWidth, fieldWidth, key, minimum)
        local text = Kit.label(ui, parent, label, { size = { 0, labelWidth, 0, ROW }, align = 'right' }, 'muted')
        local box, refresh = Kit.numberField(ui, parent, { size = { 0, fieldWidth, 0, ROW - 2 } }, function()
            return state.snap[key]
        end, function(value)
            state.snap[key] = value
            state:savePrefs()
        end, 0.0001)
        self.refreshers[#self.refreshers + 1] = refresh
        add({ w = labelWidth + 4 + fieldWidth, nodes = { { node = text, dx = 0 }, { node = box, dx = labelWidth + 4, dy = 1 } } })
    end

    tool('Undo', 48, function()
        state.undo:undo()
        state:refresh()
    end)
    tool('Redo', 48, function()
        state.undo:redo()
        state:refresh()
    end)
    for index, name in ipairs(state.TOOLS) do
        toggle(name, 60, function()
            state:setTool(name)
        end, function()
            return state.tool == name
        end, index == 1 and 12 or 0)
    end
    toggle('World', 56, function()
        state.space = state.space == 'World' and 'Local' or 'World'
    end, function()
        return state.space == 'Local'
    end, 12).text = 'World'
    self.spaceButton = self.toggles[#self.toggles].button
    toggle('Center', 56, function()
        state.pivotMode = state.pivotMode == 'Center' and 'Origin' or 'Center'
    end, function()
        return state.pivotMode == 'Origin'
    end)
    self.pivotButton = self.toggles[#self.toggles].button
    toggle('Snap', 48, function()
        state.snap.enabled = not state.snap.enabled
        state:savePrefs()
    end, function()
        return state.snap.enabled
    end, 12)
    field('Move', 36, 50, 'move')
    field('Rotate', 44, 44, 'rotate')
    field('Scale', 38, 44, 'scale')
    toggle('Surface', 62, function()
        state.snap.surface = not state.snap.surface
    end, function()
        return state.snap.surface
    end)
    toggle('Grid', 44, function()
        state.grid:setVisible(not state.grid.visible)
        state:savePrefs()
    end, function()
        return state.grid.visible
    end, 12)
    toggle('Play', 52, function()
        state:togglePlay()
    end, function()
        return state.playing == true
    end, 12)
    return self
end

-- Positions every item for a bar `width` wide (below the menu row); returns the bar height.
function Toolbar:relayout(width)
    local positions, height = Flow.place(self.items, width, GAP, ROW, PAD)
    for index, item in ipairs(self.items) do
        local at = positions[index]
        for _, part in ipairs(item.nodes) do
            part.node.position = { 0, at.x + part.dx, 0, MENU + at.y + (part.dy or 0) }
        end
    end
    return MENU + height
end

function Toolbar:update()
    for _, entry in ipairs(self.toggles) do
        local on = entry.isOn()
        if entry.on ~= on then
            entry.on = on
            if on then
                entry.button:addTag('on')
            else
                entry.button:removeTag('on')
            end
            self.state.styler:apply(entry.button)
        end
    end
    local space, pivot = self.state.space, self.state.pivotMode
    if self.spaceButton.text ~= space then
        self.spaceButton.text = space
    end
    if self.pivotButton.text ~= pivot then
        self.pivotButton.text = pivot
    end
    for _, refresh in ipairs(self.refreshers) do
        refresh()
    end
end

return Toolbar
