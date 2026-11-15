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
local SPEAKING_HOLD = 0.4 -- how long the indicator stays after the last packet

-- Loudness of int16 samples as 0..1 (RMS, lifted so quiet speech is still visible).
local function loudness(pcm, count, from)
    local sum = 0
    for index = from or 0, (from or 0) + count - 1 do
        local sample = pcm[index] / 32768
        sum = sum + sample * sample
    end
    return math.min(1, math.sqrt(sum / math.max(1, count)) * 4)
end

-- VU behaviour: a packet replaces the meter once it is at least as loud as what the meter
-- currently shows (the old peak decays), so quieter speech after a loud word still counts.
local DECAY_SECONDS = 0.35

local function decayed(level, now)
    return level and level.value * math.max(0, 1 - (now - level.time) / DECAY_SECONDS) or 0
end

function Voice:setLevel(id, value)
    local level = self.levels[id]
    if value >= decayed(level, self.now) then
        if level then
            level.value, level.time = value, self.now
        else
            self.levels[id] = { value = value, time = self.now }
        end
    end
end

local WARM_UP_AFTER = 1.5 -- seconds of session time before the microphone is opened

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
        levels = {}, -- playerId (0 = you) -> { value 0..1, time }
        hearingRange = options.hearingRange or 80,
        listenerAt = options.listenerAt,
    }, Voice)
    gameClient.client:remote('voice'):unreliable():onClient(function(id, bytes)
        self:receive(id, bytes)
    end)
    return self
end

function Voice:isAvailable()
    if self.capture == nil then
        local capture, reason = katsa.audio.openCapture(self.rate)
        self.capture = capture or false
        self.problem = reason
        local devices = katsa.audio.getCaptureDevices()
        katsa.log.log(
            capture and ('[voice] microphone ready: ' .. tostring(devices[1]))
                or ('[voice] ' .. tostring(reason)),
            'multiplayerCars'
        )
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

-- 'ready', or the reason the microphone cannot be used (checked on first use).
function Voice:getStatus()
    if self:isAvailable() then
        return 'ready'
    end
    return self.problem or 'unavailable'
end

function Voice:isTalking()
    return self.talking
end

function Voice:send(flush)
    local ffi = require('ffi')
    if self.capture and self.talking or flush then
        local pcm, count = self.capture:read()
        if pcm then
            self:setLevel(0, loudness(pcm, count))
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
    self:setLevel(id, loudness(pcm, count))
end

-- Moves each voice to its speaker and ages the speaking indicator.
function Voice:update(dt)
    self.now = self.now + dt
    -- Opening the capture device blocks for ~100 ms on desktop drivers. Do it a moment after the
    -- session starts, never on the first Tab press or the first push-to-talk.
    if self.capture == nil and self.now > WARM_UP_AFTER then
        self:isAvailable()
    end
    if self.talking then
        self:send(false)
    end
    for id, speaker in pairs(self.speakers) do
        local x, y, z = nil, nil, nil
        if self.positionOf then
            x, y, z = self.positionOf(id)
        end
        if x then
            speaker.source:setPosition(x, y, -z) -- OpenAL is right-handed: mirror Z like the engine does
        end
    end
end

-- Who is audible right now: { id, level, mine } sorted by id. Other players only count while
-- they are inside the hearing range (their voice is placed in 3D and fades out beyond it);
-- levels fall off smoothly after the last packet, like a VU meter.
function Voice:getMeters()
    local list = {}
    local ex, ey, ez
    if self.listenerAt then
        ex, ey, ez = self.listenerAt()
    end
    for id, level in pairs(self.levels) do
        local shown = decayed(level, self.now)
        if shown > 0.02 then
            local near = true
            if id ~= 0 and ex and self.positionOf then
                local x, y, z = self.positionOf(id)
                -- Unknown position (the speaker is driving): the voice plays unpositioned, so
                -- its meter shows too.
                near = x == nil or (x - ex) ^ 2 + (y - ey) ^ 2 + (z - ez) ^ 2 <= self.hearingRange ^ 2
            end
            if near then
                list[#list + 1] = { id = id, level = shown, mine = id == 0 }
            end
        end
    end
    table.sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
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
