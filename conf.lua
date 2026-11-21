-- The engine's own conf: what runs when no game provides one. There is no start scene, so the
-- program shows a black screen and says so in the console. A project or scene run on the engine
-- (`katsa <folder>`) lays its own conf.lua over this one (see docs/book/conf.md).
local Version = require('source.engine.core.version')

return {
    version = Version.release,
    title = 'Katsa Engine ' .. Version.release,
    identity = 'katsa-engine', -- save folder name: Katsa/<identity>
    console = true,
    externalStorage = true,
}
