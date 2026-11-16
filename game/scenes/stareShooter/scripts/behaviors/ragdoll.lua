-- Switches the player between walking and a physical ragdoll (the `ragdoll` plugin).
-- While it is on, the character controller is paused, its capsule follows the pelvis (so the
-- orbit camera keeps following) and does not collide.
local Ragdoll = {}
Ragdoll.__index = Ragdoll

local STAND_CLEARANCE = 1 -- how far above the pelvis the capsule is put when the player gets up

function Ragdoll.new(scene, player)
    local node = scene.world:create('Ragdoll3D', {
        name = 'PlayerRagdoll',
        source = player.body.node,
    }, player.model.root)
    return setmetatable({ scene = scene, player = player, node = node }, Ragdoll)
end

function Ragdoll:isActive()
    return self.node.active
end

-- The hips body, or nil when the ragdoll is off.
function Ragdoll:hips()
    return self.node:getBody('Hips')
end

local function setActive(self, active)
    self.node.active = active
    self.node:update() -- build or remove the bodies now, while the character still has its velocity
end

function Ragdoll:toggle()
    local player = self.player
    if self:isActive() then
        local hips = self:hips()
        local m = hips and hips:getRenderWorldMatrix()
        setActive(self, false)
        player.body.node.canCollide = true
        if m then
            player.body:teleport({ m[4], m[8] + STAND_CLEARANCE, m[12] })
        end
        player.velocity[1], player.velocity[2], player.velocity[3] = 0, 0, 0
    else
        setActive(self, true)
        if self:isActive() then
            player.body.node.canCollide = false
            player.body:setVelocity({ 0, 0, 0 })
        end
    end
end

-- Call after every physics update: keeps the capsule under the pelvis.
function Ragdoll:follow()
    local hips = self:isActive() and self:hips()
    if hips then
        local m = hips:getRenderWorldMatrix()
        self.player.body:teleport({ m[4], m[8], m[12] })
    end
end

return Ragdoll
