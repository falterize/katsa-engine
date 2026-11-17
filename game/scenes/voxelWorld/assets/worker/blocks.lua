-- Block catalogue shared by the main thread and the chunk workers (plain data, no engine API).
-- Tiles are indices into assets/textures/blocks.png (4x4 grid of 16x16 tiles, row by row).
local Blocks = {
    CHUNK = 16,
    HEIGHT = 64,
    SECTION = 16, -- vertical size of one mesh section
    AIR = 0,
    -- The order is the default hotbar order; `icon` is the tile shown in the hotbar.
    list = {
        { name = 'Grass', top = 0, side = 1, bottom = 2, icon = 1 },
        { name = 'Dirt', top = 2, side = 2, bottom = 2, icon = 2 },
        { name = 'Stone', top = 3, side = 3, bottom = 3, icon = 3 },
        { name = 'Sand', top = 4, side = 4, bottom = 4, icon = 4 },
        { name = 'Log', top = 6, side = 5, bottom = 6, icon = 5 },
        { name = 'Leaves', top = 7, side = 7, bottom = 7, icon = 7, transparent = true },
        { name = 'Planks', top = 8, side = 8, bottom = 8, icon = 8 },
        { name = 'Cobblestone', top = 9, side = 9, bottom = 9, icon = 9 },
        { name = 'Bricks', top = 10, side = 10, bottom = 10, icon = 10 },
        { name = 'Snow', top = 11, side = 11, bottom = 11, icon = 11 },
        { name = 'Coal ore', top = 12, side = 12, bottom = 12, icon = 12 },
        { name = 'Sandstone', top = 13, side = 13, bottom = 13, icon = 13 },
        { name = 'Gravel', top = 14, side = 14, bottom = 14, icon = 14 },
        { name = 'Ice', top = 15, side = 15, bottom = 15, icon = 15, transparent = true },
    },
}

Blocks.GRASS, Blocks.DIRT, Blocks.STONE, Blocks.SAND = 1, 2, 3, 4
Blocks.LOG, Blocks.LEAVES, Blocks.SNOW, Blocks.COAL, Blocks.SANDSTONE = 5, 6, 10, 11, 12

-- Block ids are 1-based list indices; 0 is air.
function Blocks.isTransparent(id)
    return id == 0 or (Blocks.list[id] and Blocks.list[id].transparent) or false
end

return Blocks
