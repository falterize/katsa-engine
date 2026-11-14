-- The containers every replicated world has. `ReplicatedStorage` is shared: everything inside it
-- replicates without being marked. `ServerStorage` exists on the server only and is never scanned.
local Storage = {
    REPLICATED_ID = 1,
}

local function find(world, name)
    for _, child in ipairs(world.root.children) do
        if child.name == name and child.className == 'Folder' then
            return child
        end
    end
end

local function ensure(world, name)
    return find(world, name) or world:create('Folder', { name = name }, world.root)
end

-- Returns replicatedStorage and, on the server, serverStorage.
function Storage.install(world, isServer)
    local shared = ensure(world, 'ReplicatedStorage')
    return shared, isServer and ensure(world, 'ServerStorage') or nil
end

return Storage
