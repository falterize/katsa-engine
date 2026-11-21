local Loader = require('source.engine.scenes.loader')
local Catalog = require('./catalog')

local Application = {}

function Application.new(manager, source, options)
    local package = Loader.open(source, Catalog, require('source.runtime.assetRoots').shared)
    if package.settings.runtime == 'standalone' then
        options = options or {}
        options.modules = options.modules or require('source.runtime.modules').standalone
        return require('source.engine.scenes.host').new(manager, package, options)
    end
    if package.settings.kind == 'interface' then
        return require('source.engine.scenes.interface').new(manager, package, options)
    end
    return require('source.runtime.game').new(
        manager,
        package.id,
        { _package = package, modules = options and options.modules }
    )
end

return Application
