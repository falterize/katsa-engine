local Version = require('source.engine.core.version')
local SaveData = require('source.engine.core.saveData')

local Project = {
    version = '1.0.8b', -- engine version this project was made for; a difference warns at startup
    title = 'Katsa - SBox B ' .. Version.value .. '',
    identity = SaveData.identity,
    console = true,
    externalStorage = true,
    startScene = 'menu',
}

return Project
