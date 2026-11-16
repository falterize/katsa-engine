-- The Stepping Stones map, around its own origin (the server places it at the arena).
-- boxes: { x, y, z, width, height, depth, color } (y is the box's centre);
-- coins: { x, z, surface }, the coin floats 0.8 above the surface it stands on.
local FLOOR = 32

return {
    title = 'Stepping Stones',
    boxes = {
        { 0, 0, 0, FLOOR, 0.2, FLOOR, { 0.2, 0.45, 0.5, 1 } },
        { 6, 0.4, 0, 4, 0.8, 4, { 0.55, 0.8, 0.75, 1 } },
        { 9, 0.8, 6, 4, 1.6, 4, { 0.5, 0.75, 0.7, 1 } },
        { 3, 1.2, 10, 4, 2.4, 4, { 0.45, 0.7, 0.65, 1 } },
        { -4, 0.8, 8, 4, 1.6, 4, { 0.5, 0.75, 0.7, 1 } },
        { -9, 0.4, 2, 4, 0.8, 4, { 0.55, 0.8, 0.75, 1 } },
        { -6, 0.8, -6, 4, 1.6, 4, { 0.5, 0.75, 0.7, 1 } },
        { 2, 1.2, -9, 4, 2.4, 4, { 0.45, 0.7, 0.65, 1 } },
        { 10, 0.6, -6, 4, 1.2, 4, { 0.5, 0.75, 0.7, 1 } },
    },
    coins = {
        { 6, 0, 0.8 }, { 9, 6, 1.6 }, { 3, 10, 2.4 }, { -4, 8, 1.6 }, { -9, 2, 0.8 },
        { -6, -6, 1.6 }, { 2, -9, 2.4 }, { 10, -6, 1.2 }, { 0, 0, 0.1 }, { 0, 3, 0.1 },
    },
}
