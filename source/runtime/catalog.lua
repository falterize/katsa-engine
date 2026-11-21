-- Scene IDs known to the runtime: an ID resolves to a scene package path. The engine ships none;
-- a project's scenes register themselves when it opens (see engine/scenes/project.lua).
local Catalog = { entries = {}, byId = {} }

function Catalog.register(entries)
    for _, entry in ipairs(entries or {}) do
        Catalog.entries[#Catalog.entries + 1] = entry
        Catalog.byId[entry.id] = entry
    end
    return Catalog
end

return Catalog
