local Content = {}

function Content.create(scene)
    scene.root:find('World3D/World2D'):create('Camera2D', { name = 'Camera2D', position = { 640, -360 }, zoom = 1 })
    local physics = scene:createPhysics2D()
    scene.root:find('World3D/World2D').autoUpdatePhysics = false
    scene.statsHelp = '2D shapes, joints and triggers. Use the on-screen controls; F3: Stats.'
    scene.root:find('World3D/World2D').layoutMode = 'Fit'
    local state = { scene = scene, physics = physics }
    scene.package:require('scripts.builders.playground').create(state)
    scene.root:find('World3D').currentCamera = nil
    state.emitter = scene.root:find('World3D/World2D'):create('ParticleEmitter2D', {
        name = 'Physics2DParticleFountain',
        position = { 180, -380 },
        rate = 35,
        direction = { 0, 1 },
        speed = { 100, 180 },
        spread = 25,
        gravityScale = 0.4,
        collisionEnabled = true,
        lifetime = { 2, 4 },
        startSize = { 6, 12 },
        offscreenBehavior = 'Simulate',
        shape = 'Disc',
        shapeSize = { 30, 12 },
        lifetimeBindings = {
            color = {
                { time = 0, value = { 0.2, 0.8, 1 } },
                {
                    time = 1,
                    value = { 1, 0.3, 0.5 },
                },
            },
        },
    })

    return state
end

return Content
