local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')

local Demo = {}
Demo.__index = Demo

function Demo.new(scene)
    local self = setmetatable({ scene = scene, clicks = 0, panels = {} }, Demo)
    scene.showStats = false
    scene.camera.position = { 0, 70, -95 }
    local viewportWidth, viewportHeight = katsa.graphics.getDimensions()
    scene.camera.rotation = { viewportHeight > viewportWidth and 5 or -15, 0, 0 }
    scene.camera.drawDistance = 700
    local world = scene.world
    world.environment.ambient = { 170, 180, 195 }
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    world.environment.shadows.enabled = true
    require('scene.scripts.lighting.directional').create(world).enabled = true
    Mesh.create(world, {
        name = 'Floor',
        position = { 0, -4, 70 },
        size = { 350, 8, 240 },
        surfaceAppearance = { colorMap = 'stone' },
    })
    local cube = Mesh.create(world, {
        name = 'SixFaceCube',
        position = { -55, 30, 40 },
        size = { 45, 55, 45 },
        rotation = { 0, -20, 0 },
        color = { 0.25, 0.3, 0.4, 1 },
    })
    for _, face in ipairs({ 'Front', 'Back', 'Left', 'Right', 'Top', 'Bottom' }) do
        local panel = world:create('SurfaceUI', {
            name = face .. 'Panel',
            face = face,
            canvasSize = { 0, 360, 0, (face == 'Top' or face == 'Bottom') and 360 or 440 },
            maxDistance = 600,
        }, cube)
        self.panels[#self.panels + 1] = panel
    end
    local sign = Mesh.create(world, {
        name = 'Sign',
        position = { 45, 32, 50 },
        rotation = { 0, -15, 0 },
        size = { 60, 40, 5 },
        color = { 0.18, 0.24, 0.3, 1 },
    })
    local socket =
        world:create('Attachment3D', { name = 'SignSocket', position = { 0, 0, -4 } }, sign)
    self.socketPanel = world:create('SurfaceUI', {
        name = 'SocketPanel',
        face = 'Front',
        size = { 0, 60, 0, 40 },
        canvasSize = { 0, 480, 0, 320 },
        onTop = false,
    }, socket)
    self.panels[#self.panels + 1] = self.socketPanel
    local tile = Mesh.create(world, {
        name = 'LitterTile',
        position = { 0, 0.5, 10 },
        size = { 42, 1, 30 },
        color = {
            0.35,
            0.4,
            0.45,
            1,
        },
    })
    self.litter = world:create('Decal3D', {
        size = { 0.75, 0, 0.75, 0 },
        name = 'Litter',
        image = 'assets/textures/ui/litter.png',
        face = 'Top',
        lightInfluence = 1,
    }, tile)
    local tiled = Mesh.create(world, {
        name = 'TiledSign',
        position = { 140, 25, 105 },
        size = { 60, 45, 3 },
    })
    world:create('Decal3D', {
        name = 'Tiles',
        image = 'assets/textures/ui/litter.png',
        mode = 'Texture',
        textureSize = { 12, 12 },
        face = 'Front',
        imageRotation = 15,
        color = { 0.5, 0.9, 1 },
        transparency = 0.15,
    }, tiled)
    local grid = Mesh.create(world, {
        name = 'GridSign',
        position = { 210, 25, 105 },
        size = { 60, 45, 3 },
    })
    world:create('Decal3D', {
        name = 'AreaGrid',
        image = 'assets/textures/ui/litter.png',
        mode = 'Tiles',
        fitMode = 'Tile',
        tileSize = { 0.25, 0, 0.25, 0 },
        tileOffset = { 4, 4 },
        face = 'Front',
    }, grid)
    self.overlay = world:create('SurfaceUI', {
        name = 'OnTopExample',
        face = 'Front',
        canvasSize = { 0, 240, 0, 120 },
        size = { 0, 28, 0, 14 },
        spatialPosition = { 0, 30, 0 },
        onTop = true,
        zIndex = 2,
    }, socket)
    self.movingSupport = Mesh.create(world, {
        name = 'MovingSupport',
        position = { 35, 85, 120 },
        size = { 12, 12, 12 },
        color = { 0.3, 0.8, 0.5, 1 },
    })
    local attachment = world:create(
        'Attachment3D',
        { name = 'BillboardSocket', position = { 0, 12, 0 }, inheritScale = false },
        self.movingSupport
    )
    self.attachmentBoard = world:create('BillboardUI', {
        name = 'AttachmentBillboard',
        adornee = attachment,
        position = { 0, 0, 0 },
        offset = { 0, 18, 0 },
        supportSize = { 24, 24, 12 },
        debugEnabled = true,
        rotation = { 12, 20, 8 },
        sizeMode = 'Screen',
        size = { 0, 210, 0, 160 },
        canvasSize = { 0, 240, 0, 180 },
        maxDistance = 400,
        onTop = false,
    })
    world:setInteractionSource(scene.camera) -- Explicit spectator interaction origin.
    local clickTarget = Mesh.create(world, {
        name = 'ClickTarget',
        position = { 0, 18, 0 },
        size = { 24, 36, 24 },
        color = {
            0.8,
            0.35,
            0.12,
            1,
        },
    })
    self.detector =
        world:create('ClickDetector3D', { name = 'CubeClick', radius = 300 }, clickTarget)
    self.detector:connect('clicked', function()
        self.clicks = self.clicks + 1
        clickTarget.color = { 0.2, 0.7, 0.4, 1 }
    end)
    self.attachment = attachment
    self.elapsed = 0
    self.offsetMode = 'Support'
    self.attachmentClicks = 0
    return self
end

function Demo:update(dt)
    self.elapsed = self.elapsed + dt
    self.movingSupport.position[1] = 35 + math.sin(self.elapsed) * 24
    self.movingSupport.rotation[2] = self.elapsed * 30
    self.movingSupport.rotation[3] = math.sin(self.elapsed * 0.6) * 25
    self.scene.world:updateNodes(dt)
    self.status.text = 'Panel presses: '
        .. self.clicks
        .. ' | Orange cube: 3D tap / support offsets / tilted UI / Texture + Tiles'
end

return Demo
