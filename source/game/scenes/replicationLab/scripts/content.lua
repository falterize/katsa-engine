local Level = require('./builders.level')
local Body = require('source.game.characters.playerBody')
local Orbit = require('source.game.characters.orbit')
local Input = require('source.game.characters.thirdPersonInput')
local HeroTree = require('source.game.characters.heroTree')
local GameServer = require('../server.scripts.gameServer')
local Session = require('./game.session')
local AvatarView = require('./game.avatarView')
local Solids = require('./game.solids')

-- Scene composition: the local character, an in-process game server, and the client session that
-- joins it. The server and the client share nothing but the network.
local Content = {}
Content.__index = Content

local WALK_SPEED = 5

-- The animation graph of the local character; the same HeroTree every avatar uses.
local function buildTree(scene, player)
    local tree = scene.world:create('AnimationTree', { name = 'HeroTree' }, player.model.root)
    HeroTree.build(scene.world, tree)
    tree:set('speed', 0)
    tree:set('stride', 1)
    tree:set('crouchRate', 0)
    tree:set('stance', 'Stand')
    tree:set('squat', 0)
    tree:set('grounded', true)
    return tree
end

function Content.new(scene)
    scene:createPhysics3D({
        unitsPerMeter = 1,
        gravity = { 0, -24.5, 0 },
        fixedDelta = 1 / 60,
        interpolate = true,
    })
    Level.create(scene)
    local player = Body.create(scene)
    local orbit = Orbit.new(scene, player)
    scene.character = player
    scene.input = Input.new(scene, player, orbit)
    scene.input.keyHandler = function(key)
        -- Enter opens the chat box; once it is open the key must reach the box to send the line.
        local chat = scene.demo and scene.demo.chat
        if key == 'return' and chat and not chat.typing then
            chat:open()
            return true
        end
    end
    orbit:update()
    local settings = scene.settings.net
    local self = setmetatable({
        scene = scene,
        player = player,
        orbit = orbit,
        tree = buildTree(scene, player),
        views = {},
    }, Content)
    self.host = GameServer.new(scene.resources, settings):start()
    self.nickname = 'Player' .. math.random(100, 999)
    self.session = Session.new(scene.world, {
        parent = scene.root:find('World3D'),
        port = settings.port,
        nickname = self.nickname,
        simulate = settings.simulate,
    }, {
        avatarAdded = function(object, netId, owned)
            if not owned then
                self.views[netId] = AvatarView.new(scene, object)
            end
        end,
        avatarRemoved = function(netId)
            if self.views[netId] then
                self.views[netId]:destroy()
                self.views[netId] = nil
            end
        end,
        teleport = function(x, y, z)
            self:teleport(x, y, z)
        end,
        chat = function(author, text)
            if self.chat then
                self.chat:add(author, text)
            end
        end,
    })
    self.solids = Solids.new(scene, self.session)
    player.carrier = function(node)
        return self.solids:carry(node)
    end
    self.session:connect()
    return self
end

-- The server asked this client to move its character (a round started or ended).
function Content:teleport(x, y, z)
    local body = self.player.body
    body:teleport({ x, y, z })
    self.player.velocity[1], self.player.velocity[2], self.player.velocity[3] = 0, 0, 0
end

-- One frame after the physics step: drive the animation graph and publish the pose.
function Content:updateNetwork(dt)
    local player = self.player
    local matrix = player.body.node:getRenderWorldMatrix()
    local speed = math.sqrt(player.velocity[1] ^ 2 + player.velocity[3] ^ 2)
    self.tree:set('speed', math.min(1, speed / WALK_SPEED))
    HeroTree.setRate(self.tree, player.walkScale, speed)
    self.tree:set('stance', player.input.crouch and 'Crouch' or 'Stand')
    self.tree:set('grounded', player.grounded)
    player.model.root.rotation[2] = math.deg(player.smooth.yaw:sampleFor(player.body.space))
    self.session:publish(
        matrix[4],
        matrix[8],
        matrix[12],
        player.model.root.rotation[2],
        speed,
        not player.grounded,
        player.walkScale,
        player.input.crouch == true
    )
    self.host:update(dt)
    self.session:update(dt)
    self.solids:update(dt)
    for _, view in pairs(self.views) do
        view:update()
    end
    if self.hud then
        self.hud:update()
    end
end

function Content:release()
    self.scene.physics.beforeStep = nil
    katsa.mouse.setRelativeMode(false)
    self.solids:release()
    self.session:release()
    self.host:stop()
end

return Content
