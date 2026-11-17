-- Cloned bodies keep their rotation lock; an indexed Trimesh collider hands its mesh to the body;
-- NavMap3D reads the nav settings of the Body3D that owns a hit collider.
local PointCollider = require('source.engine.physics.3d.pointCollider')

local Module = {}

function Module.run(self)
    local Application = require('game.runtime.application')
    local scene = Application.new(self.manager, 'replicationLab')
    scene:load()
    local player = scene.demo.player.body
    for _ = 1, 20 do
        scene:update(1 / 60, 1 / 60)
    end
    player:setAngularVelocity({ 6, 0, 6 })
    for _ = 1, 60 do
        scene:update(1 / 60, 1 / 60)
    end
    local rotation = player.node.rotation
    self:check(
        math.abs(rotation[1]) < 0.01 and math.abs(rotation[3]) < 0.01,
        'The prefab player stays upright after an angular kick'
    )

    local points = { { 0, 0, 0 }, { 1, 0, 0 }, { 0, 0, 1 }, { 1, 0, 1 } }
    local descriptor = PointCollider.build({
        points = points,
        indices = { 1, 3, 2, 2, 3, 4 },
        collisionLevel = 'Trimesh',
        maxTriangles = 2,
        position = { 0, 0, 0 },
        rotation = { 0, 0, 0 },
    }, { bodyType = 'Static' })
    local mesh = descriptor.children[1]
    self:check(
        mesh.shape == 'Mesh' and #mesh.indices == 6 and #mesh.vertices == 4,
        'An indexed Trimesh keeps its points and indices as a mesh'
    )
    local ok = pcall(PointCollider.build, {
        points = points,
        indices = { 1, 3, 2, 2, 3, 4 },
        collisionLevel = 'Trimesh',
        maxTriangles = 1,
        position = { 0, 0, 0 },
        rotation = { 0, 0, 0 },
    }, { bodyType = 'Static' })
    self:check(not ok, 'An indexed Trimesh still honours maxTriangles')
end

return Module
