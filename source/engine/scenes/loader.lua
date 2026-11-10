local Package = require('./package')

local Loader = {}

function Loader.open(source, catalog, sharedRoot)
    local entry = type(source) == 'string' and catalog and catalog.byId[source]
    local package = Package.open(entry and entry.path or source)
    if entry and package.id ~= entry.id then
        package:release()
        error('Catalog ID differs from menu-settings id: ' .. entry.id, 0)
    end
    package.paths.shared = sharedRoot or 'assets'
    return package
end

function Loader.configure(defaults, overrides)
    for key, value in pairs(overrides or {}) do
        if type(value) == 'table' and type(defaults[key]) == 'table' then
            Loader.configure(defaults[key], value)
        else
            defaults[key] = value
        end
    end
    return defaults
end

function Loader.manifest(shared, localAssets)
    local manifest = {}
    for name, entry in pairs(shared or {}) do
        manifest[name] = entry
    end
    for name, entry in pairs(localAssets or {}) do
        manifest[name] = type(entry) == 'string' and { path = entry } or entry
    end
    return manifest
end

function Loader.create(scene)
    local main = require('source.engine.scenes.layout').lifecycle(scene.package)
    if type(main.create) == 'function' then
        scene.lifecycle = main
        return assert(main.create(scene, scene.package), 'Scene create must return its state')
    end
    assert(
        type(main) == 'table' and type(main.new) == 'function',
        'Scene main.lua must export create(scene, context)'
    )
    local state = assert(main.new(scene, scene.package), 'Scene main.new must return an instance')
    -- Earlier scene archives remain loadable; newly authored packages use create.
    scene:preparePresentation()
    if state.buildUI then
        state:buildUI()
    end
    return state
end

return Loader
