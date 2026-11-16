-- The Ring Court map, around its own origin (the server places it at the arena).
-- boxes: { x, y, z, width, height, depth, color } (y is the box's centre);
-- coins: { x, z, surface }, the coin floats 0.8 above the surface it stands on.
local FLOOR = 32

return {
    title = 'Ring Court',
    boxes = {
        { 0, 0, 0, FLOOR, 0.2, FLOOR, { 0.82, 0.5, 0.36, 1 } },
        { 0, 0.5, 0, 4, 1, 4, { 0.95, 0.78, 0.4, 1 } },
        { 11, 1.5, 11, 2, 3, 2, { 0.6, 0.35, 0.3, 1 } },
        { -11, 1.5, 11, 2, 3, 2, { 0.6, 0.35, 0.3, 1 } },
        { 11, 1.5, -11, 2, 3, 2, { 0.6, 0.35, 0.3, 1 } },
        { -11, 1.5, -11, 2, 3, 2, { 0.6, 0.35, 0.3, 1 } },
    },
    coins = {
        { 10, 0, 0.1 }, { 8, 6, 0.1 }, { 3, 10, 0.1 }, { -3, 10, 0.1 }, { -8, 6, 0.1 },
        { -10, 0, 0.1 }, { -8, -6, 0.1 }, { -3, -10, 0.1 }, { 3, -10, 0.1 }, { 0, 0, 1 },
    },
}
