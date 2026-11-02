local ipairs = require('../../math.array').ipairs
local Node = require('../core.baseNode')

local Shader = Node.define('Shader3D', 'Folder')
Shader.propertySchema = {
    shaderPath = {},
    shaderLayer = {},
    zIndex = {},
    uniforms = { kind = 'bindings' },
    animated = {},
    boundsMode = { options = { 'Conservative', 'Padding' } },
    shadowBoundsPadding = { min = 0, visibleWhen = { key = 'boundsMode', equals = 'Padding' } },
}

function Shader.initialize(self)
    self.enabled = self.enabled ~= false
    self.shaderPath = self.shaderPath or ''
    if self.shaderLayer == nil or self.shaderLayer == 'Default' then
        self.shaderLayer = 'Default3D'
    end
    self.zIndex = self._zIndexAuthored and self.zIndex or self.order or self.zIndex or 0
    self.order = nil
    self.uniforms = self.uniforms or {}
    self.animated = self.animated == true
    self.boundsMode = self.boundsMode or 'Conservative'
    self.shadowBoundsPadding = self.shadowBoundsPadding or 0
end

function Shader.mount(world, properties, parent)
    local node = Node.new('Shader3D', properties, parent)
    world.shaderNodes = world.shaderNodes or {}
    world.shaderNodes[#world.shaderNodes + 1] = node
    node:onDestroy(function()
        for i, item in ipairs(world.shaderNodes) do
            if item == node then
                table.remove(world.shaderNodes, i)
                break
            end
        end
    end)
    return node
end

return Shader
