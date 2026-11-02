local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local Node = require('../core.baseNode')
local Sequence = require('../../animation.sequence')

local Ramp = Node.define('Ramp', 'Node')
Ramp.propertySchema = {
    layerGroup = {
        visibleWhen = function(node)
            return node.ui ~= nil
        end,
    },
    playing = { visibleWhen = { key = 'mode', equals = 'Animated' } },
    mode = { options = { 'Static', 'Animated' } },
    interpolation = {
        visibleWhen = function()
            return false
        end,
    },
    points = { kind = 'sequence' },
    bindings = {
        kind = 'bindings',
        visibleWhen = function()
            return false
        end,
    },
    goals = { kind = 'bindings' },
    target = { options = { 'Background', 'Text' } },
    offset = {},
    rotation = {},
    transparency = {},
    playbackTime = { min = 0.0001, visibleWhen = { key = 'mode', equals = 'Animated' } },
    reverses = { visibleWhen = { key = 'mode', equals = 'Animated' } },
    repeatCount = { min = -1, visibleWhen = { key = 'mode', equals = 'Animated' } },
    reverseDelay = { min = 0, visibleWhen = { key = 'mode', equals = 'Animated' } },
    repeatDelay = { min = 0, visibleWhen = { key = 'mode', equals = 'Animated' } },
    adornee = { kind = 'node' },
}
for _, key in ipairs({ 'target', 'offset', 'rotation', 'transparency' }) do
    Ramp.propertySchema[key].visibleWhen = function(node)
        return node:isSpatialGradient()
    end
end

function Ramp:getEnabled()
    return self._enabled ~= false
end

function Ramp:setEnabled(value)
    rawset(self, '_enabled', value ~= false)
    if self.enabled and self.track then
        self.track:apply(self.track._sampleTime or 0)
    end
    if self.ui then
        self.ui:invalidate()
    end
end

function Ramp:setPlaying(value)
    if value then
        self:play()
    else
        self:pause()
    end
end

function Ramp.initialize(self)
    self.layerGroup = self.layerGroup or 'Default'
    self.mode = self.mode or 'Static'
    self.interpolation = self.interpolation or 'Linear'
    self.application = nil
    self.points = self.points or Sequence.linear(0, 1)
    self.bindings = self.bindings or {}
    self.goals = self.goals or {}
    self.playbackTime = self.playbackTime or 1
    self.reverses = self.reverses == true
    self.repeatCount = self.repeatCount or 0
    self.reverseDelay = self.reverseDelay or 0
    self.repeatDelay = self.repeatDelay or 0
    self._requestedAdornee = rawget(self, 'adornee')
    rawset(self, 'adornee', nil)
    rawset(self, '_enabled', rawget(self, 'enabled') ~= false)
    rawset(self, 'enabled', nil)
    self._requestedPlaying = rawget(self, 'playing') == true
    rawset(self, 'playing', nil)
    self.target = self.target or 'Background'
    self.offset = self.offset or { 0, 0, 0, 0 }
    self.rotation = self.rotation or 0
    self.transparency = self.transparency or 0
    if self.colorStops then
        self.points = {}
        for _, stop in ipairs(self.colorStops) do
            self.points[#self.points + 1] = {
                time = stop.time,
                value = {
                    stop.color[1],
                    stop.color[2],
                    stop.color[3],
                    stop.transparency ~= nil and 1 - stop.transparency or stop.color[4] or 1,
                },
            }
        end
        self.colorStops = nil
    end
    self.points.interpolation = self.points.interpolation or self.interpolation
    Sequence.validate(self.points)
    for _, points in pairs(self.bindings) do
        points.interpolation = points.interpolation or self.interpolation
        Sequence.validate(points)
    end
end

function Ramp.mount(context, properties, parent)
    local node = Node.new('Ramp', properties, parent)
    node.ui = parent and parent.ui
    local owner = parent
    if owner and owner:isA('UINode') and Array.is(node.points[1].value) then
        local key = owner:isA('UIStroke') and 'color'
            or node.target == 'Text' and 'textColor'
            or 'backgroundColor'
        local alpha = key == 'color' and 'transparency' or key:gsub('Color$', 'Transparency')
        local colors, transparency = {}, {}
        for _, point in ipairs(node.points) do
            colors[#colors + 1] = {
                time = point.time,
                value = { point.value[1], point.value[2], point.value[3] },
                incoming = point.incoming,
                outgoing = point.outgoing,
            }
            transparency[#transparency + 1] = {
                time = point.time,
                value = 1 - (point.value[4] or 1),
                incoming = point.incoming,
                outgoing = point.outgoing,
            }
        end
        node.bindings[key], node.bindings[alpha] = colors, transparency
        node.goals[key], node.goals[alpha] =
            colors[#colors].value, transparency[#transparency].value
        colors.interpolation, transparency.interpolation =
            node.points.interpolation, node.points.interpolation
        node.points = Sequence.linear(0, 1)
    end
    node:setAdornee(node._requestedAdornee)
    node._requestedAdornee = nil
    node:onDestroy(function()
        if node.track then
            node.track:destroy()
        end
    end)
    if node._requestedPlaying then
        node:play()
    end
    node._requestedPlaying = nil
    return node
end

function Ramp:setAdornee(target)
    assert(
        target == nil
            or target._node
                and not target.destroyed
                and target ~= self
                and target._sceneWorld == self._sceneWorld,
        'Ramp Adornee must be a live same-world node'
    )
    rawset(self, '_adornee', target)
    return self
end

function Ramp:evaluate(time, out)
    return Sequence.evaluate(self.points, math.max(0, math.min(1, time)), self.interpolation, out)
end

function Ramp:apply(time)
    if not self.enabled then
        return
    end
    time = self:evaluate(time)
    assert(type(time) == 'number', 'Properties Ramp.points must describe scalar progress')
    local target = self.adornee or self.parent
    assert(target and not target.destroyed, 'Ramp requires a live Parent or Adornee')
    for key, goal in pairs(self.goals) do
        if not self.bindings[key] then
            self._staticStarts = self._staticStarts or {}
            self._staticStarts[key] = self._staticStarts[key]
                or require('source.engine.animation.rampGoals').value(self, key)
            require('source.engine.animation.bindings').set(
                target,
                key,
                Sequence.evaluate(
                    Sequence.linear(self._staticStarts[key], goal),
                    time,
                    self.interpolation
                )
            )
        end
    end
    for key, points in pairs(self.bindings) do
        self._buffers = self._buffers or {}
        local value = Sequence.evaluate(points, time, self.interpolation, self._buffers[key])
        if Array.is(value) then
            self._buffers[key] = value
        end
        require('source.engine.animation.bindings').set(target, key, value)
    end
end

function Ramp:exportData()
    local data = {}
    for _, key in ipairs({
        'mode',
        'interpolation',
        'points',
        'bindings',
        'goals',
        'playbackTime',
        'reverses',
        'repeatCount',
        'reverseDelay',
        'repeatDelay',
        'target',
        'offset',
        'rotation',
        'transparency',
    }) do
        data[key] = require('source.engine.animation.bindings').copy(self[key])
    end
    return data
end

function Ramp:play()
    assert(self.mode == 'Animated', 'Only Animated Ramp has playback; Static uses apply/evaluate')
    assert(not self:isLifetime(), 'Lifetime Ramp is sampled by particle age; use Static mode')
    local target = self.adornee or self.parent
    if not self:isSpatialGradient() then
        require('source.engine.animation.rampGoals').ensureTarget(self)
    end
    if self.track then
        self.track:destroy()
    end
    self.track = require('source.engine.animation.tween').new(target, {
        ramp = not self:isSpatialGradient() and self or nil,
        playbackTime = self.playbackTime,
        reverses = self.reverses,
        repeatCount = self.repeatCount,
        reverseDelay = self.reverseDelay,
        repeatDelay = self.repeatDelay,
        interpolation = self.interpolation,
        bindings = self.bindings,
        owner = self,
    }, self.goals)
    for _, event in ipairs({ 'Started', 'Completed', 'Stopped', 'Resumed' }) do
        self.track[event]:connect(function(track)
            if event == 'Completed' or event == 'Stopped' then
                rawset(self, '_playing', false)
            end
            self:emit(event, track)
        end)
    end
    self.track:play()
    rawset(self, '_playing', true)
    return self
end
for _, method in ipairs({ 'stop', 'pause', 'resume' }) do
    Ramp[method] = function(self)
        rawset(self, '_playing', method == 'resume')
        if self.track then
            self.track[method](self.track)
        end
        return self
    end
end
require('../../animation.rampLayout').install(Ramp)
return Ramp
