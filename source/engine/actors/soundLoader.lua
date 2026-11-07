-- SoundLoader: decodes sound files (Ogg Vorbis and WAV) on worker threads.
--
--   local loader = SoundLoader.new()
--   loader:load('assets/audio/theme.ogg', function(ok, soundData) ... end)
--   loader:update()                                   -- every frame; callbacks run here
--
-- A long Ogg or a large WAV (decoded sample by sample in Lua) can take long enough to hitch a
-- frame; here the decoding runs on a worker and the samples come back through shared memory as an
-- ordinary `katsa.sound` SoundData (one memory copy). Reading the file stays on the calling thread.
local ffi = require('ffi')
local Pool = require('source.engine.actors.pool')
local SharedArray = require('source.katsa.thread.sharedArray')

local SoundLoader = {}
SoundLoader.__index = SoundLoader

local SCRIPT = [[
local ffi = require('ffi')
local Sound = require('source.katsa.sound')
local SharedArray = require('source.katsa.thread.sharedArray')
Actor.on('decode', function(bytes)
    local sound = Sound.newSoundData(bytes)
    local size = sound:getSampleCount() * sound:getChannelCount() * 2
    local shared = SharedArray.new('uint8_t', size)
    ffi.copy(shared.data, sound:getFFIPointer(), size)
    return {
        handle = shared:giveAway(),
        size = size,
        frames = sound:getSampleCount(),
        rate = sound:getSampleRate(),
        bits = sound:getBitDepth(),
        channels = sound:getChannelCount(),
    }
end)
]]

function SoundLoader.new(size)
    local workers = size or math.min(2, Pool.defaultSize())
    return setmetatable({ pool = Pool.new({ script = SCRIPT, size = workers, name = 'sounds' }) }, SoundLoader)
end

-- `source` is a file path or the encoded bytes. callback(ok, soundDataOrError).
function SoundLoader:load(source, callback)
    local bytes = source
    if #source < 1024 and not source:find('\0', 1, true) then
        local message
        bytes, message = katsa.filesystem.read(source)
        if not bytes then
            callback(false, message)
            return
        end
    end
    self.pool:request('decode', bytes, function(ok, result)
        if not ok then
            callback(false, result)
            return
        end
        local shared = SharedArray.adopt(result.handle, 'uint8_t', result.size)
        local sound = katsa.sound.newSoundData(result.frames, result.rate, result.bits, result.channels)
        ffi.copy(sound:getFFIPointer(), shared.data, result.size)
        shared:release()
        callback(true, sound)
    end)
end

function SoundLoader:update(limit)
    return self.pool:update(limit)
end

function SoundLoader:getPending()
    return self.pool:getPending()
end

function SoundLoader:destroy(joinMs)
    self.pool:destroy(joinMs)
end

return SoundLoader
