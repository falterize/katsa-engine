local Settings = {
    layoutVersion = 3,
    physics = { backend = 'auto' },
    plugins = { 'pathfinding' },
    assets = {
        stone = { path = 'shared://textures/surfaces/stone.png', filter = 'nearest' },
    },
}

return Settings
