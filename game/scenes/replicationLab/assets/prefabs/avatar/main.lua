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
end)
