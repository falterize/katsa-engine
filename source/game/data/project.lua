local Version = require('source.engine.core.version')
local SaveData = require('source.engine.core.saveData')

local Project = {
    version = Version.release, -- engine version this project targets (checked by launchers)
    title = 'Katsa Engine' .. Version.value .. '',
    identity = SaveData.identity,
    console = true,
    externalStorage = true,
    startScene = 'menu',
}

return Project
