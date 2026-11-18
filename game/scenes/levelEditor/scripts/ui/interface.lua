-- Editor UI entry: top toolbar, Workspace tree (left), Properties (right) and the status bar.
-- Only the viewport between the panels stays free, so a click there reaches the 3D world.
local Browser = require('./panels.browser')
local Properties = require('./panels.properties')
local Theme = require('./theme')
local Tree = require('./panels.tree')

local Interface = {}

local function bar(state, ui)
    local top = ui:container({
        name = 'Toolbar',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 0, Theme.top },
        backgroundColor = Theme.bar,
        zIndex = 6,
    }, ui.content)
    local x = 6
    local function button(text, width, action, isOn)
        local node = ui:button({
            position = { 0, x, 0, 4 },
            size = { 0, width, 0, Theme.top - 8 },
            text = text,
            fontSize = 13,
            backgroundColor = Theme.button,
        }, top)
        node:connect('press', action)
        x = x + width + 4
        return node
    end
    local content = state
    button('Undo', 48, function() content.undo:undo(); content:refresh() end)
    button('Redo', 48, function() content.undo:redo(); content:refresh() end)
    x = x + 10
    for _, tool in ipairs(state.TOOLS) do
        local node = button(tool, 60, function() content:setTool(tool) end)
        state.toolButtons[tool] = node
    end
    x = x + 10
    button('Duplicate', 76, function() content.ops:duplicate(content.selection:items()) end)
    button('Delete', 56, function() content.ops:delete(content.selection:items()) end)
    button('Group', 56, function() content.ops:group(content.selection:items()) end)
    button('Ungroup', 64, function()
        local node = content.selection:primary()
        if node then
            local ok, message = content.ops:ungroup(node)
            if not ok then
                content:notify(message)
            end
        end
    end)
    state.moveInto = button('Move into...', 90, function()
        content.panels.tree:armReparent(true)
        content:notify('Click the new parent in the Workspace (Level = top)')
    end)
    x = x + 10
    local snap = button('Snap', 48, function() end)
    snap:connect('press', function()
        content.snap.enabled = not content.snap.enabled
    end)
    local space = button('World', 56, function() end)
    space:connect('press', function()
        content.space = content.space == 'World' and 'Local' or 'World'
        space.text = content.space
    end)
    local pivot = button('Center', 56, function() end)
    pivot:connect('press', function()
        content.pivotMode = content.pivotMode == 'Center' and 'Origin' or 'Center'
        pivot.text = content.pivotMode
    end)
    button('Grid', 44, function() content.grid:setVisible(not content.grid.visible) end)
    button('Frame all', 70, function() content:frame(content.level.children) end)
end

function Interface.create(state)
    local ui = state.scene.root:find('World3D/World2D')
    state.toolButtons = {}
    bar(state, ui)
    state.panels = {
        tree = Tree.create(state, ui),
        properties = Properties.create(state, ui),
        browser = Browser.create(state, ui),
    }
    ui:container({
        name = 'StatusBar',
        position = { 0, 0, 1, -Theme.bottom },
        size = { 1, 0, 0, Theme.bottom },
        backgroundColor = Theme.bar,
        zIndex = 6,
    }, ui.content)
    state.status = ui:create('Label', {
        name = 'Status',
        position = { 0, 10, 1, -Theme.bottom + 3 },
        size = { 1, -20, 0, 20 },
        fontSize = 13,
        align = 'left',
        textColor = Theme.text,
        interactable = false,
        zIndex = 7,
    }, ui.content)
end

return Interface
