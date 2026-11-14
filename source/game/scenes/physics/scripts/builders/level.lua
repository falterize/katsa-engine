local Mesh = require('source.engine.composition.mesh')
local object = require('./object')

local PhysicsExample = {}

function PhysicsExample.build(self, scene)
    for x = 1, 4 do
        for y = 1, 4 do
            object.create(
                scene,
                'Stack' .. x .. '.' .. y,
                { (x - 2.5) * 22, y * 22, 70 },
                { 20, 20, 20 },
                { color = { 0.2 + x * 0.15, 0.4, y / 5, 1 } },
                {
                    density = 1 + x,
                    friction = 0.45,
                    restitution = 0.05,
                    linearDamping = 0.05,
                    angularDamping = 0.1,
                }
            )
        end
    end
    object.create(
        scene,
        'Ball',
        { -65, 95, 25 },
        { 28, 28, 28 },
        { kind = 'sphere', color = { 1, 0.5, 0.15, 1 } },
        {
            collider = { shape = 'Sphere', radius = 14 },
            density = 1,
            restitution = 0.8,
            friction = 0.2,
        }
    )
    object.create(
        scene,
        'Capsule',
        { 70, 90, 30 },
        { 20, 20, 20 },
        { kind = 'capsule', color = { 0.3, 0.8, 1, 1 } },
        { collider = { height = 20, shape = 'Capsule', radius = 10 }, density = 2, friction = 0.6 }
    )
    local anchor = object.create(
        scene,
        'Anchor',
        { -100, 100, 130 },
        { 12, 12, 12 },
        { color = { 1, 0.8, 0.1, 1 } },
        { type = 'Static' }
    )
    local weight = object.create(
        scene,
        'Pendulum',
        { -100, 45, 130 },
        { 24, 24, 24 },
        { color = { 0.8, 0.2, 0.3, 1 } },
        { velocity = { 35, 0, 0 } }
    )
    scene.physics:createJoint(
        'Spherical',
        anchor.physics,
        weight.physics,
        { anchor1 = { 0, 0, 0 }, anchor2 = { 0, 55, 0 } }
    )
    local world = scene.world
    local pivot = world:create(
        'Node3D',
        { name = 'PhysicsSupport', position = { -130, 0, 80 }, rotation = { 0, 0, 20 } }
    )
    self.independentBody = world:create('Body3D', {
        name = 'IndependentBall',
        position = { 0, 75, 0 },
        size = { 16, 16, 16 },
        restitution = 0.4,
    }, pivot)
    self.independentCollider = world:create(
        'Collider3D',
        { name = 'EditableCollider', shape = 'Sphere', radius = 8, size = { 16, 16, 16 } },
        self.independentBody
    )
    Mesh.create(world, {
        name = 'IndependentVisual',
        kind = 'sphere',
        size = { 16, 16, 16 },
        color = { 0.9, 0.45, 0.15, 1 },
    }, self.independentBody)
    local trigger = world:create('Body3D', {
        name = 'TriggerVolume',
        bodyType = 'Static',
        isTrigger = true,
        position = { -130, 30, 80 },
        size = { 44, 14, 44 },
    })
    self.triggerBody = trigger
    local indicator = Mesh.create(world, {
        name = 'TriggerVisual',
        size = { 44, 14, 44 },
        color = { 0.2, 0.65, 0.9, 1 },
        transparency = 0.7,
        castShadow = false,
    }, trigger)
    trigger:connect('triggerEntered', function(other)
        if other == self.independentBody.physics then
            indicator.color = { 0.2, 1, 0.25, 1 }
        end
    end)
    trigger:connect('triggerExited', function(other)
        if other == self.independentBody.physics then
            indicator.color = { 0.2, 0.65, 0.9, 1 }
        end
    end)
end

return PhysicsExample
