local Layout = {
    version = 3,
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

function Layout.validate(root, settings)
    assert(
        settings.runInBackground == nil or type(settings.runInBackground) == 'boolean',
        'runInBackground must be a boolean'
    )
    if settings.frameRateLimit ~= nil then
        require('../core.runtime').validateFrameRateLimit(settings.frameRateLimit)
    end
    assert(
        settings.layoutVersion == nil or settings.layoutVersion == 2 or settings.layoutVersion == 3,
        'Unsupported scene layout version'
    )
    -- Category folders are a convention, not a requirement: Git, GitHub ZIPs and many
    -- archivers drop empty folders, so a scene must load without them.
end

function Layout.lifecycle(package)
    local main = package:require('main')
    assert(type(main) == 'table', 'Scene main.lua must return a named module')
    if package.settings.layoutVersion then
        for _, name in ipairs(Layout.hooks) do
            assert(type(main[name]) == 'function', 'Scene lifecycle hook is missing: ' .. name)
        end
    end
    return main
end

return Layout
