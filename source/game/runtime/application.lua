local Loader = require('source.engine.scenes.loader')
local Catalog = require('../sceneCatalog')

local Application = {}

function Application.new(manager, source, options)
    local package = Loader.open(source, Catalog, require('../data.assetRoots').shared)
    if package.settings.runtime == 'standalone' then
        return require('source.engine.scenes.host').new(manager, package, options)
    end
    if package.settings.kind == 'interface' then
        return require('source.engine.scenes.interface').new(manager, package, options)
    end
    return require('./game').new(
        manager,
        package.settings.id,
        { _package = package }
    )
end

return Application
