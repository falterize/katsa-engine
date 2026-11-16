local Paths = require('../paths')

-- Resource names that only a prefab scene understands (`scene://x`, `./scene://x`, `../scene://x`,
-- manifest aliases like `stone`) become names any world can resolve. `context` is
-- { resources = the prefab scene's resource scope, id = its scene id, aliases = {} }; the manifest
-- entries the new names stand for are collected in `aliases` and registered with `register`.
local Resource = {}

-- Rewrites one string; anything that is not a resource name of the scene stays as it is.
function Resource.string(value, context)
    local resources = context.resources
    local entry = resources.manifest[value]
    if entry then
        local name = context.id .. ':' .. value
        local path = type(entry) == 'string' and entry or entry.path
        context.aliases[name] = type(entry) == 'string' and { path = resources:canonical(value) }
            or setmetatable({ path = resources:canonical(path) }, { __index = entry })
        return name
    end
    if Paths.parse(value) == 'scene' then
        return resources:canonical(value)
    end
    return value
end

-- A deep copy of a property value with its strings rewritten (tables with a metatable, such as
-- nodes and managed vectors, are returned as they are).
function Resource.deep(value, context)
    local kind = type(value)
    if kind == 'string' then
        return Resource.string(value, context)
    elseif kind == 'table' and not getmetatable(value) then
        local result = {}
        for key, item in pairs(value) do
            result[key] = Resource.deep(item, context)
        end
        return result
    end
    return value
end

-- Registers the names collected in `aliases` in the world's manifest.
function Resource.register(world, aliases)
    local manifest = world.resources.manifest
    for name, entry in pairs(aliases) do
        manifest[name] = manifest[name] or entry
    end
end

return Resource
