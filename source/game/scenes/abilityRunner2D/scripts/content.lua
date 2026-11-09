local Content = {}

function Content.create(scene)
    local state = {
        scene = scene,
        spawn = { 100, 30 },
        checkpoint = 0,
        deaths = 0,
        checkpoints = {},
        touchLeft = {},
        touchRight = {},
    }
    local ui = scene.ui
    ui.layoutMode, ui.autoUpdatePhysics = 'Fit', false
    state.physics = scene:createPhysics2D()
    scene.world.root.currentCamera = nil
    scene.statsHelp = 'A/D or touch: move; Space: double jump; Shift: dash; C: slide; R: respawn.'
    scene.package:require('scripts.builders.level').create(state)
    state.player = ui:create('Body2D', {
        name = 'PlayerBody2D',
        position = { state.spawn[1], state.spawn[2] },
        fixedRotation = true,
        bullet = true,
        friction = 0,
        linearDamping = 0,
        autoSleep = false,
    })
    state.collider = ui:create('Collider2D', {
        name = 'PlayerCollider2D',
        size = { 24, 32 },
    }, state.player)
    state.sprite = ui:create('ImageRect', {
        name = 'PlayerSprite8x8',
        imageMode = 'XML',
        xml = 'scene://animations/player.xml',
        layerGroup = 'Player',
        size = { 1, 0, 1, 0 },
        backgroundTransparency = 1,
    }, state.collider)
    ui:create('Camera2D', {
        name = 'RunnerCamera2D',
        followTarget = state.player,
        offset = { 200, 150 },
        position = { 300, 180 },
        referenceHeight = 720,
    })
    state.effects = scene.package:require('scripts.effects.particles')
    state.effects.create(state)
    state.controller = scene.package:require('scripts.behaviors.player').new(state)
    state.player:connect('triggerEnter', function(other)
        if other.runnerCheckpoint then
            state.controller:checkpoint(other.runnerCheckpoint)
        elseif other.runnerKillZone then
            state.controller:respawn()
        elseif other.runnerFinish then
            state.completed = true
        end
    end)
    return state
end

return Content
