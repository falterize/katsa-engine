local Mesh = require('source.engine.composition.mesh')

-- Independent worlds share immutable resources, never lighting/camera/simulation state.

local Interface = {}

function Interface.create(self)
    local scene, ui = self.scene, self.scene.ui
    for i = 1, 2 do
        local frame = ui:create('ViewportFrame', {
            _viewportAuthored = true,
            name = 'Viewport' .. i,
            position = { (i - 1) * 0.5, 12, 0, 124 },
            size = { 0.5, -24, 1, -206 },
            clip = true,
            backgroundColor = { 0.03, 0.04, 0.06 },
        }, ui.content)
        local root = ui:create('World3D', { name = 'PreviewWorld' .. i }, frame)
        local world = root._world
        world.environment.sky.enabled = false
        world.environment.debug.gizmos.enabled = false
        world.environment.ambient = i == 1 and { 100, 130, 180 } or { 180, 100, 65 }
        world.environment.shadows.enabled = true
        world.environment.shadows.resolution = 128
        local camera = root:create('Camera3D', {
            name = 'PreviewCamera',
            position = { 0, 35, -110 },
            rotation = { -9, 0, 0 },
            drawDistance = 700,
        })
        root.currentCamera = camera
        local second = root:create('Camera3D', {
            name = 'AlternateCamera',
            position = { 65, 45, -80 },
            rotation = { -13, -35, 0 },
            drawDistance = 700,
        })
        local cube = Mesh.create(root, {
            name = 'PreviewCube',
            position = { 0, 15, 35 },
            size = { 25, 30, 25 },
            surfaceAppearance = { colorMap = 'bricks' },
        })
        Mesh.create(root, {
            name = 'PreviewFloor',
            position = { 0, -3, 40 },
            size = { 160, 6, 170 },
            surfaceAppearance = { colorMap = 'stone' },
        })
        root:create('SpotLight3D', {
            name = 'PreviewSpot',
            position = { 30, 60, -20 },
            rotation = { -35, 0, 0 },
            range = 250,
            radius = 90,
            brightness = 2,
            castShadow = true,
        })
        local emitter = root:create('ParticleEmitter3D', {
            name = 'PreviewParticles',
            position = { -30, 5, 25 },
            rate = 35,
            speed = { 10, 20 },
            blendMode = 'Add',
            gravityScale = 0,
            lifetimeBindings = {
                color = require('source.engine.animation.sequence').linear(
                    i == 1 and { 0.1, 0.5, 1 } or { 1, 0.3, 0.1 },
                    i == 1 and { 0.1, 0.5, 1 } or { 1, 0.3, 0.1 }
                ),
            },
        })
        local board = root:create('BillboardUI', {
            name = 'WorldBillboard',
            position = { 0, 42, 35 },
            size = { 0, 100, 0, 24 },
            canvasSize = { 0, 100, 0, 24 },
            onTop = true,
        })
        board.ui:text({
            size = { 1, 0, 1, 0 },
            text = 'World ' .. i,
            fontSize = 14,
            backgroundColor = { 0.04, 0.06, 0.09 },
            backgroundTransparency = 0.4,
        }, board.ui.content)
        local overlay = root:create('World2D', { name = 'PreviewUI' })
        local label = overlay:text({
            position = { 0, 8, 0, 8 },
            size = { 1, -16, 0, 24 },
            text = 'Independent Environment',
            fontSize = 12,
            backgroundColor = { 0.04, 0.06, 0.1 },
        }, overlay.content)
        do
            local node = overlay:button({
                position = { 0, 8, 1, -42 },
                size = { 0.5, -12, 0, 32 },
                text = 'Camera',
                fontSize = 12,
                backgroundColor = { 0.12, 0.3, 0.42 },
            }, overlay.content)
            node:connect('press', function()
                root.currentCamera = root.currentCamera == camera and second or camera
            end)
        end
        do
            local node = overlay:button({
                position = { 0.5, 4, 1, -42 },
                size = { 0.5, -12, 0, 32 },
                text = 'Burst',
                fontSize = 12,
                backgroundColor = { 0.34, 0.16, 0.08 },
            }, overlay.content)
            node:connect('press', function()
                emitter:emit(50)
                label.text = 'Burst in World ' .. i
            end)
        end
        local type = world:registerNodeType('PreviewSpin', {
            base = 'Node',
            update = function(_, dt)
                cube.rotation[2] = cube.rotation[2] + dt * 30
            end,
        })
        world:create('PreviewSpin', { name = 'PreviewSpin' })
        self.views[i] = {
            frame = frame,
            root = root,
            world = world,
            camera = camera,
            second = second,
            ui = overlay,
            emitter = emitter,
            cube = cube,
        }
    end
end

return Interface
