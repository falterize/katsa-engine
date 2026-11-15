local Version = require('source.engine.core.version')

local Project = {
    version = '1.0.8b', -- engine version this project was made for; a difference warns at startup
    title = 'Katsa Engine ' .. Version.release,
    identity = 'katsa-engine', -- save folder name: Katsa/<identity>; keep it stable and unique per game
    console = true,
    externalStorage = true,
    startScene = 'menu',
}

return Project
