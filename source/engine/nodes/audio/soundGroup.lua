local ipairs = require('source.engine.math.array').ipairs
local Node = require('source.engine.nodes.core.baseNode')

local Group = Node.define('SoundGroup', 'Node')

function Group.initialize(self)
    self.volume = self.volume or 1
    self.muted = self.muted == true
end

function Group.mount(world, properties, parent)
    assert(world.audio, 'World3D.audio must be assigned before creating sound nodes')
    properties._audio = world.audio
    local node = Node.new(properties.className or 'SoundGroup', properties, parent)
    node:onDestroy(function()
        for _, sound in ipairs(world.audio.nodes) do
            if sound.group == node then
                sound:stop()
                sound.group = nil
            end
        end
    end)
    return node
end

return Group
