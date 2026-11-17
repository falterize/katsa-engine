local ipairs = require('source.engine.math.array').ipairs
-- The physics body, collider and visual model of a walking character (capsule, no rotation).
local Models = require('source.engine.import.models')
local Player = require('game.characters.controller')

local Builder = {}

function Builder.create(scene)
    local settings = scene.settings.player
    local body = scene.world:create('Body3D', {
        name = 'Player',
        position = { 0, 1, 0 },
        size = { 1, 2, 1 },
        rotationFactor = { 0, 0, 0 },
        gravityScale = 0,
        autoSleep = false,
        friction = 0,
        restitution = 0,
        linearDamping = 0,
        angularDamping = 0,
    })
    local collider = scene.world:create('Collider3D', {
        name = 'Capsule',
        shape = 'Capsule',
        radius = settings.radius,
        height = settings.standingHeight - 2 * settings.radius,
    }, body)
    body:update(0)
    local registry = scene.world.layerGroups
    if not registry.bits.Outlined then
        registry:add('Outlined')
    end
    local model = Models.load('assets/models/characters/player.glb', scene.resources)
    Models.instantiate(scene.world, model, {
        name = 'CharacterVisual',
        position = { 0, -1, 0 },
        rotation = { 0, 180, 0 },
        scale = { 0.65, 0.65, 0.65 },
        parent = body,
    })
    -- The visual model is its own layer group: a Shader2D with viewLayers = 'Outlined' (the
    -- stareShooter outline) sees only it.
    for _, node in ipairs(body:getDescendants()) do
        if node:isA('Node3D') and not node:isA('Collider3D') then
            node.layerGroup = 'Outlined'
        end
    end
    local controller = Player.new(body.physics, collider, scene.camera, settings)
    controller.model = model
    return controller
end

return Builder
