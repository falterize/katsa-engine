local ipairs = require('source.engine.math.array').ipairs
local Node = require('source.engine.nodes.core.baseNode')
local Routing = require('source.engine.audio.nodeEffects')

local Sound = Node.define('Sound', 'Node')
Sound.propertySchema = { playing = {}, enabled = {} }

function Sound:getEnabled()
    return self._enabled ~= false
end

function Sound:setEnabled(value)
    rawset(self, '_enabled', value ~= false)
    if self._audio then
        self:sync()
    end
end

function Sound:setPlaying(value)
    if value then
        self:play()
    else
        self:pause()
    end
end

function Sound.initialize(self)
    self.resource = self.resource or ''
    self.volume = self.volume or 1
    self.playbackSpeed = self.playbackSpeed or 1
    self.looped = self.looped == true
    self.spatial = self.spatial == true
    self.stream = self.stream == true
    rawset(self, '_enabled', rawget(self, 'enabled') ~= false)
    rawset(self, 'enabled', nil)
    self._requestedPlaying = rawget(self, 'playing') == true
    rawset(self, 'playing', nil)
    self.minDistance = self.minDistance or 20
    self.maxDistance = self.maxDistance or 300
    self.rolloff = self.rolloff or 'LinearSquare'
    self.stereoWidth = self.stereoWidth or 4
    self.timeScaled = self.timeScaled ~= false
    self.status = 'Stopped'
    self._effects = {}
end

function Sound.mount(world, properties, parent)
    assert(world.audio, 'World3D.audio must be assigned before creating sound nodes')
    properties._audio = world.audio
    local node = Node.new(properties.className or 'Sound', properties, parent)
    local nodes = world.audio.nodes
    nodes[#nodes + 1] = node
    node:onDestroy(function()
        node:stop()
        for i = #nodes, 1, -1 do
            if nodes[i] == node then
                table.remove(nodes, i)
                break
            end
        end
    end)
    if node._requestedPlaying then
        node:play()
    end
    node._requestedPlaying = nil
    return node
end

local function collect(effects, owner)
    for _, child in ipairs(owner.children) do
        if child:isA('SoundEffect') and child.enabled then
            effects[#effects + 1] = child
        end
    end
end

function Sound:sync(deferApply)
    local v = self._voice
    if not v or v.released then
        rawset(self, '_playing', false)
        self.status = 'Stopped'
        return
    end
    if self.spatial then
        -- AudioSource is itself a Node3D; Sound follows its nearest spatial ancestor.
        local parent = self.getWorldMatrix and self or self.parent
        while parent and not parent.getWorldMatrix do
            parent = parent.parent
        end
        if not parent then
            self:stop()
            self.status = 'Detached'
            return
        end
    end
    local effects = self._effects
    for i = #effects, 1, -1 do
        effects[i] = nil
    end
    local gain = self.enabled and self.volume or 0
    local group = self.group
    if group then
        assert(
            group:isA('SoundGroup') and not group.destroyed and group._audio == self._audio,
            'Sound.group must be a live SoundGroup from this audio scene'
        )
    else
        local parent = self.parent
        while parent do
            if parent:isA('SoundGroup') then
                group = parent
                break
            end
            parent = parent.parent
        end
    end
    local chain = self._groups or {}
    self._groups = chain
    for i = #chain, 1, -1 do
        chain[i] = nil
    end
    local cursor = group
    while cursor do
        if cursor:isA('SoundGroup') then
            assert(
                cursor.volume >= 0 and cursor.volume <= 1,
                'SoundGroup.volume must be between 0 and 1'
            )
            gain = gain * (cursor.muted and 0 or cursor.volume)
            chain[#chain + 1] = cursor
        end
        cursor = cursor.parent
    end
    for i = #chain, 1, -1 do
        collect(effects, chain[i])
    end
    collect(effects, self)
    for _, effect in ipairs(effects) do
        if effect.parent == self then
            effect._wetMuted = gain == 0
        end
    end
    local pitch = self.playbackSpeed
    for _, effect in ipairs(effects) do
        if effect.effectType == 'pitch' then
            pitch = pitch * effect.playbackSpeed
            effect.status = 'Applied'
        end
    end
    assert(
        pitch > 0 and pitch < math.huge,
        'Combined Sound playbackSpeed must be positive and finite'
    )
    pitch = math.min(8, pitch)
    v.volume, v.pitch, v.minDistance, v.maxDistance, v.rolloff, v.stereoWidth =
        gain, pitch, self.minDistance, self.maxDistance, self.rolloff, self.stereoWidth
    assert(
        v.spatial == self.spatial
            and v.nodeResource == self.resource
            and v.nodeStream == self.stream,
        'Stop and play Sound after changing resource, stream or spatial mode'
    )
    if v.nodeLooped ~= self.looped then
        for _, source in ipairs(v.sources) do
            source:setLooping(self.looped)
        end
        v.nodeLooped = self.looped
    end
    Routing.apply(self._audio, self, v, effects)
    if not deferApply then
        self._audio:apply(v)
    end
    self.status = (self._audio.paused or v.timePaused) and 'Suspended'
        or (v.manualPause and 'Paused' or 'Playing')
end

function Sound:getWorldPosition(out)
    local parent = self.parent
    while parent and not parent.getWorldMatrix do
        parent = parent.parent
    end
    assert(parent, 'Spatial Sound requires a Node3D ancestor')
    return parent:getWorldPosition(out)
end

function Sound:getEmitterMatrix()
    local parent = self.parent
    while parent and not parent.getWorldMatrix do
        parent = parent.parent
    end
    assert(parent, 'Spatial Sound requires a Node3D ancestor')
    return parent:getWorldMatrix()
end

function Sound:play()
    rawset(self, '_playing', true)
    assert(not self.destroyed and not self._destroying, 'Sound requires a live node')
    assert(self._audio, 'Sound must be created through World3D:create')
    if self.spatial then
        self:getWorldPosition()
    end
    if self._voice and not self._voice.released and not self._voice.stopped then
        self._voice:resume()
        self:sync()
        return self
    end
    self:stop()
    self._voice = self._audio:play(self.resource, {
        volume = self.volume,
        pitch = self.playbackSpeed,
        loop = self.looped,
        stream = self.stream,
        object = self.spatial and self or nil,
        minDistance = self.minDistance,
        maxDistance = self.maxDistance,
        rolloff = self.rolloff,
        stereoWidth = self.stereoWidth,
        group = 'master',
        timeScaled = self.timeScaled,
        autoplay = false,
    })
    self._voice.nodeResource, self._voice.nodeStream = self.resource, self.stream
    self:sync()
    self._voice:resume()
    self.status = 'Playing'
    rawset(self, '_playing', true)
    return self
end

function Sound:pause()
    rawset(self, '_playing', false)
    if self._voice and not self._voice.released then
        self._voice:pause()
        self.status = 'Paused'
    end
    return self
end

function Sound:stop()
    rawset(self, '_playing', false)
    if self._audio then
        for _, effect in ipairs(self.children) do
            if effect:isA('SoundEffect') and effect._defined then
                self._audio:removeEffect(effect)
            end
        end
    end
    if self._voice then
        self._voice:release()
        self._voice = nil
    end
    self.status = 'Stopped'
    return self
end

function Sound:isPlaying()
    return self._voice and self._voice:isPlaying() or false
end

function Sound:seek(seconds)
    assert(self._voice and not self._voice.released, 'Sound must be loaded before seeking')
    assert(
        type(seconds) == 'number' and seconds >= 0 and seconds < math.huge,
        'Invalid playback time'
    )
    for _, source in ipairs(self._voice.sources) do
        source:seek(seconds, 'seconds')
    end
    return self
end

function Sound:tell()
    return self._voice and not self._voice.released and self._voice.source:tell('seconds') or 0
end

return Sound
