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
    -- Whether the effect also processes the 3D render is decided by the shader layer matrix:
    -- the layer must interact with Default3D (off between Default2D and Default3D at start).
    if self.shaderLayer == nil or self.shaderLayer == 'Default' then
        self.shaderLayer = 'Default2D'
    end
    self.affects3D = nil
    self.zIndex = self._zIndexAuthored and self.zIndex or self.order or self.zIndex or 0
    self.order = nil
    self.uniforms = self.uniforms or {}
end

return Shader
