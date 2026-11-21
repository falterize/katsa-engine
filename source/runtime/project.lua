-- The engine's own project: what runs when no game provides one. There is no start scene, so the
-- program shows a black screen and says so in the console; a scene is opened by path, dropped on
-- the window or placed in the `scenes` folder.
local Version = require('source.engine.core.version')

return {
    version = Version.release,
    title = 'Katsa Engine ' .. Version.release,
    identity = 'katsa-engine', -- save folder name: Katsa/<identity>
    console = true,
    externalStorage = true,
}
