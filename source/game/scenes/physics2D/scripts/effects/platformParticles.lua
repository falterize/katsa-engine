local Effects = {}

function Effects.create(state, platform)
    local ui = state.scene.ui
    local attached = ui:create('Attachment2D', {
        name = 'LocalParticlesAttachment2D',
        position = { -platform.size[1] / 2, 0 },
    }, platform)
    local detached = ui:create('Attachment2D', {
        name = 'WorldParticlesAttachment2D',
        position = { platform.size[1] / 2, 0 },
    }, platform)
    state.platformParticles = {
        ui:create('ParticleEmitter2D', {
            name = 'LockedPlatformParticles',
            simulationSpace = 'Local',
            rate = 24,
            maxParticles = 80,
            lifetime = { 0.8, 1.4 },
            shape = 'Disc',
            shapeSize = { 8, 8 },
            direction = { 0, 1 },
            spread = 35,
            speed = { 15, 35 },
            startSize = { 5, 9 },
            gravityScale = 0,
            lifetimeBindings = {
                color = {
                    { time = 0, value = { 0.2, 1, 1 } },
                    { time = 1, value = { 0.3, 0.5, 1 } },
                },
            },
        }, attached),
        ui:create('ParticleEmitter2D', {
            name = 'FreePlatformParticles',
            simulationSpace = 'World',
            rate = 24,
            maxParticles = 80,
            lifetime = { 0.6, 1.2 },
            shape = 'Line',
            shapeSize = { 12, 0 },
            direction = { 0, 1 },
            spread = 70,
            speed = { 8, 22 },
            startSize = { 4, 7 },
            gravityScale = 0,
            lifetimeBindings = {
                color = {
                    { time = 0, value = { 1, 0.7, 0.15 } },
                    { time = 1, value = { 1, 0.2, 0.05 } },
                },
            },
        }, detached),
    }
end

return Effects
