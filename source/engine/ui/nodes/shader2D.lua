local Node = require('source.engine.nodes')

local Shader = Node.define('Shader2D', 'Frame')
Shader.propertySchema = {
    shaderPath = {},
    shaderTransparency = { min = 0, max = 1 },
    shaderLayer = {},
    zIndex = {},
    uniforms = { kind = 'bindings' },
}

function Shader.initialize(self)
    self.shaderPath = self.shaderPath or ''
    self.shaderTransparency = self.shaderTransparency or 0
    self.shaderLayer = self.shaderLayer or 'Default'
    self.zIndex = self._zIndexAuthored and self.zIndex or self.order or self.zIndex or 0
    self.order = nil
    self.uniforms = self.uniforms or {}
end

return Shader
