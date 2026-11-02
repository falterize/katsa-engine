-- OpenAL driver: turns Source state into OpenAL sources. Sound data is uploaded once per SoundData
-- and shared by every Source (and clone) that plays it.
local ffi = require('ffi')
local Native = require('source.katsa.core.native')

ffi.cdef([[
typedef struct ALCdevice ALCdevice;
typedef struct ALCcontext ALCcontext;
ALCdevice* alcOpenDevice(const char* name);
int alcCloseDevice(ALCdevice* device);
ALCcontext* alcCreateContext(ALCdevice* device, const int* attributes);
int alcMakeContextCurrent(ALCcontext* context);
void alcDestroyContext(ALCcontext* context);
void alGenSources(int count, unsigned int* sources);
void alDeleteSources(int count, const unsigned int* sources);
void alGenBuffers(int count, unsigned int* buffers);
void alDeleteBuffers(int count, const unsigned int* buffers);
void alBufferData(unsigned int buffer, int format, const void* data, int size, int frequency);
void alSourcei(unsigned int source, int parameter, int value);
void alSourcef(unsigned int source, int parameter, float value);
void alSource3f(unsigned int source, int parameter, float x, float y, float z);
void alSourcePlay(unsigned int source);
void alSourcePause(unsigned int source);
void alSourceStop(unsigned int source);
void alGetSourcei(unsigned int source, int parameter, int* value);
void alListenerf(int parameter, float value);
void alListener3f(int parameter, float x, float y, float z);
void alListenerfv(int parameter, const float* values);
void alDistanceModel(int model);
void alDopplerFactor(float value);
int alGetError(void);
void alSource3i(unsigned int source, int parameter, int a, int b, int c);
void* alGetProcAddress(const char* name);
int alcIsExtensionPresent(ALCdevice* device, const char* name);
void alcGetIntegerv(ALCdevice* device, int parameter, int size, int* values);
typedef void (*KGenObjects)(int, unsigned int*);
typedef void (*KSetInt)(unsigned int, int, int);
typedef void (*KSetFloat)(unsigned int, int, float);
]])

local AL = {
    SOURCE_RELATIVE = 0x202, CONE_INNER_ANGLE = 0x1001, CONE_OUTER_ANGLE = 0x1002, PITCH = 0x1003,
    POSITION = 0x1004, DIRECTION = 0x1005, VELOCITY = 0x1006, LOOPING = 0x1007, BUFFER = 0x1009,
    GAIN = 0x100A, MIN_GAIN = 0x100D, MAX_GAIN = 0x100E, ORIENTATION = 0x100F,
    SOURCE_STATE = 0x1010, PLAYING = 0x1012, REFERENCE_DISTANCE = 0x1020, ROLLOFF_FACTOR = 0x1021,
    CONE_OUTER_GAIN = 0x1022, MAX_DISTANCE = 0x1023, SEC_OFFSET = 0x1024,
    FORMAT_MONO16 = 0x1101, FORMAT_STEREO16 = 0x1103,
}

local distanceModels = {
    none = 0xD000, inverse = 0xD001, inverseclamped = 0xD002, linear = 0xD003,
    linearclamped = 0xD004, exponent = 0xD005, exponentclamped = 0xD006,
}

local Driver = { name = 'openal', effectsSupported = false, maxSourceEffects = 0 }
local al, device, context

-- EFX (OpenAL Soft): effects live in auxiliary slots; a source feeds a slot through one of its
-- auxiliary sends. Filters attach directly to the dry path.
local EFX = {
    EFFECT_TYPE = 0x8001, REVERB = 0x0001, CHORUS = 0x0002, DISTORTION = 0x0003, ECHO = 0x0004,
    SLOT_EFFECT = 0x0001, SLOT_GAIN = 0x0002, DIRECT_FILTER = 0x20005, SEND_FILTER = 0x20006,
    FILTER_TYPE = 0x8001, LOWPASS = 1, HIGHPASS = 2, BANDPASS = 3, MAX_SENDS = 0x20003,
}
local efx = {} -- loaded entry points
local slots = {} -- effect name -> { effect = id, slot = id }
local directFilters = setmetatable({}, { __mode = 'k' }) -- Source -> AL filter id

local function proc(name, kind)
    local pointer = al.alGetProcAddress(name)
    if pointer == nil then
        return nil
    end
    return ffi.cast(kind, pointer)
end

local function loadEfx()
    local names = {
        genEffects = { 'alGenEffects', 'KGenObjects' },
        deleteEffects = { 'alDeleteEffects', 'void (*)(int, const unsigned int*)' },
        effecti = { 'alEffecti', 'KSetInt' },
        effectf = { 'alEffectf', 'KSetFloat' },
        genSlots = { 'alGenAuxiliaryEffectSlots', 'KGenObjects' },
        deleteSlots = { 'alDeleteAuxiliaryEffectSlots', 'void (*)(int, const unsigned int*)' },
        sloti = { 'alAuxiliaryEffectSloti', 'KSetInt' },
        slotf = { 'alAuxiliaryEffectSlotf', 'KSetFloat' },
        genFilters = { 'alGenFilters', 'KGenObjects' },
        deleteFilters = { 'alDeleteFilters', 'void (*)(int, const unsigned int*)' },
        filteri = { 'alFilteri', 'KSetInt' },
        filterf = { 'alFilterf', 'KSetFloat' },
    }
    for key, entry in pairs(names) do
        efx[key] = proc(entry[1], entry[2])
        if not efx[key] then
            return false
        end
    end
    return true
end

local voices = setmetatable({}, { __mode = 'k' }) -- Source -> OpenAL source id
local buffers = setmetatable({}, { __mode = 'k' }) -- SoundData -> shared buffer holder

local function toDegrees(radians)
    return radians * 180 / math.pi
end

-- One AL buffer per SoundData, deleted when the data is collected and no source uses it.
local function bufferFor(data)
    local holder = buffers[data]
    if holder then
        return holder.id
    end
    local id = ffi.new('unsigned int[1]')
    al.alGenBuffers(1, id)
    local format = data:getChannelCount() == 1 and AL.FORMAT_MONO16 or AL.FORMAT_STEREO16
    al.alBufferData(id[0], format, data:getFFIPointer(), data:getSize(), data:getSampleRate())
    holder = { id = id[0] }
    holder.guard = ffi.gc(ffi.new('char[1]'), function()
        local ids = ffi.new('unsigned int[1]', holder.id)
        al.alDeleteBuffers(1, ids)
    end)
    buffers[data] = holder
    return holder.id
end

function Driver.createVoice(source)
    local id = ffi.new('unsigned int[1]')
    al.alGenSources(1, id)
    voices[source] = id[0]
    al.alSourcei(id[0], AL.BUFFER, bufferFor(source._data))
    Driver.update(source)
end

function Driver.destroyVoice(source)
    local id = voices[source]
    local filter = directFilters[source]
    if filter then
        directFilters[source] = nil
        efx.deleteFilters(1, ffi.new('unsigned int[1]', filter))
    end
    if id then
        voices[source] = nil
        al.alSourceStop(id)
        al.alSourcei(id, AL.BUFFER, 0)
        al.alDeleteSources(1, ffi.new('unsigned int[1]', id))
    end
end

function Driver.update(source)
    local id = voices[source]
    if not id then
        return
    end
    local p, v, d = source._position, source._velocity, source._direction
    al.alSourcef(id, AL.GAIN, source._volume)
    al.alSourcef(id, AL.PITCH, source._pitch)
    al.alSourcei(id, AL.LOOPING, source._looping and 1 or 0)
    al.alSource3f(id, AL.POSITION, p[1], p[2], p[3])
    al.alSource3f(id, AL.VELOCITY, v[1], v[2], v[3])
    al.alSource3f(id, AL.DIRECTION, d[1], d[2], d[3])
    al.alSourcef(id, AL.CONE_INNER_ANGLE, toDegrees(source._cone[1]))
    al.alSourcef(id, AL.CONE_OUTER_ANGLE, toDegrees(source._cone[2]))
    al.alSourcef(id, AL.CONE_OUTER_GAIN, source._cone[3])
    al.alSourcei(id, AL.SOURCE_RELATIVE, source._relative and 1 or 0)
    al.alSourcef(id, AL.ROLLOFF_FACTOR, source._rolloff)
    al.alSourcef(id, AL.REFERENCE_DISTANCE, source._refDistance)
    al.alSourcef(id, AL.MAX_DISTANCE, source._maxDistance)
    al.alSourcef(id, AL.MIN_GAIN, source._minVolume)
    al.alSourcef(id, AL.MAX_GAIN, source._maxVolume)
    if Driver.effectsSupported then
        Driver.applyEffects(source, id)
    end
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, tonumber(value) or low))
end

-- Dry-path filter from Source:setFilter({ type, volume, lowgain, highgain }).
local function applyFilter(source, id)
    local settings = source._filter
    local filter = directFilters[source]
    if not settings then
        if filter then
            al.alSourcei(id, EFX.DIRECT_FILTER, 0)
        end
        return
    end
    if not filter then
        local out = ffi.new('unsigned int[1]')
        efx.genFilters(1, out)
        filter = out[0]
        directFilters[source] = filter
    end
    local kinds = { lowpass = EFX.LOWPASS, highpass = EFX.HIGHPASS, bandpass = EFX.BANDPASS }
    local kind = kinds[settings.type or 'lowpass']
    if not kind then
        return
    end
    efx.filteri(filter, EFX.FILTER_TYPE, kind)
    efx.filterf(filter, 1, clamp(settings.volume or 1, 0, 1)) -- gain
    if kind == EFX.LOWPASS then
        efx.filterf(filter, 2, clamp(settings.highgain or 1, 0, 1))
    elseif kind == EFX.HIGHPASS then
        efx.filterf(filter, 2, clamp(settings.lowgain or 1, 0, 1))
    else
        efx.filterf(filter, 2, clamp(settings.lowgain or 1, 0, 1))
        efx.filterf(filter, 3, clamp(settings.highgain or 1, 0, 1))
    end
    al.alSourcei(id, EFX.DIRECT_FILTER, filter)
end

-- Sends sorted effect names to auxiliary sends 0..n-1 and clears the rest.
function Driver.applyEffects(source, id)
    applyFilter(source, id)
    local names = {}
    for name in pairs(source._effects) do
        if slots[name] then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for send = 0, Driver.maxSourceEffects - 1 do
        local entry = names[send + 1] and slots[names[send + 1]]
        al.alSource3i(id, EFX.SEND_FILTER, entry and entry.slot or 0, send, 0)
    end
end

function Driver.seek(source, offset)
    local id = voices[source]
    if id then
        al.alSourcef(id, AL.SEC_OFFSET, offset)
    end
end

function Driver.play(source)
    local id = voices[source]
    if id then
        Driver.update(source)
        al.alSourcef(id, AL.SEC_OFFSET, source._startOffset or 0)
        al.alSourcePlay(id)
    end
end

function Driver.pause(source)
    local id = voices[source]
    if id then
        al.alSourcePause(id)
    end
end

function Driver.stop(source)
    local id = voices[source]
    if id then
        al.alSourceStop(id)
    end
end

-- True while OpenAL reports the voice of `source` as playing.
function Driver.isPlaying(source)
    local id = voices[source]
    if not id then
        return false
    end
    local state = ffi.new('int[1]')
    al.alGetSourcei(id, AL.SOURCE_STATE, state)
    return state[0] == AL.PLAYING
end

function Driver.updateListener(listener)
    local o = listener.orientation
    al.alListenerf(AL.GAIN, listener.volume)
    al.alListener3f(AL.POSITION, unpack(listener.position))
    al.alListener3f(AL.VELOCITY, unpack(listener.velocity))
    al.alListenerfv(AL.ORIENTATION, ffi.new('float[6]', o[1], o[2], o[3], o[4], o[5], o[6]))
end

-- Distance model and Doppler factor are global in OpenAL.
function Driver.updateGlobal(state)
    al.alDistanceModel(distanceModels[state.distanceModel or 'inverseclamped'])
    al.alDopplerFactor(state.doppler or 1)
end

local WAVEFORMS = { sine = 0, triangle = 1 }

-- [type] = { key, AL parameter, minimum, maximum } for each tunable float of an effect.
local PARAMETERS = {
    reverb = {
        { 'density', 0x0001, 0, 1 }, { 'diffusion', 0x0002, 0, 1 }, { 'gain', 0x0003, 0, 1 },
        { 'gainhf', 0x0004, 0, 1 }, { 'decaytime', 0x0005, 0.1, 20 },
        { 'decayhfratio', 0x0006, 0.1, 2 }, { 'reflectionsgain', 0x0007, 0, 3.16 },
        { 'reflectionsdelay', 0x0008, 0, 0.3 }, { 'lategain', 0x0009, 0, 10 },
        { 'latedelay', 0x000A, 0, 0.1 }, { 'airabsorptiongainhf', 0x000B, 0.892, 1 },
        { 'roomrollofffactor', 0x000C, 0, 10 },
    },
    echo = {
        { 'delay', 0x0001, 0, 0.207 }, { 'tapdelay', 0x0002, 0, 0.404 },
        { 'damping', 0x0003, 0, 0.99 }, { 'feedback', 0x0004, 0, 1 }, { 'spread', 0x0005, -1, 1 },
    },
    chorus = {
        { 'rate', 0x0003, 0, 10 }, { 'depth', 0x0004, 0, 1 }, { 'feedback', 0x0005, -1, 1 },
        { 'delay', 0x0006, 0, 0.016 },
    },
    distortion = {
        { 'edge', 0x0001, 0, 1 }, { 'gain', 0x0002, 0.01, 1 }, { 'lowcut', 0x0003, 80, 24000 },
        { 'center', 0x0004, 80, 24000 }, { 'bandwidth', 0x0005, 80, 24000 },
    },
}
local TYPES = {
    reverb = EFX.REVERB, echo = EFX.ECHO, chorus = EFX.CHORUS, distortion = EFX.DISTORTION,
}

-- Defines (or updates) the named effect: `settings.type` picks the kind, `volume` is the wet gain.
function Driver.defineEffect(name, settings)
    if not Driver.effectsSupported or settings.type == 'filter' then
        return
    end
    local kind = TYPES[settings.type]
    if not kind then
        return
    end
    local entry = slots[name]
    if not entry then
        local effect, slot = ffi.new('unsigned int[1]'), ffi.new('unsigned int[1]')
        efx.genEffects(1, effect)
        efx.genSlots(1, slot)
        entry = { effect = effect[0], slot = slot[0] }
        slots[name] = entry
    end
    al.alGetError()
    efx.effecti(entry.effect, EFX.EFFECT_TYPE, kind)
    for _, parameter in ipairs(PARAMETERS[settings.type]) do
        local value = settings[parameter[1]]
        if type(value) == 'number' then
            efx.effectf(entry.effect, parameter[2], clamp(value, parameter[3], parameter[4]))
        end
    end
    if settings.type == 'chorus' then
        efx.effecti(entry.effect, 0x0001, WAVEFORMS[settings.waveform or 'sine'] or 0)
        efx.effecti(entry.effect, 0x0002, math.floor(clamp(settings.phase or 90, -180, 180)))
    end
    efx.sloti(entry.slot, EFX.SLOT_EFFECT, entry.effect)
    efx.slotf(entry.slot, EFX.SLOT_GAIN, clamp(settings.volume or 1, 0, 1))
    if al.alGetError() ~= 0 then
        error('OpenAL rejected the ' .. settings.type .. ' effect settings')
    end
    for source in pairs(voices) do
        if source._effects[name] then
            Driver.update(source)
        end
    end
end

function Driver.removeEffect(name)
    local entry = slots[name]
    if not entry then
        return
    end
    slots[name] = nil
    for source, id in pairs(voices) do
        if source._effects[name] then
            Driver.applyEffects(source, id)
        end
    end
    efx.sloti(entry.slot, EFX.SLOT_EFFECT, 0)
    efx.deleteSlots(1, ffi.new('unsigned int[1]', entry.slot))
    efx.deleteEffects(1, ffi.new('unsigned int[1]', entry.effect))
end

-- Opens the default output device. Returns the driver, or nil plus the reason.
function Driver.open(deviceName)
    local lib, problem = Native.load('OpenAL')
    if not lib then
        return nil, problem
    end
    al = lib
    device = al.alcOpenDevice(deviceName)
    if device == nil then
        return nil, 'no audio output device'
    end
    local wantsEfx = al.alcIsExtensionPresent(device, 'ALC_EXT_EFX') ~= 0
    local attributes = wantsEfx and ffi.new('int[3]', EFX.MAX_SENDS, 4, 0) or nil
    context = al.alcCreateContext(device, attributes)
    if context == nil or al.alcMakeContextCurrent(context) == 0 then
        al.alcCloseDevice(device)
        return nil, 'cannot create an OpenAL context'
    end
    Driver.effectsSupported, Driver.maxSourceEffects = false, 0
    if wantsEfx and loadEfx() then
        local sends = ffi.new('int[1]')
        al.alcGetIntegerv(device, EFX.MAX_SENDS, 1, sends)
        if sends[0] > 0 then
            Driver.effectsSupported, Driver.maxSourceEffects = true, math.min(4, sends[0])
        end
    end
    return Driver
end

function Driver.close()
    if context then
        al.alcMakeContextCurrent(nil)
        al.alcDestroyContext(context)
        al.alcCloseDevice(device)
        context, device = nil, nil
    end
end

return Driver
