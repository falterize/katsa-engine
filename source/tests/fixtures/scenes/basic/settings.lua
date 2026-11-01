local Settings = {
    id = 'packageFixture',
    title = 'Scene package fixture',
    category = 'Validation',
    physics = { backend = 'oimo' },
    nodes = { 'Counter' },
    assets = {
        thumbnail = 'scene://textures/checker.png',
        click = 'scene://audio/click.wav',
        ribbon = 'scene://models/skinRibbon.gltf',
    },
}

return Settings
