-- The ragdoll toggle in stareShooter: bodies appear, fall to the floor and are removed again.
local Application = require('game.runtime.application')

local Module = {}

local function step(scene, count)
    for _ = 1, count do
        scene:update(1 / 60, 1 / 60)
    end
end

function Module.run(self)
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    step(scene, 30)
    local ragdoll = scene.demo.ragdoll
    self:check(not ragdoll:isActive() and not ragdoll:hips(), 'The ragdoll starts switched off')
    ragdoll:toggle()
    local head, hips = ragdoll.node:getBody('Head'), ragdoll:hips()
    self:check(hips and head and ragdoll.node.status == '', 'Toggling builds the humanoid rig')
    step(scene, 120)
    local hipsY = hips:getRenderWorldMatrix()[8]
    local headY = head:getRenderWorldMatrix()[8]
    self:check(hipsY < 0.6 and headY < 0.6, 'The ragdoll falls and lies on the floor')
    local body = scene.demo.player.body.node
    self:check(not body.physics.canCollide, 'The walking capsule stops colliding while ragdolled')
    -- Every segment's collider is a regular Collider3D node, feet and hands included.
    local foot, collider = ragdoll.node:getBody('FootL'), nil
    for _, child in ipairs(foot and foot.children or {}) do
        if child.className == 'Collider3D' then
            collider = child
        end
    end
    self:check(ragdoll.node:getBody('HandR') and collider, 'Segments have Collider3D children, feet and hands too')
    ragdoll:toggle()
    body:update(0)
    self:check(not ragdoll:hips() and body.physics.canCollide, 'Toggling again removes the rig')
    -- A running fall must not slide on forever: the floor grips and the ragdoll comes to rest.
    scene.demo.player.body:setVelocity({ 0, 0, 9 })
    ragdoll:toggle()
    step(scene, 60 * 5)
    local v = ragdoll:hips().physics:getVelocity({})
    self:check(math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2) < 0.3, 'A ragdoll that fell while running stops sliding')
    ragdoll:toggle()
    scene:release()
end

return Module
