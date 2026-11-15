local Net = require('source.engine.net')
local AvatarEntity = require('../shared.avatarEntity')

-- The client side of the lab: the connection, the replicated nodes and the three things a player
-- can do over the network (move, chat, be teleported). Everything else the screen shows is
-- replicated nodes and attributes that the server owns.
local Session = {}
Session.__index = Session

-- options: port, nickname, simulate, parent (the World3D node the server's nodes replicate into).
-- callbacks: avatarAdded(object, netId, owned), avatarRemoved(netId),
-- teleport(x, y, z), chat(author, text).
function Session.new(world, options, callbacks)
    local client = Net.Client.new({}, {
        address = '127.0.0.1',
        port = options.port,
        name = options.nickname,
        simulate = options.simulate,
    })
    local self = setmetatable(
        { client = client, world = world, parent = options.parent, callbacks = callbacks },
        Session
    )
    AvatarEntity.define(client)
    client:replicate(world)
    client.entitySpawned:connect(function(object, _, netId, owned)
        if owned then
            self.own = object
        end
        callbacks.avatarAdded(object, netId, owned)
    end)
    client.entityRemoved:connect(function(_, _, netId)
        callbacks.avatarRemoved(netId)
    end)
    self.chatRemote = client:remote('Chat')
    self.chatRemote:onClient(callbacks.chat)
    client:remote('Teleport'):onClient(callbacks.teleport)
    return self
end

function Session:connect()
    self.client:connect()
end

function Session:update(dt)
    self.client:update(dt)
end

function Session:sendChat(text)
    self.chatRemote:fireServer(text)
end

-- The replicated nodes the server made, by name (nil until they have arrived).
function Session:node(name)
    return self.parent:find(name, false)
end

-- Publishes the local character's pose; the server validates it and the others interpolate it.
function Session:publish(x, y, z, heading, speed, air)
    local own = self.own
    if own then
        own.x, own.y, own.z, own.heading, own.speed, own.air = x, y, z, heading, speed, air
    end
end

function Session:release()
    self.client:disconnect()
end

return Session
