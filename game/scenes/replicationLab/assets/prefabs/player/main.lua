return require('source.engine.scenes.packed.scene').define(function(scene, context)
    scene:createPhysics3D({ unitsPerMeter = 1, gravity = { 0, -24.5, 0 }, fixedDelta = 1 / 60 })
    local world = scene.world
    local body = world:create('Body3D', {
        name = 'Player',
        position = { 0, 1, 0 },
        size = { 1, 2, 1 },
        collider = { shape = 'Capsule', radius = 0.5, height = 1 },
        rotationFactor = { 0, 0, 0 },
        gravityScale = 0,
        autoSleep = false,
        friction = 0,
        restitution = 0,
        linearDamping = 0,
        angularDamping = 0,
    })
    world:create('Collider3D', { name = 'Capsule', shape = 'Capsule', radius = 0.5, height = 1 }, body)
    -- Prefabs nest: the character is its own prefab, in the assets of the scene that loads this one.
    local visual = world.prefabs:instantiate(
        '../scene://prefabs/avatar',
        { name = 'Visual', position = { 0, -1, 0 } },
        body
    )
    visual:find('Nickname'):destroy() -- one does not read one's own nickname
end)
