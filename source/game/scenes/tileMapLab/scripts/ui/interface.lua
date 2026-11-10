local ipairs = require('source.engine.math.array').ipairs
local Theme = require('source.engine.ui.theme')
local Content = require('../content')

local Interface = {}

local BRUSHES = {
    { 'Ground (autotile)', 'ground' },
    { 'Brick', 17 },
    { 'Crate', 18 },
    { 'Water', 16 },
    { 'Spike', 19 },
    { 'Coin', 20 },
    { 'Ladder', 21 },
    { 'Flag', 23 },
}

function Interface.create(state)
    local ui = state.scene.ui
    local cell = Content.CELL
    state.map = ui:create('TileMap', {
        name = 'LabMap',
        tileSet = 'shared://tilesets/platformer.lua',
        cellSize = { cell, cell },
        position = { 0.5, 100, 0.5, 0 },
        anchorPoint = { 0.5, 0.5 },
        size = { 0, Content.COLUMNS * cell, 0, Content.ROWS * cell },
        backgroundColor = { 0.05, 0.08, 0.14 },
        backgroundTransparency = 0,
        interactable = true,
    }, ui.content)
    state.map:getLayer('Ground')
    state.map:getLayer('Decor')
    state.map:fillTerrain(0, 12, 29, 14, 'ground', 'Ground', ui)
    state.map:fillTerrain(8, 9, 12, 10, 'ground', 'Ground', ui)
    state.map:setCell(10, 8, 20, 'Decor')
    local painting
    state.map:connect('cellPointer', function(phase, x, y)
        if phase == 'press' then
            painting = true
        elseif phase == 'release' then
            painting = false
        end
        if painting and phase ~= 'release' then
            local erase = state.erasing or katsa.keyboard.isDown('lctrl', 'rctrl')
            state:paint(x, y, erase)
        end
    end)
    state.status = ui:text({
        position = { 0.5, 100, 0.5, 250 },
        anchorPoint = { 0.5, 0 },
        size = { 0, Content.COLUMNS * cell, 0, 28 },
        text = 'Pick a tile on the left and paint. Hold Ctrl or use the Erase brush to remove.',
        textScaled = true,
        maxTextSize = 16,
        backgroundColor = Theme.panel,
        backgroundTransparency = 0.2,
    }, ui.content)
    local panel = ui:container({
        name = 'TilePalette',
        position = { 0, 12, 0.5, 0 },
        anchorPoint = { 0, 0.5 },
        size = { 0, 190, 0, 56 + (#BRUSHES + 4) * 40 },
        backgroundColor = Theme.panel,
    }, ui.content)
    require('source.engine.ui.widgets.collapsible').create(state.scene, panel, 'TileMap / palette')
    local y = 8
    local function button(text, press)
        do
            local node = ui:button({
                position = { 0, 8, 0, y },
                size = { 1, -16, 0, 34 },
                text = text,
            }, panel)
            if press then
                node:connect('press', press)
            end
        end
        y = y + 40
    end
    for _, brush in ipairs(BRUSHES) do
        button(brush[1], function()
            state.brush = brush[2]
            state.erasing = false
        end)
    end
    button('Erase brush', function()
        state.erasing = true
    end)
    button('Show collision boxes', function()
        state.showColliders = not state.showColliders
        state:refreshOverlay()
    end)
    button('Decor layer ON/OFF', function()
        local layer = state.map:getLayer('Decor')
        state.map:setLayerVisible('Decor', not layer.visible)
    end)
    button('Save / load snapshot', function()
        if state.snapshot then
            state.map:loadData(state.snapshot)
            state.snapshot = nil
            state:refreshOverlay()
        else
            state.snapshot = state.map:toData()
        end
    end)
end

return Interface
