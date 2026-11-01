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

-- The first Source opens the OpenAL output unless a driver was chosen already; without a device
-- (servers, CI) or with KATSA_AUDIO=null the silent driver stays.
function State.ensureDriver()
    if State.driverChosen then
        return
    end
    State.driverChosen = true
    if os.getenv('KATSA_AUDIO') == 'null' then
        return
    end
    local ok, driver = pcall(function()
        return require('source.katsa.audio.openal').open()
    end)
    if ok and driver then
        State.driver = driver
        driver.updateListener(State.listener)
        driver.updateGlobal(State)
    end
end

return State
