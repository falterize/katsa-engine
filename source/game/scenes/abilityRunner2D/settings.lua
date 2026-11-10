local Settings = {
    layoutVersion = 3,
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
