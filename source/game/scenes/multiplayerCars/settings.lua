local Settings = {
    layoutVersion = 3,
    version = '1.0.0a',
    nodes = { 'vehicle' },
    plugins = { 'pathfinding' }, -- NavMap node and its debug view
    id = 'multiplayerCars',
    title = 'Multiplayer cars / LAN servers, bot and nitro ads',
    category = 'Multiplayer',
    cameraButtons = false, -- no UP/DOWN: the chase camera is orbited by dragging
    physics = { backend = 'jolt' },
}

return Settings
