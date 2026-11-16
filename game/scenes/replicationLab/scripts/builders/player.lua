local Player = require('game.characters.controller')
local HeroTree = require('game.characters.heroTree')

-- The local character: the controller drives the capsule body and the visual of the `player`
-- prefab (a body wearing the avatar prefab, assets/prefabs/player).
local PlayerBody = {}

function PlayerBody.create(scene)
    local root = scene.world.prefabs:instantiate('scene://prefabs/player', { name = 'LocalPlayer' })
    local body = root:find('Player')
    local collider = body:find('Capsule')
    body:update(0)
    local controller = Player.new(body.physics, collider, scene.camera, scene.settings.player)
    -- The controller turns the character through its model root.
    controller.model = { root = body:find('Visual/Character') }
    controller.tree = controller.model.root:find('Tree')
    HeroTree.init(controller.tree)
    return controller
end

return PlayerBody
