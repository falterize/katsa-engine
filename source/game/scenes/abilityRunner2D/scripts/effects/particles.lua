local Particles = {}

function Particles.create(state)
    local ui = state.scene.ui
    -- Match the 3D runner's timings, budgets and emission rates. Sprite sizes
    -- and velocities are adapted to the 2D camera's logical pixel units.
    state.burst = ui:create('ParticleEmitter2D', {
        name = 'AbilityBurst',
        layerGroup = 'Player',
        rate = 0,
        maxParticles = 160,
        lifetime = { 0.15, 0.4 },
        speed = { 45, 135 },
        spread = 180,
        startSize = { 3, 6 },
        gravityScale = 0.1,
        unlit = true,
    }, state.player)
    state.trail = ui:create('ParticleEmitter2D', {
        name = 'DashTrail',
        layerGroup = 'Player',
        rate = 0,
        maxParticles = 180,
        lifetime = { 0.15, 0.35 },
        speed = { 0, 6 },
        startSize = { 3, 6 },
        unlit = true,
    }, state.player)
end

function Particles.update(state, controller)
    state.trail.rate = controller.dashTime > 0 and 100 or controller.slideTime > 0 and 45 or 0
end

return Particles
