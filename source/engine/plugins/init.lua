-- Plugin loader. A plugin is an optional add-on in `source/plugins/<name>/` with a `plugin.lua`
-- manifest and an `init.lua` entry returning its public API. The core engine never requires a
-- plugin; scenes and games opt in, so unused plugins cost nothing and can be left out of builds.
--
--   local pathfinding = Plugins.require('pathfinding')
--   Plugins.list()          -- manifests of every plugin in this build
local Plugins = {}

local ROOT = 'source/plugins'
local loaded, manifests = {}, {}

local function manifest(name)
    if manifests[name] == nil then
        local ok, result = pcall(require, 'source.plugins.' .. name .. '.plugin')
        manifests[name] = ok and result or false
        if not ok and not tostring(result):find('not found', 1, true) then
            error(result, 0)
        end
    end
    return manifests[name] or nil
end

function Plugins.has(name)
    return manifest(name) ~= nil
end

function Plugins.manifest(name)
    return manifest(name)
end

-- Names of the plugin folders present in this build, sorted.
function Plugins.names()
    local names = {}
    for _, entry in ipairs(katsa.filesystem.getDirectoryItems(ROOT)) do
        if katsa.filesystem.getInfo(ROOT .. '/' .. entry, 'directory') then
            names[#names + 1] = entry
        end
    end
    table.sort(names)
    return names
end

function Plugins.list()
    local list = {}
    for _, name in ipairs(Plugins.names()) do
        list[#list + 1] = manifest(name)
    end
    return list
end

-- Loads (once) and returns the plugin API. Dependencies listed in `requires` load first.
function Plugins.require(name)
    if loaded[name] then
        return loaded[name]
    end
    local info = manifest(name)
    assert(info, 'Unknown plugin: ' .. tostring(name))
    assert(info.name == name, 'Plugin manifest name does not match its folder: ' .. name)
    for _, dependency in ipairs(info.requires or {}) do
        Plugins.require(dependency)
    end
    local api = require('source.plugins.' .. name)
    loaded[name] = api
    return api
end

return Plugins
