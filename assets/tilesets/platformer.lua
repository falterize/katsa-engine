-- Example tileset for assets/textures/examples/tileset.png (made by tools/import/makeTileset.py).
-- Tiles 0-15 are one autotile terrain: the id is the bitmask of neighbouring ground cells
-- (N=1, E=2, S=4, W=8). Tiles 16-23 are single tiles.
local ground = {}
for mask = 0, 15 do
    ground[mask] = mask
end

return {
    image = 'shared://textures/examples/tileset.png',
    columns = 8,
    rows = 3,
    terrains = {
        ground = { tiles = ground, solid = true },
    },
    tiles = {
        [16] = { name = 'water', solid = false, hazard = true },
        [17] = { name = 'brick', solid = true },
        [18] = { name = 'crate', solid = true },
        [19] = { name = 'spike', solid = false, hazard = true },
        [20] = { name = 'coin', solid = false, pickup = true },
        [21] = { name = 'ladder', solid = false, climbable = true },
        [22] = { name = 'sign', solid = false },
        [23] = { name = 'flag', solid = false },
    },
}
