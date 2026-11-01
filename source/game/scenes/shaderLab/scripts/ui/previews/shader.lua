local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')

local Preview = {}

function Preview.create(scene, frame, name)
    local root = scene.ui:create('World3D', { name = name }, frame)
    local world = root._world
    local environment = world.environment
    environment.sky.enabled = false
    environment.shadows.enabled = false
    environment.fog.enabled = false
    environment.debug.gizmos.enabled = false
    environment.ambient = { 220, 230, 245 }
    require('scene.scripts.lighting.directional').create(world).enabled = true
    environment.brightness = 1
    root.currentCamera =
        root:create('Camera3D', { position = { 0, 28, -82 }, rotation = { -7, 0, 0 } })
    local cube = Mesh.create(root, {
        name = 'PatternCube',
        position = { 0, 12, 35 },
        size = { 38, 34, 38 },
        surfaceAppearance = { colorMap = 'bricks' },
    })
    Mesh.create(root, {
        name = 'PreviewFloor',
        position = { 0, -8, 35 },
        size = { 160, 4, 180 },
        color = { 0.5, 0.65, 0.8, 1 },
        surfaceAppearance = { colorMap = 'stone' },
    })
    Mesh.create(root, {
        name = 'Stripe',
        position = { -32, 15, 45 },
        size = { 8, 40, 8 },
        color = {
            1,
            0.35,
            0.08,
            1,
        },
    })
    world:registerNodeType('PreviewSpin', {
        base = 'Node',
        update = function(_, dt)
            cube.rotation[2] = cube.rotation[2] + dt * 24
        end,
    })
    root:create('PreviewSpin', { name = 'PreviewSpin' })
    local overlay = root:create('World2D', { name = 'CalibrationUI' })
    local colors = {
        { 1, 0.15, 0.15 },
        { 1, 0.8, 0.1 },
        { 0.1, 0.9, 0.4 },
        { 0.15, 0.55, 1 },
        {
            0.8,
            0.2,
            1,
        },
    }
    for i, color in ipairs(colors) do
        overlay:container({
            position = { (i - 1) / 5, 0, 0, 0 },
            size = { 1 / 5, 0, 0, 22 },
            backgroundColor = color,
        }, overlay.content)
    end
    overlay:text({
        position = { 0, 8, 1, -40 },
        size = { 1, -16, 0, 28 },
        text = 'SHARP DETAILS / 012345',
        textScaled = true,
        maxTextSize = 16,
        backgroundColor = { 0.025, 0.04, 0.065 },
    }, overlay.content)
    return root, cube
end

return Preview
