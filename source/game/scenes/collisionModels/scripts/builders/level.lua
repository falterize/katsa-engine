local ipairs = require('source.engine.math.array').ipairs
local Physics = require('source.engine.physics')
local UI = require('source.engine.ui')
local Models = require('source.engine.import.models')
local object = require('./object')

local CollisionModels = {}

function CollisionModels.build(self, scene)
    local model = Models.load('assets/models/examples/pyramid.obj', scene.resources)
    for i, level in ipairs({ 'Simple', 'Convex', 'Detailed' }) do
        local mesh = object.create(
            scene,
            'Pyramid.' .. level,
            { (i - 2) * 90, 0, 65 },
            { 32, 32, 32 },
            { geometry = model.parts[1].geometry, color = { i / 3, 0.6, 1 - i / 4, 1 } }
        )
        local body = scene.world:create('Body3D', {
            name = 'PyramidBody.' .. level,
            bodyType = level == 'Detailed' and 'Static' or 'Dynamic',
            position = { (i - 2) * 90, 0, 65 },
            density = 2,
            friction = 0.6,
        })
        mesh.position = { 0, 0, 0 }
        mesh.parent = body
        local collider = scene.world:create('Collider3D', {
            name = 'PyramidCollider.' .. level,
            shape = 'Geometry',
            geometrySource = level == 'Convex' and 'shared://models/examples/pyramid.obj' or mesh,
            size = level == 'Convex' and { 32, 32, 32 } or { 1, 1, 1 },
            collisionLevel = level,
        }, body)
        if level == 'Detailed' then
            -- Bake editable points independently of the visible model.
            collider:setPointsFromModel('shared://models/examples/pyramid.obj', {
                scale = { 32, 32, 32 },
            })
        end
        body:update(0)

        for n = 1, 3 do
            object.create(
                scene,
                'TestBall' .. i .. '.' .. n,
                { (i - 2) * 90 + (n - 2) * 12, 100 + n * 25, 65 },
                { 12, 12, 12 },
                { kind = 'sphere', color = { 1, 0.7, 0.2, 1 } },
                { collider = { shape = 'Sphere', radius = 6 }, restitution = 0.35 }
            )
        end
        local board = UI.newBillboard(scene.world, {
            name = 'LODLabel' .. i,
            adornee = mesh.name,
            position = { 0, 65, 0 },
            size = { 0, 230, 0, 64 },
            canvasSize = { 0, 230, 0, 64 },
            sizeMode = 'Screen',
            onTop = true,
        })
        board.ui:text({
            position = { 0, 0, 0, 0 },
            size = { 0, 230, 0, 64 },

            text = level:upper() .. ' COLLISION',
            fontSize = 22,
            backgroundColor = { 0.03, 0.08, 0.13 },
            backgroundTransparency = 1 - 0.92,
        }, board.ui.content)
    end
    local converted = Models.load('assets/models/examples/converted.glb', scene.resources)
    local parts = Models.instantiate(
        scene.world,
        converted,
        { name = 'PhysicalGLB', position = { 0, 90, 180 }, size = { 20, 20, 20 } }
    )
    local Affine = require('source.engine.math.affine')
    local Math = require('source.engine.math.math3d')
    local poses = {}
    for _, mesh in ipairs(parts) do
        poses[mesh] = Affine.copy(mesh:getWorldMatrix())
    end
    -- Body3D requires an unscaled parent; move authored scale into each independent body.
    converted.root.scale = { 1, 1, 1 }
    for _, mesh in ipairs(parts) do
        local parent = mesh.parent
        local localPose = Math.multiply(Affine.inverse(parent:getWorldMatrix()), poses[mesh])
        local position, rotation, scale = Affine.decompose(localPose)
        local body = scene.world:create('Body3D', {
            name = mesh.name .. 'Body',
            position = position,
            rotation = rotation,
            scale = scale,
            collider = Physics.modelCollider(mesh, 'Convex'),
            density = 2,
            restitution = 0.2,
        }, parent)
        mesh:setParent(body)
        mesh.poseMatrix = nil
        for _, imported in ipairs(converted.nodes) do
            if imported.instance == mesh then
                imported.physicalInstance = true
            end
        end
    end
end

return CollisionModels
