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
    if settings.frameRateLimit ~= nil then
        require('source.engine.core.runtime').validateFrameRateLimit(settings.frameRateLimit)
    end
    assert(
        settings.layoutVersion == nil or settings.layoutVersion == 2 or settings.layoutVersion == 3,
        'Unsupported scene layout version'
    )
    if settings.layoutVersion then
        for _, name in ipairs(Layout.directories) do
            -- Earlier packages keep UI at their root; new scenes group all code under scripts.
            local directory = settings.layoutVersion == 2 and name == 'scripts/ui' and 'ui' or name
            assert(
                love.filesystem.getInfo(root .. '/' .. directory, 'directory'),
                'Scene category directory is missing: ' .. directory
            )
        end
    end
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
