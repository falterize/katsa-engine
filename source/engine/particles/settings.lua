local Settings = {}
Settings.keys =
    { wind = true, maxParticles = true, collisionBudget = true, fixedDelta = true, maxSteps = true }
function Settings.create(dimension)
    return {
        _settingsKind = 'Particles',
        wind = dimension == 2 and { 0, 0 } or { 0, 0, 0 },
        maxParticles = 4096,
        collisionBudget = 64,
        fixedDelta = 1 / 60,
        maxSteps = 4,
    }
end
return Settings
