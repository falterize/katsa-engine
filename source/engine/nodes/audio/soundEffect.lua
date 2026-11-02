local Node = require('../core.baseNode')

local Effect = Node.define('SoundEffect', 'Node')
local serial = 0

function Effect.initialize(self)
    serial = serial + 1
    self.enabled = self.enabled ~= false
    self.volume = self.volume or 1
    self._effectName = 'SBoxEffect' .. serial
    self.status = 'Not applied'
end

function Effect.mount(world, properties, parent)
    assert(world.audio, 'World3D.audio must be assigned before creating sound effects')
    properties._audio = world.audio
    local node = Node.new(properties.className, properties, parent)
    local effects = world.audio.effects
    effects[#effects + 1] = node
    node:onDestroy(function()
        world.audio:removeEffect(node)
        for i = #effects, 1, -1 do
            if effects[i] == node then
                table.remove(effects, i)
                break
            end
        end
    end)
    return node
end

return Effect
