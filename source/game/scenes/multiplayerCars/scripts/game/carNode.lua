-- One node per car in the scene tree. The container `Car<netId>` holds everything that belongs to
-- the car: the physics `Body` (game/physicsCar.lua) and the drawn `Model` (view/carView.lua). The
-- two are created by different owners at different times (a client may have a view without a body,
-- a headless server a body without a view), so the container is shared and reference counted: the
-- first owner creates it, the last one to let go destroys it.
--
-- The container itself is never moved or scaled; it is only the parent that keeps a car's nodes
-- together in the Explorer. The body is placed by the physics engine and the model by the car's
-- replicated pose.
local CarNode = {}

local registry = setmetatable({}, { __mode = 'k' }) -- world -> { [netId] = { node, refs } }

function CarNode.acquire(world, netId)
    local cars = registry[world]
    if not cars then
        cars = {}
        registry[world] = cars
    end
    local entry = cars[netId]
    if not entry or entry.node.destroyed then
        entry = { node = world:create('Node3D', { name = 'Car' .. netId }), refs = 0 }
        cars[netId] = entry
    end
    entry.refs = entry.refs + 1
    return entry.node
end

function CarNode.release(world, netId)
    local cars = registry[world]
    local entry = cars and cars[netId]
    if not entry then
        return
    end
    entry.refs = entry.refs - 1
    if entry.refs <= 0 then
        cars[netId] = nil
        if not entry.node.destroyed then
            entry.node:destroy()
        end
    end
end

return CarNode
