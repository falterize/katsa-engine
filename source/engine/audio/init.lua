local ipairs = require('../math.array').ipairs
local Voice = require('./voice')

local Audio = {}
Audio.__index = Audio
local Validation = require('./validation')
local modes, unit = Validation.modes, Validation.unit

function Audio.new(options)
    options = options or {}
    local self = setmetatable({
        clock = options.clock,
        groups = options.groups or {
            master = { volume = 0.85 },
            music = { volume = 0.7, parent = 'master' },
            effects = { volume = 0.8, parent = 'master' },
            ui = { volume = 0.8, parent = 'master' },
        },
        voices = {},
        nodes = {},
        effects = {},
        samples = {},
        paused = false,
        listener = { 0, 0, 0 },
        listeners = {},
        resources = options.resources or require('source.engine.core.resources').new(),
    }, Audio)
    self.manager = require('source.engine.audio.manager').new(self)
    return self
end

function Audio:scope(resources)
    return Audio.new({
        clock = self.clock,
        groups = self.groups,
        resources = resources or self.resources:scope(),
    })
end

function Audio:addGroup(name, options)
    assert(
        type(name) == 'string' and not self.groups[name],
        'Sound group already exists: ' .. tostring(name)
    )
    options = options or {}
    local parent = options.parent or 'master'
    assert(self.groups[parent], 'Unknown parent sound group: ' .. parent)
    unit(options.volume or 1, 'Group volume')
    self.groups[name] =
        { volume = options.volume or 1, parent = parent, muted = options.muted or false }
    return self.groups[name]
end

function Audio:setGroupVolume(name, volume)
    unit(volume, 'Group volume')
    assert(self.groups[name], 'Unknown sound group: ' .. tostring(name)).volume = volume
end

function Audio:getGroupVolume(name)
    return assert(self.groups[name], 'Unknown sound group: ' .. tostring(name)).volume
end

function Audio:setGroupMuted(name, muted)
    assert(self.groups[name], 'Unknown sound group: ' .. tostring(name)).muted = not not muted
end

function Audio:groupGain(name)
    local gain, depth = 1, 0
    while name do
        local group = assert(self.groups[name], 'Unknown sound group: ' .. tostring(name))
        unit(group.volume, 'Group volume')
        gain = gain * (group.muted and 0 or group.volume)
        name, depth = group.parent, depth + 1
        assert(depth <= 32, 'Sound group parent cycle or hierarchy deeper than 32')
    end
    return gain
end
require('./playback').install(Audio)
require('./spatial').install(Audio)

function Audio:update(camera)
    local node = self.manager:getActiveListener()
    if node then
        local position, forward, up =
            node:getPose(self._listenerPosition, self._listenerForward, self._listenerUp)
        self._listenerPosition, self._listenerForward, self._listenerUp = position, forward, up
        camera = { worldPosition = position, forward = forward, up = up }
    end
    if camera then
        for i = 1, 3 do
            self.listener[i] = (camera.worldPosition or camera.position)[i]
        end
        -- Mirror Z to map the left-handed game world into OpenAL coordinates.
        katsa.audio.setPosition(self.listener[1], self.listener[2], -self.listener[3])
        katsa.audio.setOrientation(
            camera.forward[1],
            camera.forward[2],
            -camera.forward[3],
            camera.up[1],
            camera.up[2],
            -camera.up[3]
        )
    end
    for _, node in ipairs(self.nodes) do
        if not node.destroyed then
            node:sync(true)
        end
    end
    local routing = require('source.engine.audio.effects.routing')
    for _, effect in ipairs(self.effects) do
        if effect._defined then
            if not effect.enabled then
                routing.remove(self, effect)
            else
                routing.define(self, effect)
            end
        end
    end
    for i = #self.voices, 1, -1 do
        local v = self.voices[i]
        self:apply(v)
        if
            v.released
            or v.stopped
            or (not self.paused and not v.manualPause and not v.timePaused and not v:isPlaying())
        then
            v:release()
            table.remove(self.voices, i)
        end
    end
end

function Audio:refreshEffects()
    local routing = require('source.engine.audio.effects.routing')
    for _, effect in ipairs(self.effects) do
        if effect._defined then
            routing.define(self, effect)
        end
    end
end

function Audio:pause()
    if self.paused then
        return
    end
    self.paused = true
    self:refreshEffects()
    for _, v in ipairs(self.voices) do
        v.wasPlaying = v:isPlaying()
        for _, source in ipairs(v.sources) do
            source:pause()
        end
    end
end

function Audio:resume()
    if not self.paused then
        return
    end
    self.paused = false
    self:refreshEffects()
    for _, v in ipairs(self.voices) do
        self:apply(v)
        if v.wasPlaying and not v.manualPause and not v.timePaused then
            for _, source in ipairs(v.sources) do
                source:play()
            end
        end
    end
end

function Audio:stop()
    for _, effect in ipairs(self.effects) do
        self:removeEffect(effect)
    end
    for _, v in ipairs(self.voices) do
        v:release()
    end
    self.voices = {}
    local previous = self.resources
    self.resources = previous:scope()
    previous:release()
    self.samples = {}
end

function Audio:removeEffect(node)
    require('source.engine.audio.effects.routing').remove(self, node)
end

function Audio:release()
    if self.released then
        return
    end
    self.released = true
    self:stop()
    self.resources:release()
end
return Audio
