-- Authoritative game server. Owns the entities, simulates player input at a fixed tick and sends
-- state snapshots to every client.
--
--   local server = Net.Server.new(context, { port = 7777 })
--   server:define('Avatar', { create = ..., fields = { 'position:vec2' }, simulate = ... })
--   server.playerAdded:connect(function(player) server:spawn('Avatar', {}, player) end)
--   server:start()
--   -- every frame: server:update(dt)
local Codec = require('source.engine.net.codec')
local Link = require('source.engine.net.link')
local P = require('source.engine.net.protocol')
local Registry = require('source.engine.net.registry')
local Remote = require('source.engine.net.remote')
local Signal = require('source.engine.net.signal')

local Server = {}
Server.__index = Server

local Player = {}
Player.__index = Player

function Player:getPing()
    return self.peer:getPing()
end

function Player:kick(reason)
    self.server:kick(self, reason)
end

local function pack(...)
    return { ... }, select('#', ...)
end

local MAX_PACKET = 900
local MAX_QUEUED_INPUTS = 12

function Server.new(context, options)
    options = options or {}
    local self = setmetatable({
        context = context,
        options = options,
        registry = Registry.new(),
        tickRate = options.tickRate or 60,
        snapshotRate = options.snapshotRate or 20,
        maxPlayers = options.maxPlayers or 16,
        players = {},
        peerPlayers = {},
        entities = {},
        remotes = {},
        pendingRequests = 0,
        nextPlayerId = 1,
        nextNetId = 1,
        tick = 0,
        time = 0,
        accumulator = 0,
        playerAdded = Signal.new(),
        playerRemoved = Signal.new(),
        ticked = Signal.new(),
    }, Server)
    self.tickDelta = 1 / self.tickRate
    self.snapshotEvery = math.max(1, math.floor(self.tickRate / self.snapshotRate + 0.5))
    self.keyframeEvery = self.tickRate -- one full refresh per second repairs lost snapshots
    return self
end

function Server:define(kind, definition)
    return self.registry:define(kind, definition)
end

function Server:remote(name)
    local remote = self.remotes[name]
    if not remote then
        remote = Remote.new(self, name)
        self.remotes[name] = remote
    end
    return remote
end

function Server:start()
    local net = katsa.net
    self.host = net.listen({ port = self.options.port or 0, maxPeers = self.maxPlayers + 4 })
    self.port = self.options.port
    if self.options.advertise then
        self:advertise(self.options.advertise)
    end
    return self
end

-- Announces this server on the local network. info: { name = 'Room', game = 'Cars', ... }.
function Server:advertise(info)
    self.advertiseInfo = info
    self.announcer = self.announcer or katsa.net.lan.announce({ port = self.options.discoveryPort })
    self:refreshAdvertisement()
end

function Server:refreshAdvertisement()
    if self.announcer then
        local info = self.advertiseInfo
        local fields = {
            info.name or 'Katsa server',
            tostring(self.port),
            tostring(self:getPlayerCount()),
            tostring(self.maxPlayers),
            info.game or '',
        }
        self.announcer:setInfo(table.concat(fields, '|'))
    end
end

function Server:getPlayerCount()
    local count = 0
    for _ in pairs(self.players) do
        count = count + 1
    end
    return count
end

function Server:getPlayers()
    local list = {}
    for _, player in pairs(self.players) do
        list[#list + 1] = player
    end
    table.sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
end

local function send(player, writer, channel)
    return player.link:send(writer:finish(), channel)
end

function Server:sendRemote(player, name, count, args)
    local writer = Codec.writer()
    writer:u8(P.REMOTE)
    writer:string(name)
    writer:values(args, count)
    local remote = self.remotes[name]
    send(player, writer, remote and remote.channel or P.RELIABLE)
end

-- Spawns an entity of a defined kind and replicates it. `args` reaches create() on every
-- machine (must be serializable). `authority` is the Player whose input drives it, or nil.
function Server:spawn(kind, args, authority)
    local definition = self.registry:get(kind)
    local netId = self.nextNetId
    self.nextNetId = netId + 1
    local object = definition.create(self.context, args or {}, netId)
    local entity = {
        id = netId,
        kind = kind,
        definition = definition,
        object = object,
        args = args or {},
        authority = authority,
        sent = {},
    }
    self.entities[netId] = entity
    for _, player in pairs(self.players) do
        if player.ready then
            self:sendSpawn(player, entity)
        end
    end
    return object, netId
end

function Server:sendSpawn(player, entity)
    local definition = entity.definition
    if definition.relevant and not definition.relevant(player, entity.object) then
        return
    end
    local writer = Codec.writer()
    writer:u8(P.SPAWN)
    writer:u32(entity.id)
    writer:string(entity.kind)
    writer:u16(entity.authority and entity.authority.id or 0)
    writer:value(entity.args)
    Registry.writeState(definition, writer, Registry.capture(definition, entity.object))
    send(player, writer, P.RELIABLE)
    player.known[entity.id] = true
end

function Server:findEntity(objectOrId)
    if type(objectOrId) == 'number' then
        return self.entities[objectOrId]
    end
    for _, entity in pairs(self.entities) do
        if entity.object == objectOrId then
            return entity
        end
    end
end

function Server:getNetId(object)
    local entity = self:findEntity(object)
    return entity and entity.id
end

function Server:despawn(objectOrId)
    local entity = self:findEntity(objectOrId)
    if not entity then
        return
    end
    self.entities[entity.id] = nil
    local writer = Codec.writer()
    writer:u8(P.DESPAWN)
    writer:u32(entity.id)
    for _, player in pairs(self.players) do
        if player.known[entity.id] then
            player.known[entity.id] = nil
            player.sent[entity.id] = nil
            send(player, writer, P.RELIABLE)
        end
    end
    if entity.definition.destroy then
        entity.definition.destroy(entity.object)
    end
end

-- Hands an entity to another player (or nil for the server). The new authority's input drives
-- `simulate` from then on; every client that knows the entity is told, so a car's driver can
-- change while it keeps its state.
function Server:setAuthority(objectOrId, player)
    local entity = self:findEntity(objectOrId)
    if not entity or entity.authority == player then
        return entity ~= nil
    end
    entity.authority = player
    local writer = Codec.writer()
    writer:u8(P.AUTHORITY)
    writer:u32(entity.id)
    writer:u16(player and player.id or 0)
    for _, other in pairs(self.players) do
        if other.known[entity.id] then
            other.sent[entity.id] = nil -- resend the full state to everyone
            send(other, writer, P.RELIABLE)
        end
    end
    return true
end

function Server:getAuthority(objectOrId)
    local entity = self:findEntity(objectOrId)
    return entity and entity.authority
end

-- Disconnects a player. `reason` (text) is shown to them: the client's `disconnected` signal
-- fires with it. They may join again afterwards.
function Server:kick(player, reason)
    if type(reason) == 'string' then
        local writer = Codec.writer()
        writer:u8(P.REJECT)
        writer:string(reason)
        send(player, writer, P.RELIABLE)
        player.link:update(1e9)
    end
    player.peer:disconnect(type(reason) == 'number' and reason or 1, 'later')
end

local function removePlayer(self, player)
    self.players[player.id] = nil
    self.peerPlayers[player.peer.id] = nil
    for _, entity in pairs(self.entities) do
        if entity.authority == player then
            entity.authority = nil
            if entity.definition.despawnWithAuthority ~= false then
                self:despawn(entity.id)
            end
        end
    end
    local writer = Codec.writer()
    writer:u8(P.PLAYER_LEAVE)
    writer:u16(player.id)
    for _, other in pairs(self.players) do
        send(other, writer, P.RELIABLE)
    end
    self.playerRemoved:fire(player)
    self:refreshAdvertisement()
end

local function handleHello(self, peer, reader)
    local version = reader:u8()
    local name = reader:string()
    local link = Link.new(peer, self.options.simulate)
    local function reject(reason)
        local writer = Codec.writer()
        writer:u8(P.REJECT)
        writer:string(reason)
        link:send(writer:finish(), P.RELIABLE)
        link:update(1e9)
        peer:disconnect(1, 'later')
    end
    if version ~= P.VERSION then
        return reject('Protocol version mismatch')
    end
    if self:getPlayerCount() >= self.maxPlayers then
        return reject('Server is full')
    end
    -- Names are unique among connected players, ignoring case (options.uniqueNames = false to allow
    -- duplicates).
    if self.options.uniqueNames ~= false then
        local wanted = name:lower()
        for _, other in pairs(self.players) do
            if other.name:lower() == wanted then
                return reject('The name "' .. name .. '" is already taken')
            end
        end
    end
    local player = setmetatable({
        id = self.nextPlayerId,
        name = name,
        peer = peer,
        link = link,
        server = self,
        inputs = {},
        lastInput = nil,
        lastReceivedSeq = 0,
        lastAppliedSeq = 0,
        known = {},
        sent = {},
        data = {},
        ready = false,
    }, Player)
    self.nextPlayerId = self.nextPlayerId + 1
    self.players[player.id] = player
    self.peerPlayers[peer.id] = player

    local writer = Codec.writer()
    writer:u8(P.WELCOME)
    writer:u16(player.id)
    writer:u8(self.tickRate)
    writer:u8(self.snapshotRate)
    writer:f64(self.time)
    writer:u32(self.tick)
    local others = {}
    for _, other in pairs(self.players) do
        if other ~= player then
            others[#others + 1] = other
        end
    end
    writer:u16(#others)
    for _, other in ipairs(others) do
        writer:u16(other.id)
        writer:string(other.name)
    end
    send(player, writer, P.RELIABLE)

    local join = Codec.writer()
    join:u8(P.PLAYER_JOIN)
    join:u16(player.id)
    join:string(player.name)
    for _, other in ipairs(others) do
        send(other, join, P.RELIABLE)
    end
    self.playerAdded:fire(player)
    local ids = {}
    for id in pairs(self.entities) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        self:sendSpawn(player, self.entities[id])
    end
    player.ready = true
    self:refreshAdvertisement()
end

local function handleInput(player, reader)
    local count = reader:u8()
    for _ = 1, count do
        local seq = reader:u32()
        local input = reader:value()
        if seq > player.lastReceivedSeq then
            player.lastReceivedSeq = seq
            player.inputs[#player.inputs + 1] = { seq = seq, input = input }
            if #player.inputs > MAX_QUEUED_INPUTS then
                table.remove(player.inputs, 1)
            end
        end
    end
end

local function handleClientState(self, player, reader)
    for _ = 1, reader:u16() do
        local entity = self.entities[reader:u32()]
        if entity and entity.authority == player and entity.definition.clientAuthoritative then
            Registry.apply(
                entity.definition,
                entity.object,
                Registry.readState(entity.definition, reader)
            )
        elseif entity then
            Registry.readState(entity.definition, reader)
        else
            return
        end
    end
end

local function handleMessage(self, player, data)
    local reader = Codec.reader(data)
    local kind = reader:u8()
    if kind == P.INPUT then
        handleInput(player, reader)
    elseif kind == P.CLIENT_STATE then
        handleClientState(self, player, reader)
    elseif kind == P.REMOTE then
        local remote = self.remotes[reader:string()]
        local args, count = reader:values()
        if remote and remote.serverHandler then
            remote.serverHandler(player, unpack(args, 1, count))
        end
    elseif kind == P.REQUEST then
        local id = reader:u32()
        local remote = self.remotes[reader:string()]
        local args, count = reader:values()
        local results, resultCount = {}, 0
        if remote and remote.requestHandler then
            results, resultCount = pack(remote.requestHandler(player, unpack(args, 1, count)))
        end
        local writer = Codec.writer()
        writer:u8(P.RESPONSE)
        writer:u32(id)
        writer:values(results, math.min(resultCount, 255))
        send(player, writer, P.RELIABLE)
    end
end

function Server:poll()
    for event in self.host:poll() do
        if event.type == 'receive' then
            local player = self.peerPlayers[event.peer.id]
            if event.channel == P.RELIABLE and event.data:byte(1) == P.HELLO then
                if not player then
                    handleHello(self, event.peer, Codec.reader(event.data:sub(2)))
                end
            elseif player then
                handleMessage(self, player, event.data)
            end
        elseif event.type == 'disconnect' then
            local player = self.peerPlayers[event.peer.id]
            if player then
                removePlayer(self, player)
            end
        end
    end
end

local function simulatePlayers(self)
    for _, player in pairs(self.players) do
        local entry = table.remove(player.inputs, 1)
        if entry then
            player.lastInput = entry.input
            player.lastAppliedSeq = entry.seq
        end
        -- With no new input the previous one is held, as a client holding its keys would.
        if player.lastInput ~= nil then
            for _, entity in pairs(self.entities) do
                local definition = entity.definition
                if
                    entity.authority == player
                    and definition.simulate
                    and not definition.clientAuthoritative
                then
                    definition.simulate(entity.object, player.lastInput, self.tickDelta)
                end
            end
        end
    end
end

-- Entities with a `relevant` filter appear and disappear per player as the filter changes.
local function refreshRelevance(self, player)
    for _, entity in pairs(self.entities) do
        local relevant = entity.definition.relevant
        if relevant then
            local visible = relevant(player, entity.object)
            if visible and not player.known[entity.id] then
                self:sendSpawn(player, entity)
            elseif not visible and player.known[entity.id] then
                local writer = Codec.writer()
                writer:u8(P.DESPAWN)
                writer:u32(entity.id)
                send(player, writer, P.RELIABLE)
                player.known[entity.id], player.sent[entity.id] = nil, nil
            end
        end
    end
end

local function sendSnapshots(self, keyframe)
    for _, player in pairs(self.players) do
        if player.ready then
            refreshRelevance(self, player)
            local writer, count, body = Codec.writer(), 0, nil
            local function begin()
                writer = Codec.writer()
                writer:u8(P.SNAPSHOT)
                writer:u32(self.tick)
                writer:f64(self.time)
                writer:u32(player.lastAppliedSeq)
                body, count = Codec.writer(), 0
            end
            local function flush()
                if count > 0 then
                    writer:u16(count)
                    local data = writer:finish() .. body:finish()
                    player.link:send(data, P.SEQUENCED)
                end
                begin()
            end
            begin()
            local ids = {}
            for id in pairs(self.entities) do
                ids[#ids + 1] = id
            end
            table.sort(ids)
            local size = 0
            for _, id in ipairs(ids) do
                local entity = self.entities[id]
                local definition = entity.definition
                local owned = entity.authority == player and definition.clientAuthoritative
                if player.known[id] and not owned then
                    local state = Registry.capture(definition, entity.object)
                    local previous = player.sent[id]
                    if
                        keyframe
                        or not previous
                        or not Registry.sameState(definition, state, previous)
                    then
                        player.sent[id] = state
                        body:u32(id)
                        Registry.writeState(definition, body, state)
                        count = count + 1
                        size = size + 24 + #definition.parsedFields * 8
                        if size > MAX_PACKET then
                            flush()
                            size = 0
                        end
                    end
                end
            end
            flush()
        end
    end
end

-- Advances the server by `dt` seconds of wall time: network, fixed ticks, snapshots.
function Server:update(dt)
    self:poll()
    self.accumulator = math.min(self.accumulator + dt, self.tickDelta * 5)
    while self.accumulator >= self.tickDelta do
        self.accumulator = self.accumulator - self.tickDelta
        self.tick = self.tick + 1
        self.time = self.time + self.tickDelta
        simulatePlayers(self)
        self.ticked:fire(self.tickDelta)
        if self.tick % self.snapshotEvery == 0 then
            sendSnapshots(self, self.tick % self.keyframeEvery == 0)
        end
    end
    for _, player in pairs(self.players) do
        player.link:update(dt)
    end
    if self.announcer then
        self.announcer:update()
    end
    self.host:flush()
end

function Server:stop()
    if self.announcer then
        self.announcer:close()
        self.announcer = nil
    end
    if self.host then
        self.host:close()
        self.host = nil
    end
    for _, entity in pairs(self.entities) do
        if entity.definition.destroy then
            entity.definition.destroy(entity.object)
        end
    end
    self.entities, self.players, self.peerPlayers = {}, {}, {}
end

return Server
