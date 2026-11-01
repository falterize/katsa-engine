local Mesh = require('source.engine.composition.mesh')

local Spatial = {}

function Spatial.create(state)
    local scene = state.scene
    local physics = scene:createPhysics({ unitsPerMeter = 2, gravity = { 0, -19.62, 0 } })
    scene.camera.position = { 0, 5, -14 }
    scene.camera.rotation = { -12, 0, 0 }
    local function box(name, position, size, kind)
        local mesh = Mesh.create(scene.world, {
            name = name,
            position = position,
            size = size,
            color = { 0.75, 0.35, 0.2 },
            surfaceAppearance = { colorMap = 'white' },
        })
        physics:addBody(
            mesh,
            { type = kind or 'Dynamic', collider = { shape = 'Box', size = size } }
        )
        return mesh
    end
    box('Floor3D', { 0, -3, 5 }, { 16, 1, 16 }, 'Static')
    for i = 1, 8 do
        box('Crate3D_' .. i, { i % 3 * 2 - 2, i * 1.8, 5 }, { 1.3, 1.3, 1.3 })
    end
    local owner =
        scene.world:create('Body3D', { name = 'EditedHullBody3D', position = { 4, 6, 5 } })
    local mesh = Mesh.create(scene.world, {
        name = 'HullSource3D',
        size = { 2, 2, 2 },
        color = { 0.2, 0.8, 0.5 },
        surfaceAppearance = { colorMap = 'white' },
    }, owner)
    local collider = scene.world:create('Collider3D', { collisionLevel = 'Convex' }, owner)
    local points, indices = collider:getPointsFromMesh(mesh)
    for _, point in ipairs(points) do
        if point[2] > 0 then
            point[1] = point[1] + 0.4
        end
    end
    collider:setPoints(points, indices)
    -- Independent dimensions exchange gameplay events, never native collision contacts.
    state.ball:connect('triggerEnter', function()
        for _, body in ipairs(physics.bodies) do
            if body.type == 'Dynamic' then
                body:applyImpulse({ 0, 8, 0 })
            end
        end
    end)
end

return Spatial
