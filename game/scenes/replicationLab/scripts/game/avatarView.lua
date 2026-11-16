local HeroTree = require('game.characters.heroTree')

-- What another player looks like here: the avatar prefab (the character model with its own AnimationTree)
-- driven from the replicated pose; the prefab also carries the nickname board. The local player's own view is the controller's.
local AvatarView = {}
AvatarView.__index = AvatarView

local PREFAB = 'scene://prefabs/avatar'
local WALK_SPEED = 5

-- object: the replicated Avatar entity (x, y, z, heading, speed, air, name).
function AvatarView.new(scene, object)
    local root = scene.world.prefabs:instantiate(PREFAB, { name = object.name })
    local tree = root:find('Character/Tree')
    HeroTree.init(tree)
    local self = setmetatable({ object = object, root = root, tree = tree }, AvatarView)
    root:find('Nickname/Text').text = object.name
    return self
end

function AvatarView:update()
    local object, root = self.object, self.root
    root.position = { object.x, object.y - 1, object.z }
    root.rotation = { 0, object.heading, 0 }
    self.tree:set('speed', math.min(1, object.speed / WALK_SPEED))
    HeroTree.setRate(self.tree, object.walkScale or 0, object.speed)
    self.tree:set('stance', object.crouch and 'Crouch' or 'Stand')
    self.tree:set('grounded', not object.air)
end

function AvatarView:destroy()
    self.root:destroy()
end

return AvatarView
