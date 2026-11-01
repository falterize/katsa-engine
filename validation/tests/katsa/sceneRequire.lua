-- Loads pure-Lua scene modules outside a scene package, resolving `scene.` requires the way
-- Package:require does. Usage: local load = require('validation.tests.katsa.sceneRequire')
--   local Arena = load('multiplayerCars', 'scene.scripts.arena')
local cache = {}

return function(sceneName, name)
    local root = 'source/game/scenes/' .. sceneName .. '/'
    local function resolve(module)
        if module:sub(1, 6) ~= 'scene.' then
            return require(module)
        end
        local relative = module:sub(7):gsub('%.', '/')
        local key = sceneName .. '/' .. relative
        if cache[key] == nil then
            local path = root .. relative .. '.lua'
            local file = io.open(path)
            if not file then
                path = root .. relative .. '/init.lua'
            else
                file:close()
            end
            local chunk = assert(loadfile(path))
            setfenv(chunk, setmetatable({ require = resolve }, { __index = _G }))
            cache[key] = false
            cache[key] = chunk()
        end
        return cache[key]
    end
    return resolve(name)
end
