local Settings = {
    layoutVersion = 3,
    physics = { backend = 'auto' },
    presentation = { navigation = false, menuKey = 'tab', menuButton = true },
    player = {
        walkSpeed = 5,
        runSpeed = 8,
        jumpPower = 6,
        acceleration = 50,
        friction = 35,
        gravity = 24.5,
        radius = 0.5,
        standingHeight = 2,
        crouchingHeight = 1,
        heightSpeed = 10,
        crouchSpeedFactor = 0.65,
        blendSpeed = 5,
    },
    camera = { sensitivity = 0.25, zoomSpeed = 1, minDistance = 0, maxDistance = 100, fov = 75 },
    -- The game server runs inside this process on its own headless world; the client joins it
    -- through the loopback like any other player.
    net = { port = 47820, bots = 3, simulate = nil },
}

return Settings
