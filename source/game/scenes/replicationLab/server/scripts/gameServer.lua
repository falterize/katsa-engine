local Net = require('source.engine.net')
local World3D = require('source.engine.world.world')
local AvatarEntity = require('../../scripts.shared.avatarEntity')
local Arena = require('../../scripts.shared.arena')
local Roster = require('./roster')
local Rounds = require('./rounds')
local Bots = require('./bots')
local Chat = require('./chat')

-- The game server: its own headless world, the replicated nodes (Round, Players, Coins, Platform),
-- the player avatars and the chat. It never touches the client's world.
local GameServer = {}
GameServer.__index = GameServer

-- resources: a scope that outlives the server. options: port, bots, simulate, maxPlayers.
function GameServer.new(resources, options)
    local world = World3D.new(resources)
    local server = Net.Server.new({}, {
        port = options.port,
        maxPlayers = options.maxPlayers or 8,
        simulate = options.simulate,
    })
    server:replicate(world)
    AvatarEntity.define(server)
    local self = setmetatable({ world = world, server = server, avatars = {}, time = 0 }, GameServer)
    self.roster = Roster.new(world)
    self.chat = Chat.new(server, function(player)
        return player.name
    end)
    self.teleportRemote = server:remote('Teleport')
    self.rounds = Rounds.new(world, self.roster, function(avatar, position)
        self:teleport(avatar, position)
    end, function(text)
        self.chat:say(text)
    end)
    self:buildPlatform()
    self.bots = Bots.new(server, self.roster, options.bots or 0)
    server.playerAdded:connect(function(player)
        self:addPlayer(player)
    end)
    server.playerRemoved:connect(function(player)
        self.roster:remove(player.id)
        self.avatars[player.id] = nil
    end)
    return self
end

-- A platform that moves on the server only; the position is a replicated property, so every
-- client sees it slide without any client code.
function GameServer:buildPlatform()
    self.platform = self.world:create('Mesh3D', {
        name = 'Platform',
        position = { 0, 0.15, 14 },
        size = { 5, 0.3, 5 },
        color = { 0.27, 0.63, 0.86, 1 },
        replicated = true,
        replicatedProperties = { 'position', 'size', 'color' },
    })
end

function GameServer:addPlayer(player)
    local at = Arena.point(Arena.lobby, Arena.lobbyRadius, (player.id * 0.17) % 1, 0.5)
    local avatar, netId =
        self.server:spawn('Avatar', { name = player.name, x = at[1], y = at[2], z = at[3] }, player)
    self.avatars[player.id] = avatar
    self.roster:add(player.id, player.name, avatar)
    self.chat:say(player.name .. ' joined')
    self.teleportRemote:fireClient(player, at[1], at[2], at[3])
    return netId
end

-- Moves an avatar. A player's own client simulates the character, so the server asks it to move
-- (Teleport remote) and accepts the long jump for a moment; a bot is simply placed.
function GameServer:teleport(avatar, position)
    avatar.x, avatar.y, avatar.z = position[1], position[2], position[3]
    avatar.allowJump = 1.5
    for _, player in pairs(self.server:getPlayers()) do
        if self.avatars[player.id] == avatar then
            self.teleportRemote:fireClient(player, position[1], position[2], position[3])
        end
    end
end

function GameServer:update(dt)
    self.time = self.time + dt
    self.platform.position = { math.sin(self.time * 0.6) * 8, 0.15, 14 }
    for _, avatar in pairs(self.avatars) do
        avatar.allowJump = math.max(0, avatar.allowJump - dt)
    end
    self.rounds:update(dt)
    self.bots:update(dt, self.rounds)
    self.server:update(dt)
end

function GameServer:start()
    self.server:start()
    return self
end

function GameServer:stop()
    self.server:stop()
    self.world.root:destroy()
end

return GameServer
