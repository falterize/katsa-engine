local Node = require('../../nodes')
local ipairs = require('../../math.array').ipairs

-- The containers every replicated world has. They are top-level nodes beside the world root, not
-- children of it: hidden, never rendered, and shown as their own roots in the Explorer.
-- `ReplicatedStorage` is shared: everything inside it replicates without being marked.
-- `ServerStorage` exists on the server only and is never scanned.
local Storage = {
    REPLICATED_ID = 1,
}

local function ensure(world, name)
    local found = world.storage[name]
    if found and not found.destroyed then
        return found
    end
    local container = Node.create('StorageFolder', { name = name, visible = false, storageContainer = true }, nil, world)
    container._world, container._sceneWorld = world, world
    world.storage[name] = container
    return container
end

-- Returns replicatedStorage and, on the server, serverStorage.
function Storage.install(world, isServer)
    world.storage = world.storage or {}
    local shared = ensure(world, 'ReplicatedStorage')
    return shared, isServer and ensure(world, 'ServerStorage') or nil
end

-- The containers of a world, for the Explorer.
function Storage.list(world)
    local list = {}
    for _, name in ipairs({ 'ReplicatedStorage', 'ServerStorage' }) do
        local container = world.storage and world.storage[name]
        if container and not container.destroyed then
            list[#list + 1] = container
        end
    end
    return list
end

return Storage
