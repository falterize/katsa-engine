-- AudioSource, AudioListener and SoundManager against instrumented katsa audio
-- (routing and bookkeeping, not audible output).
local Module = {}

local function installFakeAudio()
    local saved = { audio = katsa.audio, sound = katsa.sound, getInfo = katsa.filesystem.getInfo }
    local state = { created = {}, listener = { position = {}, orientation = {} } }
    local Source = {}
    Source.__index = Source
    local function newSource()
        local s = setmetatable({ effects = {}, playing = false, time = 0, position = {} }, Source)
        state.created[#state.created + 1] = s
        return s
    end
    function Source:clone()
        return newSource()
    end
    function Source:release() end
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
        return 1
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
    function Source:setRelative() end
    function Source:setRolloff() end
    function Source:setAttenuationDistances() end
    function Source:setPosition(x, y, z)
        self.position = { x, y, z }
    end
    function Source:setEffect()
        return true
    end
    function Source:setFilter()
        return true
    end
    function Source:seek(t)
        self.time = t
    end
    function Source:tell()
        return self.time
    end
    katsa.sound = {
        newSoundData = function()
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
        end,
    }
    katsa.audio = {
        newSource = newSource,
        isEffectsSupported = function()
            return true
        end,
        getMaxSourceEffects = function()
            return 2
        end,
        setEffect = function()
            return true
        end,
        setPosition = function(x, y, z)
            state.listener.position = { x, y, z }
        end,
        setOrientation = function(fx, fy, fz, ux, uy, uz)
            state.listener.orientation = { fx, fy, fz, ux, uy, uz }
        end,
    }
    katsa.filesystem.getInfo = function()
        return true
    end
    return state,
        function()
            katsa.audio, katsa.sound, katsa.filesystem.getInfo =
                saved.audio, saved.sound, saved.getInfo
        end
end

function Module.run(self)
    local Node = require('source.engine.nodes')
    local Audio = require('source.engine.audio')
    local state, restore = installFakeAudio()
    local ok, err = pcall(function()
        local audio = Audio.new()
        local root = Node.new('World3D', {})
        local world = { audio = audio, root = root }
        root._world = world
        local function create(kind, props, parent)
            return Node.create(kind, props, parent or root, world)
        end
        local manager = audio.manager
        self:check(manager and manager.audio == audio, 'Audio scope owns a SoundManager')

        -- SoundManager mix control reads and writes the shared group table.
        manager:setMasterVolume(0.5)
        self:check(manager:getMasterVolume() == 0.5, 'SoundManager master volume')
        manager:createGroup('vehicles', { volume = 0.5, parent = 'effects' })
        self:check(
            math.abs(manager:getGroupGain('vehicles') - 0.5 * 0.8 * 0.5) < 1e-9,
            'SoundManager group gain multiplies the hierarchy'
        )
        manager:setMuted(true)
        self:check(manager:isMuted() and manager:getGroupGain('vehicles') == 0, 'SoundManager mute')
        manager:setMuted(false)
        self:check(
            not pcall(manager.setMasterVolume, manager, 2),
            'SoundManager rejects volumes outside 0..1'
        )
        self:check(
            not pcall(manager.play, manager, 'a.wav', { group = 'missing' }),
            'unknown group'
        )
        local names = manager:getGroupNames()
        self:check(names[1] == 'effects' and #names == 5, 'SoundManager lists groups')

        -- AudioSource is a spatial Node3D with the Sound API.
        local source = create('AudioSource', {
            resource = 'probe.wav',
            position = { 10, 0, 20 },
            looped = true,
            volume = 0.8,
        })
        self:check(source:isA('AudioSource') and source:isA('Node3D'), 'AudioSource is a Node3D')
        self:check(source:isA('Sound'), 'AudioSource is accepted wherever Sound is')
        self:check(source.spatial == true, 'AudioSource is spatial by default')
        source:play()
        audio:update(nil)
        local voiceSource = source._voice.source
        self:check(
            voiceSource.position[1] == 10 and voiceSource.position[3] == -20,
            'AudioSource emits from its own transform'
        )
        local parent = create('Attachment3D', { position = { 0, 5, 0 } })
        local child =
            create('AudioSource', { resource = 'probe.wav', position = { 1, 0, 0 } }, parent)
        child:play()
        audio:update(nil)
        self:check(child._voice.source.position[2] == 5, 'AudioSource follows its parent transform')
        local reverb = create('SoundReverb', { decaytime = 1 }, source)
        self:check(reverb.parent == source, 'Sound effects can be children of an AudioSource')
        self:check(manager:getVoiceCount() == 2, 'SoundManager counts voices')
        source.position = { 40, 0, 0 }
        audio:update(nil)
        self:check(source._voice.source.position[1] == 40, 'AudioSource tracks position changes')
        source:stop()
        self:check(source.status == 'Stopped', 'AudioSource stops')
        local flat = create('AudioSource', { resource = 'probe.wav', spatial = false })
        self:check(flat.spatial == false, 'AudioSource spatial can be disabled')
        source:destroy()
        local registered = false
        for _, node in ipairs(audio.nodes) do
            registered = registered or node == source
        end
        self:check(not registered, 'Destroyed AudioSource unregisters')

        -- AudioListener replaces the camera as the listener.
        local camera = { worldPosition = { 1, 2, 3 }, forward = { 0, 0, 1 }, up = { 0, 1, 0 } }
        audio:update(camera)
        self:check(
            state.listener.position[1] == 1 and state.listener.position[3] == -3,
            'Camera is the listener when no AudioListener exists'
        )
        self:check(manager:getActiveListener() == nil, 'No active listener by default')
        local listener = create('AudioListener', { position = { 7, 8, 9 } })
        self:check(manager:getActiveListener() == listener, 'AudioListener becomes active')
        audio:update(camera)
        self:check(
            state.listener.position[1] == 7
                and state.listener.position[2] == 8
                and state.listener.position[3] == -9,
            'AudioListener overrides the camera position'
        )
        self:check(
            state.listener.orientation[3] == -1 and state.listener.orientation[5] == 1,
            'AudioListener faces +Z with +Y up (OpenAL mirrored)'
        )
        local second = create('AudioListener', { position = { 100, 0, 0 } })
        self:check(manager:getActiveListener() == listener, 'First enabled listener wins')
        listener.enabled = false
        self:check(manager:getActiveListener() == second, 'Disabled listener is skipped')
        second.enabled = false
        audio:update(camera)
        self:check(state.listener.position[1] == 1, 'Camera returns when listeners are disabled')
        listener:destroy()
        second:destroy()
        self:check(#audio.listeners == 0, 'Destroyed listeners unregister')

        -- Spatial attenuation uses the active listener.
        local emitter = create('AudioSource', {
            resource = 'probe.wav',
            position = { 0, 0, 0 },
            minDistance = 10,
            maxDistance = 110,
            rolloff = 'Linear',
        })
        emitter:play()
        local ear = create('AudioListener', { position = { 60, 0, 0 } })
        audio:update(camera)
        self:check(
            math.abs(emitter._voice.source.volume - audio:groupGain('master') * 0.5) < 1e-6,
            'Attenuation is measured from the AudioListener'
        )
        ear:destroy()

        manager:pauseAll()
        self:check(manager:isPaused(), 'SoundManager pauses')
        manager:resumeAll()
        manager:stopAll()
        self:check(manager:getVoiceCount() == 0 and emitter.status == 'Stopped', 'stopAll')
        audio:release()
    end)
    restore()
    assert(ok, err)
end

return Module
