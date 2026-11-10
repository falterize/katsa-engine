local Node = require('../core.baseNode')

local Class = Node.define('DirectionalLight3D', 'Node3D')

require('../../components.illumination.shadowing').describe(Class, { receive = false, cutoff = false })
require('../../components.ordering.priority').describe(Class)

function Class.initialize(self)
    -- Rotation is the single orientation control. Convert old creation input once.
    if self.direction then
        self.rotation = require('source.engine.graphics.lighting.orientation').rotation(self.direction)
        self.direction = nil
    end
    self.color = self.color or { 255, 245, 220 }
    self.brightness = self.brightness or 1
    self.enabled = self.enabled ~= false
    require('source.engine.components.illumination.shadowing').normalize(self, { castShadow = true })
    self.shadowLayers = self.shadowLayers or -1
    require('source.engine.components.ordering.priority').normalize(self)
end

function Class.mount(world, properties, parent)
    properties.parent, properties.type = parent, properties.className
    local node = world:addLight(properties)
    world.directionalLights[#world.directionalLights + 1] = node
    node:onDestroy(function()
        for i = #world.directionalLights, 1, -1 do
            if world.directionalLights[i] == node then
                table.remove(world.directionalLights, i)
            end
        end
    end)
    return node
end

return Class
