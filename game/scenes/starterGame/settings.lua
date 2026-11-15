local Settings = {
    layoutVersion = 3,
    runtime = 'standalone',
    frameRateLimit = 500,
    physics = { backend = 'jolt' },
    world = { sky = { enabled = false }, fog = { enabled = false }, ambient = { 180, 180, 180 } },
    assets = { white = 'shared://textures/engine/fallback/white.png' },
}

return Settings
