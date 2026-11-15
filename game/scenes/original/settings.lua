local Settings = {
    layoutVersion = 3,
    physics = { backend = 'auto' },
    assets = {
        bricks = { path = 'shared://textures/surfaces/bricks.jpg' },
        deltarune = { path = 'scene://textures/deltarune.jpg', filter = 'nearest' },
        dirt = { path = 'shared://textures/surfaces/dirt.jpg' },
        second = { path = 'scene://textures/second.jpg' },
        skebob = { path = 'scene://textures/skebob.jpg' },
        stone = { path = 'shared://textures/surfaces/stone.png', filter = 'nearest' },
    },
}

return Settings
