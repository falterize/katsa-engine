local HeroTree = require('game.characters.heroTree')

-- What another player looks like here: the avatar prefab (the character model with its own AnimationTree)
-- driven from the replicated pose, with the nickname over its head. The local player's own view is the controller's.
local AvatarView = {}
AvatarView.__index = AvatarView

local PREFAB = 'scene://prefabs/avatar'
local WALK_SPEED = 5

local function nameplate(world, parent, text)
    local board = world:create('BillboardUI', {
        name = 'Nickname',
        position = { 0, 2.35, 0 },
        size = { 0, 1.6, 0, 0.36 },
        sizeMode = 'World3D',
        canvasSize = { 0, 400, 0, 90 },
        onTop = true,
        maxDistance = 60,
    }, parent)
    board.ui:text({
        size = { 1, 0, 1, 0 },
        text = text,
        fontSize = 52,
        textColor = { 1, 1, 1 },
        backgroundTransparency = 1,
    }, board.ui.content)
    return board
end

-- object: the replicated Avatar entity (x, y, z, heading, speed, air, name).
function AvatarView.new(scene, object)
    local root = scene.world.prefabs:instantiate(PREFAB, { name = object.name })
    local tree = root:find('Character/Tree')
    HeroTree.init(tree)
    local self = setmetatable({ object = object, root = root, tree = tree }, AvatarView)
    self.nameplate = nameplate(scene.world, root, object.name)
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
