local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')
local Character = require('source.engine.physics.3d.character')
local UI = require('source.engine.ui')
local object = require('./object')

local NightPlayer = {}

function NightPlayer.build(self, scene)
    scene.world.environment.ambient = { 3, 5, 9 }
    scene.world.environment.sky.brightness = 0.025
    scene.world.lights[1].enabled = false
    for i = 1, 6 do
        object.create(
            scene,
            'Wall' .. i,
            { (i % 2 == 0 and 1 or -1) * 100, 25, i * 55 - 40 },
            { 25, 50, 35 },
            { surfaceAppearance = { colorMap = 'bricks' } },
            { type = 'Static' }
        )
    end
    object.create(
        scene,
        'Step',
        { 0, 5, 110 },
        { 60, 10, 35 },
        { surfaceAppearance = { colorMap = 'stone' } },
        { type = 'Static' }
    )
    object.create(
        scene,
        'Crate',
        { 25, 22, 170 },
        { 32, 44, 32 },
        { surfaceAppearance = { colorMap = 'bricks' } },
        { density = 2, friction = 0.6 }
    )
    scene.world.environment.shadows.enabled = true
    scene.world.environment.shadows.resolution = 512
    self.dayHour = 0
    self.player = object.create(
        scene,
        'Player',
        { 0, 18, -60 },
        { 16, 16, 16 },
        { kind = 'capsule', layerGroup = 'Player', color = { 0.25, 0.65, 1, 1 } },
        {
            collider = { height = 16, shape = 'Capsule', radius = 8 },
            density = 3,
            friction = 0.2,
            rotationFactor = { 0, 0, 0 },
            autoSleep = false,
        }
    )
    self.head = self.player:attachment({ name = 'Head', position = { 0, 12, 0 } })
    scene.camera.pitchLimit = 85
    scene.camera.rotation = { 0, 0, 0 }
    scene.camera.layerGroup = 'SceneCamera'
    self.first = scene.camera
    self.first.parent = scene.world.folders.Cameras
    self.first.position = { 0, 0, 0 }
    self.third = scene.world:addCamera({
        name = 'ThirdPerson',
        position = { 0, 60, -140 },
        rotation = { 0, 0, 0 },
        layerGroup = 'Default',
        pitchLimit = 85,
        drawDistance = 1000,
    })
    scene.world:setCamera(self.first)
    scene.character = Character.new(
        self.player.body,
        scene.camera,
        { height = 32, radius = 8, speed = 65, jumpSpeed = 95 }
    )
    scene.physics.beforeStep = function()
        scene.character:step()
    end
    self.flashlight = scene.world:create('SpotLight3D', {
        name = 'HeadFlashlight',
        position = { 0, 0, 0 },
        range = 330,
        radius = 135,
        brightness = 6,
        color = { 230, 240, 255 },
        forceUpdate = true,
        castShadow = true,
        shadowLayers = 1, -- Exclude the capsule containing the head emitter.
    })
    self.flashlight.parent = self.head
    self.trampoline = scene.world:create('BouncePad', {
        name = 'Trampoline',
        position = { -55, 3, 60 },
        size = { 50, 6, 50 },
        launchSpeed = 160,
    })
    self.trampoline:bindPhysics(scene.physics, self.player)
    self.trampoline:setProcess(true)
    self.portalButton = scene.world:create('SceneButton', {
        name = 'SceneButton',
        position = { 55, 3, 70 },
        size = { 35, 6, 35 },
    })
    self.portalButton:bindPhysics(
        scene.physics,
        self.player,
        scene.manager,
        require('source.game.runtime.game').new,
        'physics'
    )
    for _, data in ipairs({
        { self.trampoline, 'TRAMPOLINE' },
        { self.portalButton, 'TOUCH: PHYSICS LAB' },
    }) do
        local label = UI.newBillboard(scene.world, {
            name = data[2],
            adornee = data[1].name,
            position = { 0, 20, 0 },
            size = { 0, 240, 0, 54 },
            canvasSize = { 0, 240, 0, 54 },
            sizeMode = 'Screen',
            onTop = true,
        })
        label.ui:text({
            position = { 0, 0, 0, 0 },
            size = { 0, 240, 0, 54 },

            text = data[2],
            fontSize = 22,
            backgroundColor = { 0.04, 0.08, 0.14 },
            backgroundTransparency = 1 - 0.9,
        }, label.ui.content)
    end
    self.interactCube = Mesh.create(scene.world, {
        name = 'InteractLamp',
        position = { 0, 45, 35 },
        size = { 16, 16, 16 },
        color = { 1, 0.45, 0.1, 1 },
        lightInfluence = 0,
    })
    local detector = scene.world:create(
        'ClickDetector3D',
        { name = 'ToggleFlashlight', radius = 140 },
        self.interactCube
    )
    detector:connect('click', function()
        self.flashlight.enabled = not self.flashlight.enabled
    end)
    self:setTimeOfDay(0)
    local Controller = require('source.engine.cameras.controller')
    self.firstController = Controller.new(
        self.first,
        { mode = 'FirstPerson', target = self.head, offset = { 0, 0, 0 }, positionSmooth = 18 }
    )
    self.firstController:update(0, true)
    self.thirdController = Controller.new(self.third, {
        mode = 'ThirdPerson',
        target = self.head,
        offset = { 0, 15, 0 },
        distance = 75,
        physics = scene.physics,
        filter = scene.character.rayFilter,
    })
end

return NightPlayer
