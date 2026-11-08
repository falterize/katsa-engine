local Settings = {
    layoutVersion = 3,
    id = 'starterGame',
    title = 'Starter Game',
    runtime = 'standalone',
    category = 'Games',
    tags = { 'game', 'example' },
    frameRateLimit = 500,
    physics = { backend = 'jolt' },
    world = { sky = { enabled = false }, fog = { enabled = false }, ambient = { 180, 180, 180 } },
    assets = { white = 'shared://textures/internal/white.png' },
}

return Settings
