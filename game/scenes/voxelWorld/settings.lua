local Settings = {
    layoutVersion = 3,
    physics = { backend = 'auto' },
    -- The block tile sheet (4x4 tiles of 16x16 pixels): tools/assets/generateBlockAtlas.py.
    assets = {
        blocks = { path = 'scene://textures/blocks.png', filter = 'nearest' },
    },
    presentation = { navigation = false, menuKey = 'tab', menuButton = true },
    cameraButtons = false,
    world = {
        seed = 1337,
        viewDistance = 6, -- chunks around the player that are drawn
        maxGenerating = 6, -- terrain requests in flight at once
        maxMeshing = 6, -- mesh requests in flight at once
        meshesPerFrame = 3, -- finished meshes uploaded per frame (keeps frames short)
    },
    player = {
        walkSpeed = 4.3,
        sprintSpeed = 6.5,
        flySpeed = 11,
        flySprintSpeed = 22,
        jumpSpeed = 9,
        gravity = 32,
        reach = 6,
        eyeHeight = 1.62,
        sensitivity = 0.15,
        fov = 75,
    },
}

return Settings
