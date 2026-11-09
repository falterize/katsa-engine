-- TileMap: cells, autotiling, merged colliders, saving and drawing.
local TileSet = require('source.engine.tilemap.tileSet')
local Terrain = require('source.engine.tilemap.terrain')
local Layer = require('source.engine.tilemap.layer')
local Colliders = require('source.engine.tilemap.colliders')

local Tests = {}

function Tests.run(tester)
    local ground = {}
    for mask = 0, 15 do
        ground[mask] = mask
    end
    local set = TileSet.new({
        image = 'x.png',
        columns = 8,
        rows = 3,
        terrains = { ground = { tiles = ground, solid = true } },
        tiles = { [17] = { solid = true } },
    })
    local layer = Layer.new('Ground')
    for x = 0, 2 do
        Terrain.paint(layer, set, x, 0, 'ground')
    end
    Terrain.paint(layer, set, 1, 1, 'ground')
    -- Left end has only an east neighbour, the middle one has east, south and west.
    tester:check(
        layer:get(0, 0) == 2 and layer:get(1, 0) == 2 + 4 + 8 and layer:get(2, 0) == 8,
        'autotile picks tiles from the neighbour mask'
    )
    Terrain.paint(layer, set, 1, 1, nil)
    tester:check(layer:get(1, 0) == 2 + 8 and layer.count == 3, 'erasing a cell fixes its neighbours')
    local rects = Colliders.rects(layer, set)
    tester:check(#rects == 1 and rects[1].w == 3 and rects[1].h == 1, 'a run of solid cells is one collider')
    for x = 0, 2 do
        Terrain.paint(layer, set, x, 1, 'ground')
    end
    layer:set(5, 0, 17)
    rects = Colliders.rects(layer, set)
    tester:check(#rects == 2, 'equal runs stack into one rectangle, a gap starts another')
    local ids = {}
    for _, rect in ipairs(rects) do
        ids[#ids + 1] = rect.w .. 'x' .. rect.h
    end
    table.sort(ids)
    tester:check(ids[1] == '1x1' and ids[2] == '3x2', 'merged rectangles cover the cells exactly')

    -- The node: cells, solidity, colliders, save and load, and a real draw.
    local world = require('source.engine.world.world').new(tester.manager.resources:scope())
    local ui = world:create('World2D', { width = 320, height = 240 })
    local map = ui:create('TileMap', {
        tileSet = 'shared://tilesets/platformer.lua',
        cellSize = { 16, 16 },
        size = { 0, 320, 0, 240 },
    }, ui.content)
    map:fillTerrain(0, 10, 9, 12, 'ground', nil, ui)
    map:setCell(12, 9, 18)
    tester:check(map:isSolid(3, 11) and not map:isSolid(3, 5), 'the node reports solid cells')
    tester:check(map:tileProperty(12, 9, 'name') == 'crate', 'tile properties come from the tileset')
    ui:layout()
    local cx, cy = map:cellAt(map._x + 50, map._y + 170)
    tester:check(cx == 3 and cy == 10, 'cellAt maps a point to its cell')
    local ok, message = pcall(function()
        ui:layout()
        ui:draw()
    end)
    tester:check(ok, 'a tile map draws: ' .. tostring(message))
    ui:createPhysics({ gravity = { 0, 0 } })
    local body = ui:create('Body2D', { bodyType = 'Static', position = { 0, 0 } })
    local colliders = map:buildColliders(ui, body, { origin = { 0, 0 } })
    local rects = map:solidRects()
    tester:check(#colliders == #rects and #colliders > 0, 'buildColliders makes one box per merged rectangle')
    local again = map:buildColliders(ui, body, { origin = { 0, 0 } })
    tester:check(#again == #colliders and colliders[1].destroyed, 'building again replaces the previous colliders')
    local data = map:toData()
    local copy = ui:create('TileMap', { cellSize = { 16, 16 } }, ui.content)
    copy:loadData(data)
    tester:check(copy:getCell(9, 12) == map:getCell(9, 12) and copy:getCell(12, 9) == 18, 'saved cells load back')
    map:setLayerVisible('Ground', false)
    tester:check(select(1, pcall(function() ui:draw() end)), 'a hidden layer is skipped')
    ui:destroy()
end

return Tests
