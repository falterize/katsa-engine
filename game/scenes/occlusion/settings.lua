local Settings = {
    layoutVersion = 3,
    physics = { backend = 'auto' },
    assets = {
        bricks = { path = 'shared://textures/surfaces/bricks.jpg' },
        dirt = { path = 'shared://textures/surfaces/dirt.jpg' },
        stone = { path = 'shared://textures/surfaces/stone.png', filter = 'nearest' },
    },
}

return Settings
