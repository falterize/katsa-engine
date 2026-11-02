-- Live audio: microphone capture and queue-fed playback, the pieces voice chat is built from.
--
--   local mic = katsa.audio.openCapture(12000)     -- mono, 16-bit; nil, reason when there is no device
--   mic:start()
--   local pcm, count = mic:read()                  -- int16 cdata and sample count (nil when empty)
--   mic:stop(); mic:close()
--
--   local speaker = katsa.audio.newQueueSource(12000)
--   speaker:queue(pcm, count)                      -- plays gaplessly after the queued data
--   speaker:setPosition(x, y, z)                   -- 3D, like any Source (distance attenuated)
--   speaker:release()
--
-- Without OpenAL (servers, CI, KATSA_AUDIO=null) opening a capture returns nil and a queue source
-- silently swallows its data, so game code needs no special cases.
local ffi = require('ffi')
local Native = require('source.katsa.core.native')
local State = require('source.katsa.audio.state')

local Audio = State.Audio

local declared = false
local function declare()
    if declared then
        return
    end
    declared = true
    for _, line in ipairs({
        'typedef struct ALCdevice ALCdevice;',
        'ALCdevice* alcCaptureOpenDevice(const char* name, unsigned int frequency, int format, int size);',
        'int alcCaptureCloseDevice(ALCdevice* device);',
        'void alcCaptureStart(ALCdevice* device);',
        'void alcCaptureStop(ALCdevice* device);',
        'void alcCaptureSamples(ALCdevice* device, void* buffer, int samples);',
        'void alcGetIntegerv(ALCdevice* device, int parameter, int size, int* values);',
        'void alGenSources(int count, unsigned int* sources);',
        'void alDeleteSources(int count, const unsigned int* sources);',
        'void alGenBuffers(int count, unsigned int* buffers);',
        'void alDeleteBuffers(int count, const unsigned int* buffers);',
        'void alBufferData(unsigned int buffer, int format, const void* data, int size, int frequency);',
        'void alSourcei(unsigned int source, int parameter, int value);',
        'void alSourcef(unsigned int source, int parameter, float value);',
        'void alSource3f(unsigned int source, int parameter, float x, float y, float z);',
        'void alSourcePlay(unsigned int source);',
        'void alSourceStop(unsigned int source);',
        'void alGetSourcei(unsigned int source, int parameter, int* value);',
        'void alSourceQueueBuffers(unsigned int source, int count, const unsigned int* buffers);',
        'void alSourceUnqueueBuffers(unsigned int source, int count, unsigned int* buffers);',
    }) do
        pcall(ffi.cdef, line) -- already declared by the OpenAL driver: fine
    end
end

local FORMAT_MONO16 = 0x1101
local CAPTURE_SAMPLES = 0x312
local AL = {
    POSITION = 0x1004, GAIN = 0x100A, SOURCE_STATE = 0x1010, PLAYING = 0x1012,
    REFERENCE_DISTANCE = 0x1020, ROLLOFF_FACTOR = 0x1021, MAX_DISTANCE = 0x1023,
    BUFFERS_QUEUED = 0x1015, BUFFERS_PROCESSED = 0x1016, SOURCE_RELATIVE = 0x202,
}

local function library()
    if os.getenv('KATSA_AUDIO') == 'null' then
        return nil
    end
    local lib = Native.load('OpenAL')
    if lib then
        declare()
    end
    return lib
end

-- Capture ---------------------------------------------------------------------------------------
local Capture = {}
Capture.__index = Capture

function Audio.openCapture(sampleRate, deviceName)
    local lib = library()
    if not lib then
        return nil, 'OpenAL is not available'
    end
    sampleRate = sampleRate or 12000
    local ok, device = pcall(lib.alcCaptureOpenDevice, deviceName, sampleRate, FORMAT_MONO16, sampleRate)
    if not ok or device == nil then
        return nil, 'no capture device (microphone)'
    end
    return setmetatable({ lib = lib, device = device, rate = sampleRate, running = false }, Capture)
end

function Capture:start()
    if not self.running then
        self.lib.alcCaptureStart(self.device)
        self.running = true
    end
end

function Capture:stop()
    if self.running then
        self.lib.alcCaptureStop(self.device)
        self.running = false
    end
end

function Capture:isRunning()
    return self.running
end

-- Takes everything recorded since the last read: int16 cdata, sample count; nil when empty.
function Capture:read()
    local available = ffi.new('int[1]')
    self.lib.alcGetIntegerv(self.device, CAPTURE_SAMPLES, 1, available)
    local count = available[0]
    if count <= 0 then
        return nil
    end
    local buffer = ffi.new('int16_t[?]', count)
    self.lib.alcCaptureSamples(self.device, buffer, count)
    return buffer, count
end

function Capture:close()
    if self.device ~= nil then
        self:stop()
        self.lib.alcCaptureCloseDevice(self.device)
        self.device = nil
    end
end

-- Queue playback --------------------------------------------------------------------------------
local Queue = {}
Queue.__index = Queue

local function swallow() end
local Silent = setmetatable({}, {
    __index = function()
        return swallow
    end,
})

function Audio.newQueueSource(sampleRate)
    State.ensureDriver()
    local lib = State.driver.name == 'openal' and library()
    if not lib then
        return Silent
    end
    local id = ffi.new('unsigned int[1]')
    lib.alGenSources(1, id)
    lib.alSourcef(id[0], AL.REFERENCE_DISTANCE, 4)
    lib.alSourcef(id[0], AL.ROLLOFF_FACTOR, 1)
    lib.alSourcef(id[0], AL.MAX_DISTANCE, 80)
    return setmetatable({ lib = lib, id = id[0], rate = sampleRate or 12000, free = {} }, Queue)
end

local function recycle(self)
    local processed = ffi.new('int[1]')
    self.lib.alGetSourcei(self.id, AL.BUFFERS_PROCESSED, processed)
    for _ = 1, processed[0] do
        local buffer = ffi.new('unsigned int[1]')
        self.lib.alSourceUnqueueBuffers(self.id, 1, buffer)
        self.free[#self.free + 1] = buffer[0]
    end
end

-- Appends int16 samples; starts (or restarts after an underrun) playback.
function Queue:queue(pcm, count)
    recycle(self)
    local buffer = table.remove(self.free)
    if not buffer then
        local id = ffi.new('unsigned int[1]')
        self.lib.alGenBuffers(1, id)
        buffer = id[0]
    end
    self.lib.alBufferData(buffer, FORMAT_MONO16, pcm, count * 2, self.rate)
    local ids = ffi.new('unsigned int[1]', buffer)
    self.lib.alSourceQueueBuffers(self.id, 1, ids)
    local state = ffi.new('int[1]')
    self.lib.alGetSourcei(self.id, AL.SOURCE_STATE, state)
    if state[0] ~= AL.PLAYING then
        self.lib.alSourcePlay(self.id)
    end
end

-- Samples' worth of audio still waiting to play (drives the jitter buffer).
function Queue:getQueued()
    recycle(self)
    local queued = ffi.new('int[1]')
    self.lib.alGetSourcei(self.id, AL.BUFFERS_QUEUED, queued)
    return queued[0]
end

function Queue:setPosition(x, y, z)
    self.lib.alSource3f(self.id, AL.POSITION, x, y, z)
end

function Queue:setVolume(volume)
    self.lib.alSourcef(self.id, AL.GAIN, volume)
end

function Queue:release()
    if self.id then
        self.lib.alSourceStop(self.id)
        recycle(self)
        local buffers = ffi.new('unsigned int[?]', math.max(1, #self.free))
        for index, buffer in ipairs(self.free) do
            buffers[index - 1] = buffer
        end
        self.lib.alDeleteBuffers(#self.free, buffers)
        local ids = ffi.new('unsigned int[1]', self.id)
        self.lib.alDeleteSources(1, ids)
        self.id = nil
    end
end

return Audio
