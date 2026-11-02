-- Push-to-talk voice chat over the game's network connection.
--
-- The microphone (katsa.audio.openCapture) is read while the talk key is held, compressed with
-- μ-law to one byte per sample and sent to the server in ~80 ms packets over an unreliable
-- remote. The server relays each packet to the other players, whose clients decode it into a
-- queue source placed at the speaker, so voices are 3D and fade with distance. Desktop only: no
-- microphone, no capture.
local MuLaw = require('source.engine.audio.muLaw')

local Voice = {}
Voice.__index = Voice

local SAMPLE_RATE = 12000
local PACKET_SAMPLES = 960 -- 80 ms
local MAX_PACKET = 2400
local SPEAKING_HOLD = 0.4 -- how long the indicator stays after the last packet

-- Server side: relay. `server` is the GameServer.
function Voice.bindServer(server)
    local remote = server.server:remote('voice'):unreliable()
    local last = {}
    remote:onServer(function(player, bytes)
        if type(bytes) ~= 'string' or #bytes == 0 or #bytes > MAX_PACKET then
            return
        end
        -- 80 ms of audio per packet; allow bursts but not floods.
        local now = server.server.time
        local gate = last[player.id] or { time = now, tokens = 8 }
        gate.tokens = math.min(8, gate.tokens + (now - gate.time) * 12.5)
        gate.time = now
        last[player.id] = gate
        if gate.tokens < 1 then
            return
        end
        gate.tokens = gate.tokens - 1
        remote:fireOthers(player, player.id, bytes)
    end)
end

-- options: positionOf(playerId) -> x, y, z or nil; sampleRate
function Voice.new(gameClient, options)
    options = options or {}
    local self = setmetatable({
        client = gameClient,
        rate = options.sampleRate or SAMPLE_RATE,
        positionOf = options.positionOf,
        speakers = {}, -- playerId -> { source, last }
        pending = {},
        pendingCount = 0,
        talking = false,
        now = 0,
        speakingSince = {},
    }, Voice)
    gameClient.client:remote('voice'):unreliable():onClient(function(id, bytes)
        self:receive(id, bytes)
    end)
    return self
end

function Voice:isAvailable()
    if self.capture == nil then
        local capture = katsa.audio.openCapture(self.rate)
        self.capture = capture or false
    end
    return self.capture ~= false
end

-- Hold to talk: true while the key is down.
function Voice:setTalking(talking)
    if talking == self.talking then
        return
    end
    if talking and not self:isAvailable() then
        return
    end
    self.talking = talking
    if talking then
        self.capture:start()
    else
        self:send(true)
        self.capture:stop()
        self.capture:read() -- drop what is left
    end
end

function Voice:isTalking()
    return self.talking
end

function Voice:send(flush)
    local ffi = require('ffi')
    if self.capture and self.talking or flush then
        local pcm, count = self.capture:read()
        if pcm then
            local merged = ffi.new('int16_t[?]', self.pendingCount + count)
            if self.pendingCount > 0 then
                ffi.copy(merged, self.pending, self.pendingCount * 2)
            end
            ffi.copy(merged + self.pendingCount, pcm, count * 2)
            self.pending, self.pendingCount = merged, self.pendingCount + count
        end
    end
    local offset = 0
    while self.pendingCount - offset >= PACKET_SAMPLES or (flush and self.pendingCount - offset > 0) do
        local count = math.min(PACKET_SAMPLES, self.pendingCount - offset)
        self.client.client:remote('voice'):fireServer(MuLaw.encode(self.pending + offset, count))
        offset = offset + count
    end
    if offset > 0 then
        local rest = self.pendingCount - offset
        local ffi2 = require('ffi')
        local remaining = ffi2.new('int16_t[?]', math.max(1, rest))
        if rest > 0 then
            ffi2.copy(remaining, self.pending + offset, rest * 2)
        end
        self.pending, self.pendingCount = remaining, rest
    end
end

function Voice:receive(id, bytes)
    if type(bytes) ~= 'string' or #bytes == 0 then
        return
    end
    local speaker = self.speakers[id]
    if not speaker then
        speaker = { source = katsa.audio.newQueueSource(self.rate) }
        self.speakers[id] = speaker
    end
    local pcm, count = MuLaw.decode(bytes)
    -- A long backlog means the connection stalled: drop it rather than delay the voice.
    if (speaker.source:getQueued() or 0) > 6 then
        return
    end
    speaker.source:queue(pcm, count)
    self.speakingSince[id] = self.now
end

-- Moves each voice to its speaker and ages the speaking indicator.
function Voice:update(dt)
    self.now = self.now + dt
    if self.talking then
        self:send(false)
    end
    for id, speaker in pairs(self.speakers) do
        local x, y, z = nil, nil, nil
        if self.positionOf then
            x, y, z = self.positionOf(id)
        end
        if x then
            speaker.source:setPosition(x, y, z)
        end
    end
end

-- Player ids that spoke in the last moments.
function Voice:getSpeaking()
    local list = {}
    for id, time in pairs(self.speakingSince) do
        if self.now - time < SPEAKING_HOLD then
            list[#list + 1] = id
        end
    end
    table.sort(list)
    return list
end

function Voice:forget(id)
    local speaker = self.speakers[id]
    if speaker then
        speaker.source:release()
        self.speakers[id] = nil
    end
end

function Voice:destroy()
    for id in pairs(self.speakers) do
        self:forget(id)
    end
    if self.capture then
        self.capture:close()
        self.capture = nil
    end
end

return Voice
