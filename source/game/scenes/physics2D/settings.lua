local Settings = {
    layoutVersion = 3,
    id = 'physics2D',
    title = 'Physics 2D',
    category = 'Physics',
    tags = { 'physics', '2d' },
    frameRateLimit = 144,
    physics = { backend = 'jolt' },
    physics2D = { units = 64, gravity = { 0, -627.84 }, fixedDelta = 1 / 60, debug = true },
    world = { sky = { enabled = false }, fog = { enabled = false }, ambient = { 180, 180, 180 } },
    assets = { white = 'shared://textures/internal/white.png' },
}

return Settings
