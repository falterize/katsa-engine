local Models = require('source.engine.import.models')
local HeroTree = require('game.characters.heroTree')

local CHARACTER = 'assets/models/characters/player.glb'

return require('source.engine.scenes.packed.scene').define(function(scene)
    local world = scene.world
    local _, root = Models.instantiate(world, Models.load(CHARACTER, scene.resources), {
        name = 'Character',
        scale = { 0.65, 0.65, 0.65 },
    })
    HeroTree.build(world, world:create('AnimationTree', { name = 'Tree' }, root))
    -- The nickname over the head; the label's text is set by whoever shows the avatar.
    local board = world:create('BillboardUI', {
        name = 'Nickname',
        position = { 0, 2.35, 0 },
        size = { 0, 1.6, 0, 0.36 },
        sizeMode = 'World3D',
        canvasSize = { 0, 400, 0, 90 },
        onTop = true,
        maxDistance = 60,
    })
    world:create('Label', {
        name = 'Text',
        size = { 1, 0, 1, 0 },
        text = 'Player',
        fontSize = 52,
        textColor = { 1, 1, 1 },
        backgroundTransparency = 1,
    }, board)
end)
