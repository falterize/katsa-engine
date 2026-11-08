-- The engine note of one car: a looped idle recording (assets/audio/engineLoop.ogg) played faster
-- as the car does, with a gear-shift sawtooth, so speed is heard without a real engine model.
--
-- The sound is spatial and fades out completely at `MAX_DISTANCE`. A car beyond that (plus a
-- margin) stops its voice, and at most `MAX_VOICES` engines sound at once, so a lobby full of cars
-- costs a handful of voices.
local EngineSound = {}
EngineSound.__index = EngineSound

EngineSound.PATH = 'scene://audio/engineLoop.ogg'

local MIN_DISTANCE, MAX_DISTANCE, MARGIN = 5, 60, 10
local MAX_VOICES = 6
local TOP_SPEED = 62 -- m/s at the top of the last gear
local GEARS = { 0, 14, 26, 40, 54, TOP_SPEED }
local IDLE_PITCH, REV_PITCH = 0.85, 2.1 -- playbackSpeed at idle and at the top of a gear
local SMOOTHING = 6 -- 1/s, how quickly the note follows the target

local voices = 0 -- engines that are sounding right now (all cars of this process)

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

function EngineSound.available(scene)
    return scene.world.audio ~= nil
        and katsa.filesystem.getInfo(scene.resources:canonical(EngineSound.PATH), 'file') ~= nil
end

-- Revs (0..1) for a speed: climbs inside each gear and drops back at the shift.
function EngineSound.revs(speed)
    speed = math.abs(speed)
    for gear = 1, #GEARS - 1 do
        if speed < GEARS[gear + 1] or gear == #GEARS - 1 then
            local span = GEARS[gear + 1] - GEARS[gear]
            return clamp(0.25 + 0.75 * (speed - GEARS[gear]) / span, 0, 1)
        end
    end
    return 1
end

-- Playback speed and volume for revs, load (0..1, how hard the car accelerates) and master volume.
function EngineSound.tone(revs, load)
    return IDLE_PITCH + (REV_PITCH - IDLE_PITCH) * revs, 0.35 + 0.4 * revs + 0.25 * load
end

-- `parent` is the car's model root (any Node3D that follows the car).
function EngineSound.new(world, parent, netId)
    local self = setmetatable({
        world = world,
        netId = netId,
        revs = 0,
        load = 0,
        lastSpeed = 0,
        sounding = false,
    }, EngineSound)
    self.source = world:create('AudioSource', {
        name = 'Engine' .. netId,
        resource = EngineSound.PATH,
        looped = true,
        volume = 0,
        playbackSpeed = IDLE_PITCH,
        minDistance = MIN_DISTANCE,
        maxDistance = MAX_DISTANCE,
        rolloff = 'LinearSquare',
        playing = false,
        position = { 0, 0.6, 0 },
    }, parent)
    return self
end

function EngineSound:distance()
    local listener = self.world.audio and self.world.audio.listener
    if not listener then
        return math.huge
    end
    local p = self.source:getWorldPosition()
    return math.sqrt(
        (p[1] - listener[1]) ^ 2 + (p[2] - listener[2]) ^ 2 + (p[3] - listener[3]) ^ 2
    )
end

function EngineSound:setSounding(on)
    if on == self.sounding then
        return
    end
    self.sounding = on
    if on then
        voices = voices + 1
        self.source:play()
    else
        voices = math.max(0, voices - 1)
        self.source:pause()
    end
end

-- Call every frame with the car's replicated speed (m/s, signed).
function EngineSound:update(dt, speed)
    local near = self:distance() < MAX_DISTANCE + (self.sounding and MARGIN or 0)
    self:setSounding(near and (self.sounding or voices < MAX_VOICES))
    if not self.sounding then
        self.lastSpeed = speed
        return
    end
    local accel = dt > 0 and (math.abs(speed) - math.abs(self.lastSpeed)) / dt or 0
    self.lastSpeed = speed
    local k = 1 - math.exp(-SMOOTHING * dt)
    self.revs = self.revs + (EngineSound.revs(speed) - self.revs) * k
    self.load = self.load + (clamp(accel / 6, 0, 1) - self.load) * k
    local pitch, volume = EngineSound.tone(self.revs, self.load)
    self.source.playbackSpeed = pitch
    self.source.volume = volume
end

function EngineSound:destroy()
    self:setSounding(false)
    self.source:destroy()
end

return EngineSound
