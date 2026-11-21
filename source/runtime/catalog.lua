-- Scene IDs known to the runtime: an ID resolves to a scene package path. The engine ships none;
-- a game or the examples register theirs with `use` (the project's `catalog` module name).
local Optional = require('./optional')

local Catalog = { entries = {}, byId = {} }

function Catalog.register(entries)
    for _, entry in ipairs(entries or {}) do
        Catalog.entries[#Catalog.entries + 1] = entry
        Catalog.byId[entry.id] = entry
    end
    return Catalog
end

-- `name` is a module returning { entries = { { id, path }, ... } }, or nil for no catalog.
function Catalog.use(name)
    local module = name and Optional.require(name)
    if module then
        Catalog.register(module.entries)
        for id, entry in pairs(module.byId or {}) do
            Catalog.byId[id] = entry
        end
    end
    return Catalog
end

return Catalog
