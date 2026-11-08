local Settings = {
    layoutVersion = 3,
    id = 'abilityRunner2D',
    title = 'Ability Runner 2D / checkpoints, dash and pixel animation',
    category = 'Physics',
    tags = { 'game', '2d', 'physics', 'animation', 'platformer' },
    frameRateLimit = 144,
    physics2D = {
        unitsPerMeter = 64,
        gravity = 700,
        gravityDirection = { 0, -1 },
        fixedDelta = 1 / 60,
        interpolate = true,
    },
    world = { sky = { enabled = false }, fog = { enabled = false } },
}

return Settings
