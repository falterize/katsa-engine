local Layout = {
    directories = {
        'assets',
        'assets/models',
        'assets/textures',
        'assets/audio',
        'assets/shaders',
        'assets/fonts',
        'nodes',
        'systems',
        'scripts',
        'scripts/ui',
    },
    hooks = { 'create', 'update', 'update3D', 'update2D', 'destroy' },
}

-- Launcher metadata lives in menu-settings.lua; naming it in conf.lua is a mistake worth reporting.
-- (`title` is the application title of conf.lua, not the menu entry.)
local MENU_KEYS = { 'id', 'category', 'tags', 'description' }

-- Keys that were once part of a scene's conf and are code now: the scene sets them when it builds
-- its world (see docs/book/conf.md). Reporting them beats silently ignoring them.
local REMOVED_KEYS = {
    layoutVersion = 'the layout is always the current one',
    catalog = 'scenes are found in the project\'s scenes folder',
    gravity = 'pass it to createPhysics2D / createPhysics3D',
    gravityDirection = 'pass it to createPhysics2D / createPhysics3D',
    physics = 'pass options (and `backend`) to scene:createPhysics3D',
    physics2D = 'pass options to scene:createPhysics2D',
    world = 'call scene.world:configure({ sky = ..., fog = ..., ambient = ... })',
    assets = 'call scene.resources:define(name, { path = ... })',
    enabled = 'enable systems in main.lua',
    gammacorrect = 'it never did anything',
}

function Layout.validate(root, settings)
    for _, key in ipairs(MENU_KEYS) do
        assert(
            settings[key] == nil,
            ('conf.lua must not set `%s`: it belongs in menu-settings.lua'):format(key)
        )
    end
    for key, hint in pairs(REMOVED_KEYS) do
        assert(settings[key] == nil, ('conf.lua no longer has `%s`: %s'):format(key, hint))
    end
    assert(
        settings.server == nil or type(settings.server) == 'string',
        'conf.lua `server` must name a module such as server.main'
    )
    assert(
        settings.runInBackground == nil or type(settings.runInBackground) == 'boolean',
        'runInBackground must be a boolean'
    )
    if settings.frameRateLimit ~= nil then
        require('source.engine.core.runtime').validateFrameRateLimit(settings.frameRateLimit)
    end
    -- Category folders are a convention, not a requirement: Git, GitHub ZIPs and many
    -- archivers drop empty folders, so a scene must load without them.
end

-- The scene's lifecycle module: main.lua, or the `server` module when the process runs
-- as a headless dedicated server (`--server`). `forced` names the module instead (prefab loads).
function Layout.lifecycle(package, forced)
    local name = forced or 'main'
    if not forced and require('source.engine.core.runtime').headless then
        name = assert(
            package.settings.server,
            'This scene has no server entry (conf.lua `server`) to run with --server'
        )
    end
    local main = package:require(name)
    assert(type(main) == 'table', 'Scene ' .. name .. ' must return a named module')
    for _, hook in ipairs(Layout.hooks) do
        assert(type(main[hook]) == 'function', 'Scene lifecycle hook is missing: ' .. hook)
    end
    return main
end

return Layout
