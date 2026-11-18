-- The ribbon under the menu bar: a row of category tabs (Home, Create, View, Assets) and, below
-- it, the big icon buttons of the active tab, grouped by thin dividers. Toggle buttons carry the
-- `on` tag while active. Items wrap onto more rows when the window is narrow (Flow), so no
-- button ever leaves the screen. Every button has a hover description (panels/tooltip) and a hint
-- in the status bar.
local Flow = require('../support.flow')
local Icons = require('../widgets.icons')
local Kit = require('../support.kit')
local Importer = require('../../core.importer')
local Menus = require('../support.menus')

local Toolbar = {}
Toolbar.__index = Toolbar

local ROW, GAP, PAD = 64, 4, 5
local MENU, TABS = 28, 26 -- menu row, then the tab row, above the ribbon content
local BIG, ICON = 58, 32

Toolbar.TABS = {
    { 'home', 'Home' },
    { 'create', 'Create' },
    { 'view', 'View' },
    { 'assets', 'Assets' },
}

function Toolbar.create(state, ui, parent)
    local self = setmetatable({ state = state, ui = ui, items = {}, toggles = {}, refreshers = {}, hints = {}, tabButtons = {} }, Toolbar)
    self.frame = parent
    self.tab = 'home'
    local tooltip = state.panels.tooltip
    local group -- the tab the next items belong to
    local function add(item)
        item.tab = group
        self.items[#self.items + 1] = item
        return item
    end
    local function describe(node, text)
        self.hints[#self.hints + 1] = { node = node, text = text }
        tooltip:register(node, text)
    end

    -- A big button: the icon on top, the caption under it.
    local function big(text, icon, action, hint, width, gap)
        width = width or BIG
        local button = Kit.button(ui, parent, '', width, ROW - 6, action, 'tool')
        Icons.add(ui, button, icon, (width - ICON) / 2, 6, ICON)
        local caption = Kit.label(ui, button, text, {
            position = { 0, 0, 0, ROW - 6 - 20 },
            size = { 1, 0, 0, 16 },
            align = 'center',
            fontSize = 12,
        }, 'text')
        describe(button, hint)
        add({ w = width, gap = gap, nodes = { { node = button, dx = 0, dy = 2 } } })
        return button, caption
    end
    local function toggle(text, icon, action, isOn, hint, width, gap)
        local button, caption = big(text, icon, action, hint, width, gap)
        self.toggles[#self.toggles + 1] = { button = button, isOn = isOn }
        return button, caption
    end
    local function divider()
        local line = Kit.make(ui, 'Frame', { size = { 0, 1, 0, ROW - 12 }, interactable = false }, parent, 'sep')
        add({ w = 1, gap = 6, nodes = { { node = line, dx = 0, dy = 6 } } })
    end
    -- Several small labelled number fields stacked in one column of the ribbon.
    local function stack(rows, labelWidth, fieldWidth, gap)
        local nodes = {}
        for index, row in ipairs(rows) do
            local dy = 3 + (index - 1) * 20
            local text = Kit.label(ui, parent, row.label, { size = { 0, labelWidth, 0, 18 }, align = 'right', fontSize = 12 }, 'muted')
            local box, refresh = Kit.numberField(ui, parent, { size = { 0, fieldWidth, 0, 18 }, fontSize = 12 }, row.get, function(value)
                row.set(value)
                state:savePrefs()
            end, 0.0001)
            self.refreshers[#self.refreshers + 1] = refresh
            describe(box, row.hint)
            tooltip:register(text, row.hint)
            nodes[#nodes + 1] = { node = text, dx = 0, dy = dy }
            nodes[#nodes + 1] = { node = box, dx = labelWidth + 4, dy = dy }
        end
        add({ w = labelWidth + 4 + fieldWidth, gap = gap, nodes = nodes })
    end
    local function snapRow(label, key, hint)
        return {
            label = label,
            hint = hint,
            get = function()
                return state.snap[key]
            end,
            set = function(value)
                state.snap[key] = value
            end,
        }
    end

    -- Tab buttons.
    for index, entry in ipairs(Toolbar.TABS) do
        local name = entry[1]
        local button = Kit.button(ui, parent, entry[2], 72, TABS - 2, function()
            self.tab = name
            state.dock.barWidth = nil -- the ribbon may change height: lay the dock out again
        end, 'tab')
        button.position = { 0, PAD + (index - 1) * 76, 0, MENU }
        self.tabButtons[#self.tabButtons + 1] = button
        self.toggles[#self.toggles + 1] = { button = button, isOn = function()
            return self.tab == name
        end }
    end

    ---------------------------------------------------------------- Home
    group = 'home'
    big('Undo', 'undo', function()
        state.undo:undo()
        state:refresh()
    end, 'Undo the last change (Ctrl+Z)')
    big('Redo', 'redo', function()
        state.undo:redo()
        state:refresh()
    end, 'Redo (Ctrl+Y)')
    divider()
    local TOOL_ICONS = { Select = 'select', Move = 'move', Rotate = 'rotate', Scale = 'scale' }
    local TOOL_HINTS = {
        Select = 'Select objects: click, Ctrl+click adds, drag a rectangle (Q)',
        Move = 'Move the selection with the gizmo (W)',
        Rotate = 'Rotate the selection with the gizmo (E)',
        Scale = 'Scale the selection with the gizmo (R)',
    }
    for index, name in ipairs(state.TOOLS) do
        toggle(name, TOOL_ICONS[name], function()
            state:setTool(name)
        end, function()
            return state.tool == name
        end, TOOL_HINTS[name], nil, index == 1 and 6 or 0)
    end
    divider()
    local _, spaceCaption = toggle('World', 'world', function()
        state.space = state.space == 'World' and 'Local' or 'World'
    end, function()
        return state.space == 'Local'
    end, 'Gizmo space: World axes or the object\'s Local axes (X)', nil, 6)
    self.spaceCaption = spaceCaption
    local _, pivotCaption = toggle('Center', 'center', function()
        state.pivotMode = state.pivotMode == 'Center' and 'Origin' or 'Center'
    end, function()
        return state.pivotMode == 'Origin'
    end, 'Pivot: the centre of the selection or each object\'s own origin')
    self.pivotCaption = pivotCaption
    divider()
    toggle('Snap', 'snap', function()
        state.snap.enabled = not state.snap.enabled
        state:savePrefs()
    end, function()
        return state.snap.enabled
    end, 'Snap moves, rotations and scales to the steps on the right', nil, 6)
    stack({
        snapRow('Move', 'move', 'Move step in units'),
        snapRow('Rotate', 'rotate', 'Rotation step in degrees'),
        snapRow('Scale', 'scale', 'Scale step'),
    }, 44, 52)
    toggle('Surface', 'surface', function()
        state.snap.surface = not state.snap.surface
    end, function()
        return state.snap.surface
    end, 'Drop moved objects onto the surface under the pointer')

    ---------------------------------------------------------------- Create
    group = 'create'
    local createButton
    createButton = big('Create', 'add', function()
        local x, y = createButton:getAbsolutePosition()
        local _, h = createButton:getAbsoluteSize()
        state:openCreate(x, y + h)
    end, 'Open the list of everything you can create (Shift+A)')
    local function quick(label, text, icon, hint)
        big(text, icon, function()
            for _, entry in ipairs(Menus.createItems(state)) do
                if entry.label == label and entry.run then
                    entry.run()
                    return
                end
            end
        end, hint)
    end
    divider()
    quick('Point light', 'Point', 'light', 'Add a point light in front of the camera')
    quick('Spot light', 'Spot', 'light', 'Add a spot light in front of the camera')
    quick('Sun', 'Sun', 'light', 'Add a directional light (sun)')
    divider()
    big('Import', 'import', function()
        Importer.dialog(state)
    end, 'Choose files on your computer to import: models, images, audio, fonts, anything (you can also drop files on the window)')

    ---------------------------------------------------------------- View
    group = 'view'
    toggle('Grid', 'grid', function()
        state.grid:setVisible(not state.grid.visible)
        state:savePrefs()
    end, function()
        return state.grid.visible
    end, 'Show or hide the ground grid (G)')
    stack({
        {
            label = 'Cell',
            hint = 'Grid cell size in units',
            get = function()
                return state.grid.cell
            end,
            set = function(value)
                state.grid:setCell(value)
            end,
        },
        {
            label = 'Major',
            hint = 'A bright line every N cells',
            get = function()
                return state.grid.settings.major
            end,
            set = function(value)
                state.grid:setMajor(value)
            end,
        },
        {
            label = 'Extent',
            hint = 'How many cells the grid covers in each direction',
            get = function()
                return state.grid.settings.count
            end,
            set = function(value)
                state.grid:setCount(value)
            end,
        },
    }, 44, 52)
    divider()
    local environment = state.world.environment
    toggle('Lights', 'light', function()
        state.lightViz.enabled = not state.lightViz.enabled
    end, function()
        return state.lightViz.enabled
    end, 'Show the light markers: icon, radius and range', nil, 6)
    toggle('Shadows', 'shadow', function()
        environment.shadows.enabled = not environment.shadows.enabled
    end, function()
        return environment.shadows.enabled
    end, 'Turn shadows on or off in the viewport')
    toggle('Wireframe', 'wire', function()
        environment.debug.wireframe = not environment.debug.wireframe
    end, function()
        return environment.debug.wireframe
    end, 'Draw every mesh as lines')
    divider()
    big('Frame', 'frame', function()
        local nodes = state.selection:items()
        state:frame(#nodes > 0 and nodes or state.level.children)
    end, 'Move the camera to see the selection, or everything (F)', nil, 6)
    big('All', 'cube', function()
        state:frame(state.level.children)
    end, 'Move the camera to see the whole level (Home)')

    ---------------------------------------------------------------- Assets
    group = 'assets'
    local _, targetCaption = toggle('Scene', 'folder', function()
        state.importTarget = state.importTarget == 'shared' and 'scene' or 'shared'
    end, function()
        return state.importTarget == 'shared'
    end, 'Where imports go: Scene copies the file into this level\'s assets folder (scene://); Shared points at a file of the project assets (shared://)', 72)
    self.targetCaption = targetCaption
    big('Scene folder', 'folder', function()
        state.panels.browser:openSceneFolder()
    end, 'Show the level\'s own assets folder in the file browser; drop models and images there', 72, 6)
    big('Import', 'import', function()
        Importer.dialog(state)
    end, 'Choose files on your computer to import (or drop them on the window)', nil, 6)
    big('Files', 'folder', function()
        state.panels.browser:show('Files')
    end, 'Open the file browser')
    return self
end

-- Positions the tab row and the active tab's items for a bar `width` wide; returns the height.
function Toolbar:relayout(width)
    local shown = {}
    for _, item in ipairs(self.items) do
        local visible = item.tab == nil or item.tab == self.tab
        for _, part in ipairs(item.nodes) do
            part.node.visible = visible
        end
        if visible then
            shown[#shown + 1] = item
        end
    end
    local positions, height = Flow.place(shown, width, GAP, ROW, PAD)
    for index, item in ipairs(shown) do
        local at = positions[index]
        for _, part in ipairs(item.nodes) do
            part.node.position = { 0, at.x + part.dx, 0, MENU + TABS + at.y + (part.dy or 0) }
        end
    end
    return MENU + TABS + height
end

local function over(node, mx, my)
    local x, y = node:getAbsolutePosition()
    local w, h = node:getAbsoluteSize()
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function Toolbar:update()
    local ui, state = self.ui, self.state
    local mx, my = (katsa.mouse.getX() - ui.offsetX) / ui.scale, (katsa.mouse.getY() - ui.offsetY) / ui.scale
    local hint
    for _, entry in ipairs(self.hints) do
        if entry.node.visible ~= false and over(entry.node, mx, my) then
            hint = entry.text
            break
        end
    end
    state.hint = hint
    for _, entry in ipairs(self.toggles) do
        local on = entry.isOn()
        if entry.on ~= on then
            entry.on = on
            if on then
                entry.button:addTag('on')
            else
                entry.button:removeTag('on')
            end
            state.styler:apply(entry.button)
        end
    end
    if self.spaceCaption.text ~= state.space then
        self.spaceCaption.text = state.space
    end
    if self.pivotCaption.text ~= state.pivotMode then
        self.pivotCaption.text = state.pivotMode
    end
    local target = state.importTarget == 'shared' and 'Shared' or 'Scene'
    if self.targetCaption.text ~= target then
        self.targetCaption.text = target
    end
    for _, refresh in ipairs(self.refreshers) do
        refresh()
    end
end

return Toolbar
