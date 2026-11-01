local Version = require('source.engine.core.version')
local SaveData = require('source.engine.core.saveData')

local Project = {
    title = 'Katsa - SBox B ' .. Version.value .. '',
    identity = SaveData.identity,
    console = true,
    externalStorage = true,
    startScene = 'menu',
}

return Project
