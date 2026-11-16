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
    self:check(not body.canCollide, 'The walking capsule stops colliding while ragdolled')
    ragdoll:toggle()
    self:check(not ragdoll:hips() and body.canCollide, 'Toggling again removes the rig')
    scene:release()
end

return Module
