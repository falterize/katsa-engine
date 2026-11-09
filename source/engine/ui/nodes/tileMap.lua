-- TileMap: a grid of cells drawn from a tileset, with layers, autotiling and collision.
--
--   local map = ui:create('TileMap', {
--       tileSet = 'shared://tilesets/platformer.lua', cellSize = { 32, 32 },
--       size = { 0, 640, 0, 360 },
--   })
--   map:setTerrain(3, 10, 'ground')                -- picks the edge tile from the neighbours
--   map:setCell(5, 9, 18)                          -- a plain tile id (a crate)
--   local x, y = map:cellAt(pointerX, pointerY)    -- cell under a screen point
--   map:buildColliders(ui, body, { origin = { 0, 0 } })   -- static boxes for the solid cells
--
-- Cells are (x, y) integers, y grows downward (the order of the image rows) and the cell (0, 0)
-- starts at the top-left corner of the node. A node draws only the cells that are inside its
-- rectangle and on screen, so a big map costs what it shows. The tileset (see tilemap/tileSet.lua)
-- decides which tiles are solid. `mapFile` loads cells saved with `toData`.
local Node = require('../../nodes')
local Layer = require('../../tilemap.layer')
local TileSet = require('../../tilemap.tileSet')
local Terrain = require('../../tilemap.terrain')
local Colliders = require('../../tilemap.colliders')

local Class = Node.define('TileMap', 'Frame')
Class.propertySchema = {
    tileSet = {
        hint = 'Lua file that returns the tileset: image, tile grid, solid tiles and terrains.',
    },
    mapFile = {
        hint = 'Lua file with saved cells (TileMap:toData). Loaded when it changes.',
    },
    cellSize = { hint = 'Size of one cell on screen, in UI pixels.' },
    pixelate = { hint = 'Sharp pixels instead of smoothing; right for pixel art.' },
}

local DEFAULT_LAYER = 'Ground'

function Class.initialize(self)
    self.cellSize = self.cellSize or { 16, 16 }
    self.tileSet = self.tileSet or ''
    self.mapFile = self.mapFile or ''
    self.pixelate = self.pixelate ~= false
    self.interactable = self.interactable == true
    self._layers, self._order = {}, {}
    self._quad = nil
end

-- Layers ---------------------------------------------------------------------------------

-- A layer by name, created (drawn after the existing ones) when missing and `create` is not false.
function Class:getLayer(name, create)
    name = name or DEFAULT_LAYER
    local layer = self._layers[name]
    if not layer and create ~= false then
        layer = Layer.new(name)
        self._layers[name] = layer
        self._order[#self._order + 1] = layer
    end
    return layer
end

function Class:layerNames()
    local names = {}
    for i, layer in ipairs(self._order) do
        names[i] = layer.name
    end
    return names
end

function Class:setLayerVisible(name, visible)
    self:getLayer(name).visible = visible ~= false
end

function Class:clear(name)
    if name then
        self:getLayer(name):clear()
    else
        for _, layer in ipairs(self._order) do
            layer:clear()
        end
    end
end

-- The loaded tileset (nil until `tileSet` names a readable file). Loaded again when the
-- property changes, which keeps the cells.
function Class:getTileSet(resources)
    local source = self.tileSet
    if source == '' or source == nil then
        return nil
    end
    if self._tileSetSource ~= source or self._tileSetRevision ~= TileSet.revision then
        self._tileSetRevision = TileSet.revision
        local ok, result
        if type(source) == 'table' then
            ok, result = pcall(TileSet.new, source)
        else
            ok, result = pcall(TileSet.load, resources, source)
        end
        if not ok and resources.store and resources.store.journal then
            resources.store.journal:record('Resources', tostring(result), self, tostring(source))
        end
        self._tileSetSource, self._tileSetObject = source, ok and result or nil
    end
    return self._tileSetObject
end

function Class:_resources()
    local ui = self._ui or self.ui or (self.getUI and self:getUI())
    return ui and ui.resources
end

-- Cells ----------------------------------------------------------------------------------

function Class:setCell(x, y, id, layer)
    self:getLayer(layer):set(math.floor(x), math.floor(y), id)
end

function Class:eraseCell(x, y, layer)
    self:setCell(x, y, nil, layer)
end

function Class:getCell(x, y, layer)
    local found = self:getLayer(layer, false)
    return found and found:get(math.floor(x), math.floor(y))
end

function Class:fill(x0, y0, x1, y1, id, layer)
    local target = self:getLayer(layer)
    for y = math.min(y0, y1), math.max(y0, y1) do
        for x = math.min(x0, x1), math.max(x0, x1) do
            target:set(x, y, id)
        end
    end
end

-- Paints a terrain cell (nil erases) and refreshes the tiles around it. Needs the tileset
-- (loaded on first draw, or pass the scene's `ui` to load it now).
function Class:setTerrain(x, y, terrain, layer, ui)
    local tileSet = assert(self:_tileSetFor(ui), 'setTerrain needs a loaded tileSet')
    Terrain.paint(self:getLayer(layer), tileSet, math.floor(x), math.floor(y), terrain)
end

-- Fills a rectangle with a terrain, then fixes the edges once.
function Class:fillTerrain(x0, y0, x1, y1, terrain, layer, ui)
    local tileSet = assert(self:_tileSetFor(ui), 'fillTerrain needs a loaded tileSet')
    local target = self:getLayer(layer)
    for y = math.min(y0, y1), math.max(y0, y1) do
        for x = math.min(x0, x1), math.max(x0, x1) do
            target:set(x, y, tileSet:terrainTile(terrain, 0))
        end
    end
    Terrain.refreshAll(target, tileSet)
end

function Class:_tileSetFor(ui)
    local resources = ui and ui.resources or self:_resources()
    return resources and self:getTileSet(resources) or self._tileSetObject
end

-- Cell under a point given in the same pixel space as the node's position.
function Class:cellAt(px, py)
    local cw, ch = self.cellSize[1], self.cellSize[2]
    return math.floor((px - self._x) / cw), math.floor((py - self._y) / ch)
end

-- Top-left corner of a cell, in the pixel space of the node's position.
function Class:cellOrigin(x, y)
    return self._x + x * self.cellSize[1], self._y + y * self.cellSize[2]
end

function Class:isSolid(x, y, layer)
    local tileSet = self._tileSetObject
    if not tileSet then
        return false
    end
    x, y = math.floor(x), math.floor(y)
    for _, candidate in ipairs(self._order) do
        if (layer == nil or candidate.name == layer) and tileSet:isSolid(candidate:get(x, y)) then
            return true
        end
    end
    return false
end

function Class:tileProperty(x, y, key, layer)
    local tileSet = self._tileSetObject
    local id = tileSet and self:getCell(x, y, layer)
    return id ~= nil and tileSet:property(id, key) or nil
end

-- Collision ------------------------------------------------------------------------------

-- Rectangles { x, y, w, h } (in cells) covering the solid cells of a layer.
function Class:solidRects(layer)
    local tileSet = assert(self._tileSetObject, 'solidRects needs a loaded tileSet')
    return Colliders.rects(self:getLayer(layer), tileSet)
end

-- Creates a Collider2D box per merged rectangle under a static Body2D. `origin` is where the
-- top-left corner of the map is, relative to the body (physics units, Y up); a previous build of
-- this map is removed first. Returns the colliders.
function Class:buildColliders(ui, body, options)
    options = options or {}
    self:_tileSetFor(ui)
    for _, collider in ipairs(self._colliders or {}) do
        if not collider.destroyed then
            collider:destroy()
        end
    end
    local origin = options.origin or { 0, 0 }
    local cw, ch = self.cellSize[1], self.cellSize[2]
    local colliders = {}
    for _, rect in ipairs(self:solidRects(options.layer)) do
        colliders[#colliders + 1] = ui:create('Collider2D', {
            name = 'TileCollider',
            position = { origin[1] + (rect.x + rect.w / 2) * cw, origin[2] - (rect.y + rect.h / 2) * ch },
            size = { rect.w * cw, rect.h * ch },
            friction = options.friction,
        }, body)
    end
    self._colliders = colliders
    return colliders
end

-- Saving and loading ---------------------------------------------------------------------

-- Plain data: layers as lists of { x, y, id } (stable order), ready to write as a Lua file.
function Class:toData()
    local data = { layers = {} }
    for _, layer in ipairs(self._order) do
        local cells = {}
        layer:each(function(x, y, id)
            cells[#cells + 1] = { x, y, id }
        end)
        table.sort(cells, function(a, b)
            if a[2] ~= b[2] then
                return a[2] < b[2]
            end
            return a[1] < b[1]
        end)
        data.layers[#data.layers + 1] = { name = layer.name, visible = layer.visible, cells = cells }
    end
    return data
end

function Class:loadData(data)
    for _, entry in ipairs(data.layers or {}) do
        local layer = self:getLayer(entry.name)
        layer:clear()
        layer.visible = entry.visible ~= false
        for _, cell in ipairs(entry.cells) do
            layer:set(cell[1], cell[2], cell[3])
        end
    end
end

function Class:_loadMapFile(resources)
    if self._mapSource == self.mapFile then
        return
    end
    self._mapSource = self.mapFile
    if self.mapFile ~= '' then
        local text = katsa.filesystem.read(resources:canonical(self.mapFile))
        local chunk = text and loadstring(text, '@' .. self.mapFile)
        if chunk then
            self:loadData(chunk())
        elseif resources.store and resources.store.journal then
            resources.store.journal:record('Resources', 'Missing map file', self, self.mapFile)
        end
    end
end

-- Pointer --------------------------------------------------------------------------------

-- With `interactable` on, the map reports pointer events as the signal
-- `cellPointer(phase, x, y, pointerId)`: phase is press, move or release and (x, y) the cell
-- under the pointer (it can lie outside the node while a drag goes on).
function Class:pointer(ui, phase, px, py, id)
    local x, y = self:cellAt((px - ui.offsetX) / ui.scale, (py - ui.offsetY) / ui.scale)
    self:emit('cellPointer', phase, x, y, id)
end

-- Drawing --------------------------------------------------------------------------------

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    local resources = ui.resources
    self._ui = ui
    self:_loadMapFile(resources)
    local tileSet = self:getTileSet(resources)
    if not tileSet or #self._order == 0 then
        return
    end
    local g = katsa.graphics
    local w, h = self._width, self._height
    local cw, ch = self.cellSize[1], self.cellSize[2]
    if w <= 0 or h <= 0 or cw <= 0 or ch <= 0 then
        return
    end
    local image = resources:imageVariant(tileSet.image, self.pixelate)
    local iw, ih = image:getDimensions()
    -- Visible cells: the node rectangle cut by the screen (assumes no rotation, like the UI).
    local sw, sh = g.getDimensions()
    local ax, ay = g.inverseTransformPoint(0, 0)
    local bx, by = g.inverseTransformPoint(sw, sh)
    local left = math.max(self._x, math.min(ax, bx))
    local top = math.max(self._y, math.min(ay, by))
    local right = math.min(self._x + w, math.max(ax, bx))
    local bottom = math.min(self._y + h, math.max(ay, by))
    if right <= left or bottom <= top then
        return
    end
    local cx0, cy0 = math.floor((left - self._x) / cw), math.floor((top - self._y) / ch)
    local cx1, cy1 = math.ceil((right - self._x) / cw) - 1, math.ceil((bottom - self._y) / ch) - 1
    local style = require('source.engine.ui.style')
    local c = style.color(self, 'image') or { 1, 1, 1 }
    g.push('all')
    g.setColor(c[1], c[2], c[3], style.alpha(self, 'image', c))
    self._quad = self._quad or self:own(g.newQuad(0, 0, iw, ih, iw, ih))
    local quad = self._quad
    local span = (cx1 - cx0 + 1) * (cy1 - cy0 + 1)
    local function drawCell(x, y, id)
        if x < cx0 or x > cx1 or y < cy0 or y > cy1 then
            return
        end
        local sx, sy, sw2, sh2 = tileSet:region(id, iw, ih)
        local dx, dy = self._x + x * cw, self._y + y * ch
        -- Cut cells that stick out of the node rectangle instead of drawing outside it.
        local fx0 = math.max(0, (self._x - dx) / cw)
        local fy0 = math.max(0, (self._y - dy) / ch)
        local fx1 = math.min(1, (self._x + w - dx) / cw)
        local fy1 = math.min(1, (self._y + h - dy) / ch)
        quad:setViewport(sx + sw2 * fx0, sy + sh2 * fy0, sw2 * (fx1 - fx0), sh2 * (fy1 - fy0), iw, ih)
        g.draw(image, quad, dx + cw * fx0, dy + ch * fy0, 0, cw / sw2, ch / sh2)
    end
    for _, layer in ipairs(self._order) do
        if layer.visible then
            if layer.count < span then
                layer:each(drawCell)
            else
                for y = cy0, cy1 do
                    for x = cx0, cx1 do
                        local id = layer:get(x, y)
                        if id then
                            drawCell(x, y, id)
                        end
                    end
                end
            end
        end
    end
    g.pop()
end

return Class
