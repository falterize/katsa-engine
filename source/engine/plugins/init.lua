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

-- Contributions -----------------------------------------------------------------------------
--
-- A manifest can extend the engine for the scenes that opt in with `plugins = { 'name' }` in
-- their settings. Nothing is added for scenes that do not list the plugin.
--
--   nodes = { NavMap = 'source.plugins.pathfinding.nodes.navMap' }
--       Node types, registered in the scene's world exactly like `world:registerNodeType`
--       (the module returns the definition table).
--   extend = { Body3D = 'source.plugins.pathfinding.extensions.body3D' }
--       Settings and methods added to existing node classes (see nodes/core/extensions.lua).
--   debug = { key = 'pathfinding', title = 'Pathfinding', defaults = { enabled = false, ... },
--             draw = 'source.plugins.pathfinding.debug' }
--       (or a list of such tables for several independent sections)
--       A section `Environment.debug.<key>` seeded from `defaults`, listed in the editor and the
--       debug menu. When `enabled` is true the module's `draw(world, camera, settings)` runs
--       after the 3D scene each frame.

-- Activates plugins for one world. Safe to call twice with the same names.
-- A manifest names its modules relative to the plugin folder ('./nodes.navMap') or absolutely.
local function load(name, path)
    if path:sub(1, 2) == './' then
        path = 'source.plugins.' .. name .. '.' .. path:sub(3)
    end
    return require(path)
end

function Plugins.activate(world, names)
    world.plugins = world.plugins or { names = {}, debug = {} }
    local state = world.plugins
    rawset(world.environment, '_pluginDebug', state.debug) -- read by the editor tree
    for _, name in ipairs(names or {}) do
        if not state.names[name] then
            state.names[name] = true
            local info = assert(manifest(name), 'Unknown plugin: ' .. tostring(name))
            Plugins.require(name)
            for typeName, modulePath in pairs(info.nodes or {}) do
                world:registerNodeType(typeName, load(name, modulePath))
            end
            for className, modulePath in pairs(info.extend or {}) do
                local spec = load(name, modulePath)
                spec.plugin = name
                require('source.engine.nodes.core.extensions').add(className, spec)
            end
            local sections = info.debug and (info.debug.key and { info.debug } or info.debug) or {}
            for _, debug in ipairs(sections) do
                local settings = world.environment.debug[debug.key] or {}
                for key, value in pairs(debug.defaults or {}) do
                    if settings[key] == nil then
                        settings[key] = value
                    end
                end
                world.environment.debug[debug.key] = settings
                state.debug[#state.debug + 1] = {
                    key = debug.key,
                    title = debug.title or debug.key,
                    settings = settings,
                    drawer = debug.draw and load(name, debug.draw) or nil,
                }
            end
        end
    end
end

-- Debug sections of the active plugins: { key, title, settings } in activation order.
function Plugins.debugSections(world)
    return world.plugins and world.plugins.debug or {}
end

-- Runs the draw hook of every enabled plugin debug section (called by the renderer).
function Plugins.drawDebug(world, camera)
    for _, section in ipairs(Plugins.debugSections(world)) do
        if section.settings.enabled and section.drawer then
            section.drawer.draw(world, camera, section.settings)
        end
    end
end

return Plugins
