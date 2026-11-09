-- Autotiling: a terrain cell picks its tile from which of its four neighbours belong to the
-- same terrain (mask N=1, E=2, S=4, W=8). Painting a cell refreshes it and its neighbours.
local Terrain = {}

local NEIGHBOURS = { { 0, -1, 1 }, { 1, 0, 2 }, { 0, 1, 4 }, { -1, 0, 8 } }

local function terrainAt(layer, tileSet, x, y)
    local id = layer:get(x, y)
    return id ~= nil and tileSet.terrainOf[id] or nil
end

-- Mask of the neighbours of (x, y) that are `terrain`.
function Terrain.mask(layer, tileSet, x, y, terrain)
    local mask = 0
    for _, n in ipairs(NEIGHBOURS) do
        if terrainAt(layer, tileSet, x + n[1], y + n[2]) == terrain then
            mask = mask + n[3]
        end
    end
    return mask
end

local function refresh(layer, tileSet, x, y)
    local terrain = terrainAt(layer, tileSet, x, y)
    if terrain then
        layer:set(x, y, tileSet:terrainTile(terrain, Terrain.mask(layer, tileSet, x, y, terrain)))
    end
end

-- Paints (or, with terrain = nil, erases) a cell and fixes the tiles around it.
function Terrain.paint(layer, tileSet, x, y, terrain)
    if terrain then
        layer:set(x, y, tileSet:terrainTile(terrain, 0))
    else
        layer:set(x, y, nil)
    end
    refresh(layer, tileSet, x, y)
    for _, n in ipairs(NEIGHBOURS) do
        refresh(layer, tileSet, x + n[1], y + n[2])
    end
end

-- Fixes every terrain tile of the layer (after filling cells directly).
function Terrain.refreshAll(layer, tileSet)
    local used = {}
    layer:each(function(x, y)
        used[#used + 1] = { x, y }
    end)
    for _, cell in ipairs(used) do
        refresh(layer, tileSet, cell[1], cell[2])
    end
end

return Terrain
