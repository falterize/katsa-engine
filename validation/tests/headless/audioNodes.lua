-- Instrumented katsa audio calls; routing/lifetime, not audible DSP.
require('validation.tests.integration.luaCompatibility')
local count, definitions, created = 0, {}, {}

local function check(ok, msg)
    assert(ok, msg)
    count = count + 1
    print('PASS ' .. msg)
end
local Source = {}
Source.__index = Source

local function source()
    local s = setmetatable(
        { effects = {}, playing = false, channels = 1, position = {}, time = 0 },
        Source
    )
    created[#created + 1] = s
    return s
end

function Source:clone()
    return source()
end

function Source:release()
    self.released = true
end

function Source:play()
    self.playing = true
end

function Source:pause()
    self.playing = false
end

function Source:stop()
    self.playing = false
end

function Source:isPlaying()
    return self.playing
end

function Source:getChannelCount()
    return self.channels
end

function Source:setVolume(v)
    self.volume = v
end

function Source:setPitch(v)
    self.pitch = v
end

function Source:setLooping(v)
    self.loop = v
end

function Source:setRelative(v)
    self.relative = v
end

function Source:setRolloff(v) end

function Source:setAttenuationDistances(a, b) end

function Source:setPosition(x, y, z)
    self.position = { x, y, z }
end

function Source:setEffect(name, enabled)
    self.effects[name] = enabled or nil
    return true
end

function Source:setFilter(settings)
    self.filter = settings
    return true
end

function Source:seek(t)
    self.time = t
end

function Source:tell()
    return self.time
end

local function data()
    return {
        getChannelCount = function()
            return 1
        end,
        getSampleCount = function()
            return 4
        end,
        getSampleRate = function()
            return 22050
        end,
        getBitDepth = function()
            return 16
        end,
        getSample = function()
            return 0
        end,
        setSample = function() end,
        release = function() end,
    }
end
katsa = {
    filesystem = {
        getInfo = function()
            return true
        end,
    },
    sound = { newSoundData = data },
    audio = {
        newSource = source,
        isEffectsSupported = function()
            return true
        end,
        getMaxSourceEffects = function()
            return 2
        end,
        setEffect = function(name, settings)
            definitions[name] = settings
            return true
        end,
        setPosition = function() end,
        setOrientation = function() end,
    },
}
local Node = require('source.engine.nodes')
local Audio = require('source.engine.audio')

local audio = Audio.new()
local root = Node.new('World3D', {})
local world = { audio = audio, root = root }
root._world = world

local function create(kind, props, parent)
    return Node.create(kind, props, parent or root, world)
end
local group = create('SoundGroup', { volume = 0.5 })
local sound = create('Sound', { resource = 'probe.wav', volume = 0.8, looped = true }, group)
local reverb = create('SoundReverb', { decaytime = 2 }, sound)
local echo = create('SoundEcho', {}, group)
local pitch = create('SoundPitch', { playbackSpeed = 0.5 }, sound)
sound:play()
local v = sound._voice
check(
    sound:isPlaying() and #audio.nodes == 1,
    'Sound mounts into the mixer and plays a Source interface'
)
check(math.abs(v.source.volume - 0.34) < 1e-6, 'SoundGroup gain and legacy master gain multiply')
check(v.source.pitch == 0.5, 'SoundPitch multiplies playbackSpeed without a fake EFX type')
check(
    v.source.effects[reverb._effectName] and v.source.effects[echo._effectName],
    'Sound and group effects share parallel source routing'
)
check(
    definitions[echo._effectName].type == 'echo' and definitions[reverb._effectName].decaytime == 2,
    'Native effect settings use documented katsa types'
)
local definitionsCount = 0
local original = katsa.audio.setEffect
katsa.audio.setEffect = function(...)
    definitionsCount = definitionsCount + 1
    return original(...)
end
audio:update()
check(definitionsCount == 0, 'Unchanged definitions are not recreated each frame')
reverb.decaytime = 3
audio:update()
check(
    definitionsCount == 1 and definitions[reverb._effectName].decaytime == 3,
    'Effect property edit updates exactly its definition'
)
sound:seek(1.25)
check(sound:tell() == 1.25, 'Sound seek/tell use seconds')
sound:pause()
audio:pause()
audio:resume()
check(not sound:isPlaying(), 'Focus resume retains manual Sound pause')
sound:play()
check(sound:isPlaying(), 'Sound play resumes a paused voice')
audio:pause()
check(not sound:isPlaying(), 'Scene pause suspends node voices')
audio:resume()
check(sound:isPlaying(), 'Scene resume restores playing node voices')
group.volume = 0.25
audio:update()
check(math.abs(v.source.volume - 0.17) < 1e-6, 'Group edits affect existing voices')
group.muted = true
audio:update()
check(v.source.volume == 0, 'Muted SoundGroup silences source gain')
group.muted = false
local extra = create('SoundChorus', {}, sound)
audio:update()
check(
    extra.status == 'Source effect limit reached',
    'Device send limit produces an explicit fallback status'
)
echo.enabled = false
audio:update()
check(
    not v.source.effects[echo._effectName] and v.source.effects[extra._effectName],
    'Disabling an effect frees its send'
)
reverb:destroy()
check(
    not v.source.effects[reverb._effectName] and definitions[reverb._effectName] == false,
    'Destroy detaches sends and deletes native effect'
)
local filter = create('SoundFilter', {}, sound)
audio:update()
check(v.source.filter and v.source.filter.type == 'lowpass', 'SoundFilter applies a Source filter')
filter.enabled = false
audio:update()
check(v.source.filter == nil, 'Disabling filter clears direct filtering')
local old = sound.parent
check(
    not pcall(extra.setParent, extra, root) and extra.parent == sound,
    'Invalid effect parenting rejects atomically'
)
local otherAudio = Audio.new()
local otherRoot = Node.new('World3D', { _audio = otherAudio })
check(
    not pcall(sound.setParent, sound, otherRoot) and sound.parent == old,
    'Audio nodes cannot migrate mixer scopes'
)
sound:stop()
sound.parent = root
sound.spatial = true
sound:play()
v = sound._voice
audio:update()
check(
    v.source.position[1] == 0 and v.source.position[3] == 0,
    'Spatial Sound follows a World3D ancestor'
)
local attachment = create('Attachment3D', { position = { 7, 3, 9 } })
sound.parent = attachment
audio:update()
check(
    v.source.position[1] == 7 and v.source.position[3] == -9,
    'Spatial Sound follows Attachment3D and OpenAL axis mapping'
)
attachment.position[1] = 10
audio:update()
check(v.source.position[1] == 10, 'Moving Attachment3D updates existing sources')
attachment:destroy()
audio:update()
check(
    sound.destroyed and v.released and #audio.nodes == 0,
    'Destroying spatial parent releases Sound and mixer membership'
)
local fallback = create('Sound', { resource = 'probe.wav' })
local unavailable = create('SoundEcho', {}, fallback)
audio.effectsSupported = nil
katsa.audio.isEffectsSupported = function()
    return false
end
fallback:play()
check(
    fallback:isPlaying() and unavailable.status == 'Unsupported on this device',
    'Unsupported effects preserve dry playback'
)
fallback:stop()
fallback.stream = true
fallback:play()
check(fallback._voice.nodeStream and fallback:isPlaying(), 'Sound supports streaming playback')
root:destroy()
audio:release()
otherRoot:destroy()
otherAudio:release()
local allReleased = true
for _, s in ipairs(created) do
    allReleased = allReleased and s.released
end
check(allReleased, 'Scene cleanup releases cloned sources and cached samples')
-- Build the actual example, including BillboardUI/UI nodes and preset callbacks.
katsa.audio.isEffectsSupported = function()
    return true
end
katsa.graphics = {
    getSystemLimits = function()
        return { texturesize = 4096 }
    end,
    getDPIScale = function()
        return 1
    end,
    newCanvas = function(w, h)
        return {
            setFilter = function() end,
            release = function() end,
            getWidth = function()
                return w
            end,
            getHeight = function()
                return h
            end,
        }
    end,
}
local UI = require('source.engine.ui')

local resources = {
    own = function(_, v)
        return v
    end,
    releaseOwned = function(_, v)
        v:release()
    end,
}
local World3D = require('source.engine.world.world')

local labAudio = Audio.new()
local labRoot = Node.new('World3D', {})
local labWorld = {
    audio = labAudio,
    root = labRoot,
    resources = resources,
    billboards = {},
    folders = {},
    lighting = { fog = {}, gizmos = {} },
}
labRoot._world = labWorld
for _, name in ipairs({ 'Geometry', 'Scripts', 'Billboards', 'Lights', 'Cameras' }) do
    labWorld.folders[name] = Node.new('Folder', { name = name }, labRoot)
end
labWorld.create = World3D.create

function labWorld:addObject(properties)
    properties._world = self
    return Node.new('Mesh3D', properties, properties.parent or self.folders.Geometry)
end

function labWorld:removeBillboard(board)
    for i, v in ipairs(self.billboards) do
        if v == board then
            table.remove(self.billboards, i)
            break
        end
    end
    self.resources:releaseOwned(board.canvas)
end

function labWorld:updateNodes() end
local labUI = UI.new(1280, 720, resources)
local scene = { world = labWorld, audio = labAudio, ui = labUI, camera = {} }
local demo = require('source.game.scenes.audioNodes.main').new(scene)
demo:buildUI()
check(
    #labWorld.billboards == 1 and demo.sound.parent == demo.emitter,
    'Listening scene builds real Sound, effect and BillboardUI node hierarchy'
)
demo:choose('Echo', 'SoundEcho')
labAudio:update()
check(
    demo.sound:isPlaying() and demo.effects.SoundEcho.status == 'Applied',
    'Listening preset activates its actual effect node'
)
demo:choose('Group reverb', 'Group')
labAudio:update()
check(
    demo.groupReverb.status == 'Applied' and not demo.effects.SoundEcho.enabled,
    'Group preset changes inherited native effect routing'
)
demo:choose('High pitch', 'SoundPitch', 1.4)
labAudio:update()
check(
    demo.sound._voice.source.pitch == 1.4,
    'Listening pitch preset changes the Source playback speed'
)
demo.spatialButton:press()
labAudio:update()
check(
    demo.sound.spatial and demo.sound._voice.source.position[3] == -25,
    'Listening spatial toggle follows the speaker world pose'
)
labRoot:destroy()
labUI:release()
labAudio:release()
check(
    #labAudio.nodes == 0 and #labAudio.effects == 0,
    'Leaving listening scene cleans all sound/effect registrations'
)
print('PASSED ' .. count .. ' instrumented audio-node assertions; no audible DSP testing')
