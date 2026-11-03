local Tables = require('../../core.tables')
local Array = require('../../math.array')
local pairs = require('../../math.array').pairs

local palette = {
    { 1, 1, 1 },
    { 0.75, 0.75, 0.75 },
    { 0.35, 0.35, 0.35 },
    { 0, 0, 0 },
    { 1, 0.25, 0.25 },
    { 1, 0.6, 0.15 },
    { 1, 0.9, 0.2 },
    { 0.5, 0.85, 0.25 },
    { 0.1, 0.7, 0.5 },
    { 0.1, 0.8, 1 },
    { 0.2, 0.4, 1 },
    { 0.6, 0.3, 1 },
    { 1, 0.35, 0.75 },
    { 0.55, 0.25, 0.15 },
    { 0.85, 0.7, 0.5 },
    { 0.1, 0.2, 0.3 },
    { 0.035, 0.065, 0.105 },
    { 0.1, 0.32, 0.45 },
}

return { palette = palette, copy = Tables.copyAuthored }
