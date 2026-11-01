-- AudioSource: a Node3D that emits sound from its own transform. It has the full Sound API
-- (play/pause/stop/seek, effects as children, groups) and is spatial by default. Sound remains
-- available for emitters that follow an Attachment3D parent.
local Node = require('source.engine.nodes.core.baseNode')
local Sound = require('source.engine.nodes.audio.sound')

local Source = Node.define('AudioSource', 'Node3D')
-- Effects, groups and the inspector treat an AudioSource as a Sound.
Source._types.Sound = true

for key, value in pairs(Sound) do
    if type(value) == 'function' and Source[key] == nil or key == 'propertySchema' then
        rawset(Source, key, value)
    end
end

function Source.initialize(self)
    local spatial = rawget(self, 'spatial')
    Sound.initialize(self)
    self.spatial = spatial ~= false
end

function Source.mount(world, properties, parent)
    properties.className = 'AudioSource'
    return Sound.mount(world, properties, parent)
end

function Source:getWorldPosition(out)
    return Node.classes.Node3D.getWorldPosition(self, out)
end

function Source:getEmitterMatrix()
    return self:getWorldMatrix()
end

return Source
