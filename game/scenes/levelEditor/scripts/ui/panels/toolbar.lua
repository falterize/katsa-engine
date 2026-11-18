-- Tool strip under the menu bar: undo/redo, tools, space/pivot, snap with editable steps, surface
-- snap and grid. Items wrap onto more rows when the window is narrow (Flow), so no
-- button ever leaves the screen. Toggle buttons carry the `on` tag while active.
local Flow = require('../flow')
local Icons = require('../widgets.icons')
local Kit = require('../kit')

local Toolbar = {}
Toolbar.__index = Toolbar

local ROW, GAP, PAD = 26, 4, 5
local MENU = 28 -- height of the menu row above the tool strip

function Toolbar.create(state, ui, parent)
    local self = setmetatable({ state = state, ui = ui, items = {}, toggles = {}, refreshers = {}, hints = {} }, Toolbar)
    self.frame = parent
    local function add(item)
        self.items[#self.items + 1] = item
        return item
    end
    -- A button with a pixel icon at its left; the label is padded with spaces to clear the icon.
    local function tool(text, width, action, gap, icon, hint)
        local button = Kit.button(ui, parent, icon and ('     ' .. text) or text, width + (icon and 18 or 0), ROW, action, 'tool')
        if icon then
            button.align = 'left'
            Icons.add(ui, button, icon, 6, 5)
        end
        self.hints[#self.hints + 1] = { node = button, text = hint or text }
        add({ w = width + (icon and 18 or 0), gap = gap, nodes = { { node = button, dx = 0 } } })
        return button
    end
    local function toggle(text, width, action, isOn, gap, icon, hint)
        local button = tool(text, width, action, gap, icon, hint)
        self.toggles[#self.toggles + 1] = { button = button, isOn = isOn }
        return button
    end
    local function field(label, labelWidth, fieldWidth, key, minimum, hint, gap)
        local text = Kit.label(ui, parent, label, { size = { 0, labelWidth, 0, ROW }, align = 'right' }, 'muted')
        local box, refresh = Kit.numberField(ui, parent, { size = { 0, fieldWidth, 0, ROW - 2 } }, function()
            return state.snap[key]
        end, function(value)
            state.snap[key] = value
            state:savePrefs()
        end, minimum or 0.0001)
        self.refreshers[#self.refreshers + 1] = refresh
        self.hints[#self.hints + 1] = { node = box, text = hint }
        add({ w = labelWidth + 4 + fieldWidth, gap = gap, nodes = { { node = text, dx = 0 }, { node = box, dx = labelWidth + 4, dy = 1 } } })
    end
    -- A numeric field bound to getter/setter functions (the grid settings).
    local function gridField(label, labelWidth, fieldWidth, get, set, hint, gap)
        local text = Kit.label(ui, parent, label, { size = { 0, labelWidth, 0, ROW }, align = 'right' }, 'muted')
        local box, refresh = Kit.numberField(ui, parent, { size = { 0, fieldWidth, 0, ROW - 2 } }, get, function(value)
            set(value)
            state:savePrefs()
        end, 0.0001)
        self.refreshers[#self.refreshers + 1] = refresh
        self.hints[#self.hints + 1] = { node = box, text = hint }
        add({ w = labelWidth + 4 + fieldWidth, gap = gap, nodes = { { node = text, dx = 0 }, { node = box, dx = labelWidth + 4, dy = 1 } } })
    end

    tool('Undo', 48, function()
        state.undo:undo()
        state:refresh()
    end, nil, 'undo', 'Undo the last change (Ctrl+Z)')
    tool('Redo', 48, function()
        state.undo:redo()
        state:refresh()
    end, nil, 'redo', 'Redo (Ctrl+Y)')
    local TOOL_ICONS = { Select = 'select', Move = 'move', Rotate = 'rotate', Scale = 'scale' }
    local TOOL_HINTS = {
        Select = 'Select objects: click, Ctrl+click adds, drag a rectangle (Q)',
        Move = 'Move the selection with the gizmo (W)',
        Rotate = 'Rotate the selection with the gizmo (E)',
        Scale = 'Scale the selection with the gizmo (R)',
    }
    for index, name in ipairs(state.TOOLS) do
        toggle(name, 60, function()
            state:setTool(name)
        end, function()
            return state.tool == name
        end, index == 1 and 12 or 0, TOOL_ICONS[name], TOOL_HINTS[name])
    end
    toggle('World', 56, function()
        state.space = state.space == 'World' and 'Local' or 'World'
    end, function()
        return state.space == 'Local'
    end, 12, 'world', 'Gizmo space: World or Local (X)').text = '     World'
    self.spaceButton = self.toggles[#self.toggles].button
    toggle('Center', 56, function()
        state.pivotMode = state.pivotMode == 'Center' and 'Origin' or 'Center'
    end, function()
        return state.pivotMode == 'Origin'
    end, nil, 'center', 'Pivot: the selection centre or each object origin')
    self.pivotButton = self.toggles[#self.toggles].button
    toggle('Snap', 48, function()
        state.snap.enabled = not state.snap.enabled
        state:savePrefs()
    end, function()
        return state.snap.enabled
    end, 12, 'snap', 'Snap moves, rotations and scales to the steps on the right')
    field('Move', 36, 50, 'move', nil, 'Move step in units')
    field('Rotate', 44, 44, 'rotate', nil, 'Rotation step in degrees')
    field('Scale', 38, 44, 'scale', nil, 'Scale step')
    toggle('Surface', 62, function()
        state.snap.surface = not state.snap.surface
    end, function()
        return state.snap.surface
    end, nil, 'surface', 'Drop moved objects onto the surface under the pointer')
    toggle('Grid', 44, function()
        state.grid:setVisible(not state.grid.visible)
        state:savePrefs()
    end, function()
        return state.grid.visible
    end, 12, 'grid', 'Show or hide the ground grid (G)')
    gridField('Cell', 32, 44, function()
        return state.grid.cell
    end, function(value)
        state.grid:setCell(value)
    end, 'Grid cell size in units')
    gridField('Major', 40, 36, function()
        return state.grid.settings.major
    end, function(value)
        state.grid:setMajor(value)
    end, 'Bright line every N cells')
    gridField('Size', 34, 44, function()
        return state.grid.settings.count
    end, function(value)
        state.grid:setCount(value)
    end, 'How many cells the grid covers in each direction')
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

local function over(node, mx, my)
    local x, y = node:getAbsolutePosition()
    local w, h = node:getAbsoluteSize()
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function Toolbar:update()
    local ui = self.ui
    local mx, my = (katsa.mouse.getX() - ui.offsetX) / ui.scale, (katsa.mouse.getY() - ui.offsetY) / ui.scale
    local hint
    for _, entry in ipairs(self.hints) do
        if over(entry.node, mx, my) then
            hint = entry.text
            break
        end
    end
    self.state.hint = hint
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
    if self.spaceButton.text ~= '     ' .. space then
        self.spaceButton.text = '     ' .. space
    end
    if self.pivotButton.text ~= '     ' .. pivot then
        self.pivotButton.text = '     ' .. pivot
    end
    for _, refresh in ipairs(self.refreshers) do
        refresh()
    end
end

return Toolbar
