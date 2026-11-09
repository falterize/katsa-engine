-- TileSet: how the cells of a TileMap look and behave. A tileset is a Lua table (usually the
-- return value of a file such as assets/tilesets/platformer.lua):
--
--   return {
--       image = 'shared://textures/examples/tileset.png',
--       columns = 8, rows = 3,                      -- tile grid of the image, row-major, 0-based ids
--       tiles = { [16] = { name = 'water', solid = false, hazard = true } },
--       terrains = {
--           -- one id per 4-neighbour mask (N=1, E=2, S=4, W=8), so 16 ids. `solid` applies to all.
--           ground = { tiles = { [0] = 0, 1, 2, ... 15 }, solid = true },
--       },
--   }
--
-- Every tile may carry free-form properties next to `solid` (damage, friction, ...); read them
-- with `tileSet:property(id, 'damage')`.
local TileSet = {}
TileSet.__index = TileSet

local MASKS = 16

-- Counts hot reloads: a TileMap loads its tileset again when this changes.
TileSet.revision = 0

function TileSet.invalidate()
    TileSet.revision = TileSet.revision + 1
end

function TileSet.new(definition)
    assert(type(definition) == 'table', 'A tileset must be a table')
    assert(type(definition.image) == 'string' and definition.image ~= '', 'A tileset needs an image')
    local columns, rows = definition.columns or 1, definition.rows or 1
    assert(columns >= 1 and rows >= 1, 'A tileset needs at least one column and one row')
    local self = setmetatable({
        image = definition.image,
        columns = columns,
        rows = rows,
        tiles = definition.tiles or {},
        terrains = {},
        terrainOf = {},
        count = columns * rows,
    }, TileSet)
    for name, terrain in pairs(definition.terrains or {}) do
        for mask = 0, MASKS - 1 do
            local id = terrain.tiles[mask]
            assert(
                id and id >= 0 and id < self.count,
                ('Terrain %s needs a tile id for mask %d'):format(name, mask)
            )
            self.terrainOf[id] = name
        end
        self.terrains[name] = terrain
    end
    return self
end

-- Reads a tileset file through the scene resources.
function TileSet.load(resources, path)
    local text = assert(katsa.filesystem.read(resources:canonical(path)), 'Missing tileset: ' .. path)
    local chunk = assert(loadstring(text, '@' .. path))
    return TileSet.new(chunk())
end

function TileSet:info(id)
    return self.tiles[id]
end

function TileSet:property(id, key)
    local info = self.tiles[id]
    if info and info[key] ~= nil then
        return info[key]
    end
    local terrain = self.terrains[self.terrainOf[id]]
    return terrain and terrain[key]
end

function TileSet:isSolid(id)
    return id ~= nil and self:property(id, 'solid') == true
end

function TileSet:terrainTile(name, mask)
    return assert(self.terrains[name], 'Unknown terrain: ' .. tostring(name)).tiles[mask]
end

-- Source rectangle of a tile in image pixels.
function TileSet:region(id, imageWidth, imageHeight)
    local w, h = imageWidth / self.columns, imageHeight / self.rows
    return id % self.columns * w, math.floor(id / self.columns) * h, w, h
end

return TileSet
