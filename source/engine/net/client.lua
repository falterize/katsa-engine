-- Game client. Mirrors the server's entities, predicts the local player's input and
-- interpolates everything else.
--
--   local client = Net.Client.new(context, { address = '127.0.0.1', port = 7777, name = 'Ann' })
--   client:define('Avatar', sameDefinitionAsServer)
--   client.inputProvider = function() return { moveX = 1 } end
--   client:connect()
--   -- every frame: client:update(dt)
local Codec = require('./codec')
local Link = require('./link')
local P = require('./protocol')
local Registry = require('./registry')
local Remote = require('./remote')
local Signal = require('./signal')

local Client = {}
Client.__index = Client

local REDUNDANT_INPUTS = 3
local BUFFER_SECONDS = 1.5

function Client.new(context, options)
    options = options or {}
    return setmetatable({
        context = context,
        options = options,
        registry = Registry.new(),
        state = 'idle',
        players = {},
        entities = {},
        remotes = {},
        requests = {},
        nextRequest = 1,
        pending = {},
        inputSeq = 0,
        accumulator = 0,
        clock = 0,
        timeOffset = nil,
        interpolationDelay = options.interpolationDelay or 0.1,
        inputProvider = function()
            return {}
        end,
        connected = Signal.new(),
        disconnected = Signal.new(),
        playerJoined = Signal.new(),
        playerLeft = Signal.new(),
        entitySpawned = Signal.new(),
        authorityChanged = Signal.new(),
        entityRemoved = Signal.new(),
    }, Client)
end

function Client:define(kind, definition)
    return self.registry:define(kind, definition)
end

function Client:remote(name)
    local remote = self.remotes[name]
    if not remote then
        remote = Remote.new(self, name)
        self.remotes[name] = remote
    end
    return remote
end

function Client:connect()
    assert(self.state == 'idle', 'Client is already connecting')
    self.host = katsa.net.connect({
        address = self.options.address,
        port = self.options.port,
        timeout = self.options.timeout,
    })
    self.link = Link.new(self.host.server, self.options.simulate)
    self.state = 'connecting'
    return self
end

function Client:isConnected()
    return self.state == 'connected'
end

function Client:getPing()
    return self.host and self.host.server:getPing() or 0
end

-- Estimated current server time (seconds), smoothed from snapshot timestamps.
function Client:getServerTime()
    return self.timeOffset and self.clock + self.timeOffset or 0
end

function Client:getObject(netId)
    local entity = self.entities[netId]
    return entity and entity.object
end

local function send(self, writer, channel)
    self.link:send(writer:finish(), channel)
end

function Client:sendRemote(_, name, count, args)
    local writer = Codec.writer()
    writer:u8(P.REMOTE)
    writer:string(name)
    writer:values(args, count)
    local remote = self.remotes[name]
    send(self, writer, remote and remote.channel or P.RELIABLE)
end

function Client:sendRequest(name, callback, count, args)
    local id = self.nextRequest
    self.nextRequest = id + 1
    self.requests[id] = callback
    local writer = Codec.writer()
    writer:u8(P.REQUEST)
    writer:u32(id)
    writer:string(name)
    writer:values(args, count)
    send(self, writer, P.RELIABLE)
end

local function sendHello(self)
    local writer = Codec.writer()
    writer:u8(P.HELLO)
    writer:u8(P.VERSION)
    writer:string(self.options.name or 'Player')
    self.link:send(writer:finish(), P.RELIABLE)
end

local function noteServerTime(self, serverTime)
    local offset = serverTime - self.clock
    if not self.timeOffset then
        self.timeOffset = offset
    else
        -- Smooth against jitter, but follow the server if it drifts.
        self.timeOffset = self.timeOffset + (offset - self.timeOffset) * 0.1
    end
end

local function removeEntity(self, netId)
    local entity = self.entities[netId]
    if entity then
        self.entities[netId] = nil
        self.entityRemoved:fire(entity.object, entity.kind, netId)
        if entity.definition.destroy then
            entity.definition.destroy(entity.object)
        end
    end
end

local function handleWelcome(self, reader)
    self.playerId = reader:u16()
    self.tickRate = reader:u8()
    self.snapshotRate = reader:u8()
    local serverTime = reader:f64()
    reader:u32()
    self.tickDelta = 1 / self.tickRate
    self.snapshotEvery = math.max(1, math.floor(self.tickRate / self.snapshotRate + 0.5))
    noteServerTime(self, serverTime + self:getPing() / 2000)
    for _ = 1, reader:u16() do
        local id = reader:u16()
        self.players[id] = { id = id, name = reader:string() }
    end
    self.localPlayer = { id = self.playerId, name = self.options.name or 'Player', isLocal = true }
    self.players[self.playerId] = self.localPlayer
    self.state = 'connected'
    self.connected:fire(self.localPlayer)
end

local function handleSpawn(self, reader)
    local netId = reader:u32()
    local kind = reader:string()
    local authorityId = reader:u16()
    local args = reader:value()
    local definition = self.registry:get(kind)
    local state = Registry.readState(definition, reader)
    if self.entities[netId] then
        removeEntity(self, netId)
    end
    local object = definition.create(self.context, args, netId)
    Registry.apply(definition, object, state)
    local entity = {
        id = netId,
        kind = kind,
        definition = definition,
        object = object,
        authorityId = authorityId,
        buffer = { { time = self:getServerTime(), state = state } },
        local_ = authorityId == self.playerId,
    }
    self.entities[netId] = entity
    self.entitySpawned:fire(object, kind, netId, entity.local_)
end

local function replay(self, entity, ack)
    local definition = entity.definition
    for seq = ack + 1, self.inputSeq do
        local input = self.pending[seq]
        if input ~= nil and definition.simulate then
            definition.simulate(entity.object, input, self.tickDelta)
        end
    end
end

local SLOW_SNAPSHOT_GAP = 0.15 -- seconds between two received snapshots that is worth a log line
local STARVED_LOG = 0.1 -- seconds an entity had nothing newer than the render time

local function handleSnapshot(self, reader)
    local tick = reader:u32()
    local serverTime = reader:f64()
    local ack = reader:u32()
    noteServerTime(self, serverTime)
    -- Diagnostics for choppy remote motion: the wall time between snapshots and how far the server
    -- clock jumped in that time. A gap far above the snapshot period means the data arrived late.
    local now = katsa.timer.getTime()
    local last = self.lastSnapshotAt
    self.lastSnapshotAt = now
    if last and now - last > SLOW_SNAPSHOT_GAP then
        katsa.log.warn(
            ('Snapshot gap: %.0f ms since the previous one (server tick +%d, %.0f ms of server time)'):format(
                (now - last) * 1000,
                tick - (self.lastSnapshotTick or tick),
                (serverTime - (self.lastSnapshotTime or serverTime)) * 1000
            ),
            'Net',
            false
        )
    end
    self.lastSnapshotTick, self.lastSnapshotTime = tick, serverTime
    self.snapshotsReceived = (self.snapshotsReceived or 0) + 1
    for _ = 1, reader:u16() do
        local entity = self.entities[reader:u32()]
        if not entity then
            -- Spawn not received yet (reliable arrives later than a snapshot): skip the rest.
            return
        end
        local state = Registry.readState(entity.definition, reader)
        local definition = entity.definition
        if entity.local_ and definition.simulate and not definition.clientAuthoritative then
            -- Server state at input `ack`, then everything the server has not processed yet.
            Registry.apply(definition, entity.object, state)
            replay(self, entity, ack)
        elseif not (entity.local_ and definition.clientAuthoritative) then
            local buffer = entity.buffer
            buffer[#buffer + 1] = { time = serverTime, state = state }
            while #buffer > 2 and buffer[2].time < serverTime - BUFFER_SECONDS do
                table.remove(buffer, 1)
            end
        end
    end
    for seq in pairs(self.pending) do
        if seq <= ack then
            self.pending[seq] = nil
        end
    end
end

local function handleMessage(self, data)
    local reader = Codec.reader(data)
    local kind = reader:u8()
    if kind == P.WELCOME then
        handleWelcome(self, reader)
    elseif kind == P.REJECT then
        self.rejection = reader:string()
    elseif kind == P.SPAWN then
        handleSpawn(self, reader)
    elseif kind == P.DESPAWN then
        removeEntity(self, reader:u32())
    elseif kind == P.AUTHORITY then
        local entity = self.entities[reader:u32()]
        local id = reader:u16()
        if entity then
            entity.authorityId = id
            entity.local_ = id == self.playerId
            -- Restart interpolation from what is on screen so nothing jumps.
            entity.buffer = {
                {
                    time = self:getServerTime(),
                    state = Registry.capture(entity.definition, entity.object),
                },
            }
            self.authorityChanged:fire(entity.object, id, entity.local_)
        end
    elseif kind == P.SNAPSHOT then
        handleSnapshot(self, reader)
    elseif kind == P.PLAYER_JOIN then
        local player = { id = reader:u16(), name = reader:string() }
        self.players[player.id] = player
        self.playerJoined:fire(player)
    elseif kind == P.PLAYER_LEAVE then
        local player = self.players[reader:u16()]
        if player then
            self.players[player.id] = nil
            self.playerLeft:fire(player)
        end
    elseif kind == P.REMOTE then
        local remote = self.remotes[reader:string()]
        local args, count = reader:values()
        if remote and remote.clientHandler then
            remote.clientHandler(unpack(args, 1, count))
        end
    elseif kind == P.RESPONSE then
        local callback = self.requests[reader:u32()]
        if callback then
            local args, count = reader:values()
            callback(unpack(args, 1, count))
        end
    end
end

local function finish(self, reason)
    if self.state == 'disconnected' then
        return
    end
    self.state = 'disconnected'
    for netId in pairs(self.entities) do
        removeEntity(self, netId)
    end
    self.disconnected:fire(self.rejection or reason)
end

local function sendInputs(self)
    local first = math.max(self.inputSeq - REDUNDANT_INPUTS + 1, 1)
    local writer = Codec.writer()
    writer:u8(P.INPUT)
    writer:u8(self.inputSeq - first + 1)
    for seq = first, self.inputSeq do
        writer:u32(seq)
        writer:value(self.pending[seq])
    end
    send(self, writer, P.SEQUENCED)
end

local function inputTick(self)
    local input = self.inputProvider()
    self.inputSeq = self.inputSeq + 1
    self.pending[self.inputSeq] = input
    sendInputs(self)
    for _, entity in pairs(self.entities) do
        local definition = entity.definition
        if entity.local_ and definition.simulate and not definition.clientAuthoritative then
            definition.simulate(entity.object, input, self.tickDelta)
        end
    end
    -- Bound memory if the server stops acknowledging.
    self.pending[self.inputSeq - 120] = nil
end

local function sendOwnedState(self)
    local writer, count, body = Codec.writer(), 0, Codec.writer()
    for id, entity in pairs(self.entities) do
        if entity.local_ and entity.definition.clientAuthoritative then
            body:u32(id)
            Registry.writeState(
                entity.definition,
                body,
                Registry.capture(entity.definition, entity.object)
            )
            count = count + 1
        end
    end
    if count > 0 then
        writer:u8(P.CLIENT_STATE)
        writer:u16(count)
        self.link:send(writer:finish() .. body:finish(), P.SEQUENCED)
    end
end

local function interpolate(self)
    local renderTime = self:getServerTime() - self.interpolationDelay
    for _, entity in pairs(self.entities) do
        local definition = entity.definition
        if not (entity.local_ and (definition.simulate or definition.clientAuthoritative)) then
            local buffer = entity.buffer
            local from, to = buffer[1], buffer[#buffer]
            for index = 1, #buffer - 1 do
                if buffer[index + 1].time >= renderTime then
                    from, to = buffer[index], buffer[index + 1]
                    break
                end
            end
            local span = to.time - from.time
            local t = span > 0 and math.max(0, math.min(1, (renderTime - from.time) / span)) or 1
            -- Starving: the render time is already past the newest snapshot, so the entity holds
            -- still until the next one arrives and then jumps.
            -- A parked entity sends nothing (unchanged state), so only count one that was moving.
            local moving = #buffer > 1 and not Registry.sameState(definition, from.state, to.state)
            if moving and renderTime > to.time + 0.02 then
                entity.starvedFor = (entity.starvedFor or 0) + self.frameDelta
                entity.starvedPast = renderTime - to.time
            elseif entity.starvedFor then
                if entity.starvedFor >= STARVED_LOG then
                    katsa.log.warn(
                        ('Entity %d held still for %.0f ms (render time %.0f ms past the newest snapshot, %d buffered)'):format(
                            entity.id,
                            entity.starvedFor * 1000,
                            (entity.starvedPast or 0) * 1000,
                            #buffer
                        ),
                        'Net',
                        false
                    )
                end
                entity.starvedFor = nil
            end
            for _, field in ipairs(definition.parsedFields) do
                local a, b = from.state[field.name], to.state[field.name]
                local value
                if a ~= nil and b ~= nil then
                    value = field.type.lerp(a, b, t)
                else
                    value = b or a
                end
                if value ~= nil then
                    Registry.write(definition, entity.object, field.name, value)
                end
            end
        end
    end
end

-- Once a second: how many snapshot packets arrived. Logged as info for the first seconds after the
-- connection (to compare with the server's own count) and as a warning whenever it drops far below
-- the snapshot rate, together with ENet's loss estimate and ping.
function Client:logRate(dt)
    if self.state ~= 'connected' then
        return
    end
    self.rateTimer = (self.rateTimer or 0) + dt
    self.rateAge = (self.rateAge or 0) + dt
    if self.rateTimer < 1 then
        return
    end
    local seconds, count = self.rateTimer, self.snapshotsReceived or 0
    self.rateTimer, self.snapshotsReceived = 0, 0
    local expected = (self.snapshotRate or 20) * seconds
    local low = count < expected * 0.75
    if low or self.rateAge < 12 then
        local peer = self.host and self.host.server
        local text = ('Client received %d snapshot packets in %.1f s (expected %.0f), ENet loss %.0f%%, ping %d ms'):format(
            count,
            seconds,
            expected,
            peer and peer:getLoss() * 100 or 0,
            peer and peer:getPing() or 0
        )
        if low then
            katsa.log.warn(text, 'Net', false)
        else
            katsa.log.log(text, 'Net')
        end
    end
end

function Client:update(dt)
    if not self.host then
        return
    end
    self.clock = self.clock + dt
    self.frameDelta = dt
    self:logRate(dt)
    local host = self.host
    for event in host:poll() do
        if event.type == 'connect' then
            sendHello(self)
        elseif event.type == 'receive' then
            handleMessage(self, event.data)
        elseif event.type == 'disconnect' then
            finish(self, event.reason)
        end
        if self.host ~= host then
            -- A handler (the scene leaving after the host went away) already closed the client.
            return
        end
    end
    if self.state == 'connected' then
        self.accumulator = math.min(self.accumulator + dt, self.tickDelta * 5)
        self.tickCount = self.tickCount or 0
        while self.accumulator >= self.tickDelta do
            self.accumulator = self.accumulator - self.tickDelta
            self.tickCount = self.tickCount + 1
            inputTick(self)
            if self.tickCount % self.snapshotEvery == 0 then
                sendOwnedState(self)
            end
        end
        interpolate(self)
    end
    self.link:update(dt)
    if self.host then
        self.host:flush()
    end
end

function Client:disconnect()
    if self.host then
        self.host.server:disconnect(0, 'now')
        self.host:flush()
        self.host:close()
        self.host = nil
        finish(self, 0)
    end
end

return Client
