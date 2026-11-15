local Settings = {
    layoutVersion = 3,
    nodes = { 'bouncePad', 'sceneButton' },
    physics = { backend = 'auto' },
    assets = {
        bricks = { path = 'shared://textures/surfaces/bricks.jpg' },
        dirt = { path = 'shared://textures/surfaces/dirt.jpg' },
        stone = { path = 'shared://textures/surfaces/stone.png', filter = 'nearest' },
    },
}

return Settings
