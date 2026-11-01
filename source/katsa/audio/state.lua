-- Shared audio state: the public module table, the source class and the active driver.
local State = {
    Audio = {},
    Methods = {},
    listener = {
        position = { 0, 0, 0 },
        orientation = { 0, 0, -1, 0, 1, 0 },
        velocity = { 0, 0, 0 },
        volume = 1,
    },
    effects = {},
    driver = require('source.katsa.audio.nullDriver'),
    sources = setmetatable({}, { __mode = 'k' }),
}
State.Methods.__index = State.Methods

return State
