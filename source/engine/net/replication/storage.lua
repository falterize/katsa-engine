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
    -- A scene's world hangs from its Game node; the containers become its siblings. A headless
    -- world (a dedicated server, a test) has no Game node and keeps them as roots.
    local top = world._node.parent
    local container = Node.create(
        'StorageFolder',
        { name = name, visible = false, storageContainer = true },
        top and top:isA('Game') and top or nil,
        world
    )
    container._world, container._sceneWorld = world, world
    world.storage[name] = container
    return container
end

-- Returns replicatedStorage and, on the server, serverStorage. A single-player scene installs both
-- (it is its own server); a client that joins a remote server drops its ServerStorage, which only
-- the server has.
function Storage.install(world, isServer)
    world.storage = world.storage or {}
    local shared = ensure(world, 'ReplicatedStorage')
    if isServer then
        return shared, ensure(world, 'ServerStorage')
    end
    local server = world.storage.ServerStorage
    if server then
        world.storage.ServerStorage = nil
        if not server.destroyed then
            server:destroy()
        end
    end
    return shared
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
