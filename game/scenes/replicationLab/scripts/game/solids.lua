-- Physics for the server's scenery. The server owns the platform and the maps as replicated
-- meshes marked with the `Solid` attribute; a client has no physics for them, so this gives each
-- one a body here: static for a map piece, kinematic (following the replicated position) for a
-- `Moving` one. The local character stands on these bodies and is carried by moving ones.
local Solids = {}
Solids.__index = Solids

local ROOTS = { 'Platform', 'Map' }
local SCAN_INTERVAL = 0.25
local FOLLOW = 10 -- how quickly a moving body catches up with its replicated position

function Solids.new(scene, session)
    return setmetatable({ scene = scene, session = session, proxies = {}, timer = 0, count = 0 }, Solids)
end

local function meshesUnder(root, list)
    if root.className == 'Mesh3D' and root:getAttribute('Solid') then
        list[#list + 1] = root
    end
    for _, node in ipairs(root:getDescendants()) do
        if node.className == 'Mesh3D' and node:getAttribute('Solid') then
            list[#list + 1] = node
        end
    end
    return list
end

function Solids:add(mesh)
    local moving = mesh:getAttribute('Moving') == true
    self.count = self.count + 1
    local p, size = mesh.position, mesh.size
    self.proxies[mesh] = {
        moving = moving,
        body = self.scene.world:create('Body3D', {
            name = 'SolidProxy' .. self.count,
            bodyType = moving and 'Kinematic' or 'Static',
            position = { p[1], p[2], p[3] },
            size = { size[1], size[2], size[3] },
            friction = 0.8,
            restitution = 0,
        }),
    }
end

function Solids:scan()
    local found = {}
    for _, name in ipairs(ROOTS) do
        local root = self.session:node(name)
        if root then
            meshesUnder(root, found)
        end
    end
    local alive = {}
    for _, mesh in ipairs(found) do
        alive[mesh] = true
        if not self.proxies[mesh] then
            self:add(mesh)
        end
    end
    for mesh, proxy in pairs(self.proxies) do
        if not alive[mesh] or mesh.destroyed then
            proxy.body:destroy()
            self.proxies[mesh] = nil
        end
    end
end

function Solids:update(dt)
    self.timer = self.timer - dt
    if self.timer <= 0 then
        self.timer = SCAN_INTERVAL
        self:scan()
    end
    for mesh, proxy in pairs(self.proxies) do
        if proxy.moving and not mesh.destroyed then
            local target, at = mesh.position, proxy.body.position
            proxy.body.physics:setVelocity({
                (target[1] - at[1]) * FOLLOW,
                (target[2] - at[2]) * FOLLOW,
                (target[3] - at[3]) * FOLLOW,
            })
        end
    end
end

-- The horizontal velocity of the moving body `node` belongs to (the character's ground carrier).
function Solids:carry(node)
    while node do
        for _, proxy in pairs(self.proxies) do
            if proxy.body == node then
                if proxy.moving then
                    local velocity = proxy.body.physics:getVelocity()
                    return velocity[1], velocity[3]
                end
                return 0, 0
            end
        end
        node = node.parent
    end
    return 0, 0
end

function Solids:release()
    for _, proxy in pairs(self.proxies) do
        proxy.body:destroy()
    end
    self.proxies = {}
end

return Solids
