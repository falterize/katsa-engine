-- The Crossroads map, around its own origin (the server places it at the arena).
-- boxes: { x, y, z, width, height, depth, color } (y is the box's centre);
-- coins: { x, z, surface }, the coin floats 0.8 above the surface it stands on.
local FLOOR = 32

return {
    title = 'Crossroads',
    boxes = {
        { 0, 0, 0, FLOOR, 0.2, FLOOR, { 0.45, 0.5, 0.78, 1 } },
        { 0, 1, 7, 2, 2, 10, { 0.85, 0.85, 0.92, 1 } },
        { 0, 1, -7, 2, 2, 10, { 0.85, 0.85, 0.92, 1 } },
        { 7, 1, 0, 10, 2, 2, { 0.85, 0.85, 0.92, 1 } },
        { -7, 1, 0, 10, 2, 2, { 0.85, 0.85, 0.92, 1 } },
        { 0, 0.3, 0, 3, 0.6, 3, { 1, 0.85, 0.4, 1 } },
    },
    coins = {
        { 0, 0, 0.6 }, { 10, 10, 0.1 }, { -10, 10, 0.1 }, { 10, -10, 0.1 }, { -10, -10, 0.1 },
        { 7, 3, 0.1 }, { -7, -3, 0.1 }, { 3, -7, 0.1 }, { -3, 7, 0.1 }, { 13, 0, 0.1 },
    },
}
