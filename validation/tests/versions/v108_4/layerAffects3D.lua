-- Shader layers can forbid their Shader2D nodes from affecting the 3D scene.
local Module = {}

function Module.run(self)
    local layers = require('source.engine.shaders.layers').new()
    layers:add('Fx')
    self:check(layers:affects3D('Fx'), 'shader layers allow 3D by default')
    layers:setAffects3D('Fx', false)
    self:check(not layers:affects3D('Fx'), 'a layer can forbid affecting 3D')
    self:check(layers:affects3D('Default'), 'other layers keep their own setting')
    layers:setAffects3D('Fx', true)
    self:check(layers:affects3D('Fx'), 'a layer can allow 3D again')
end

return Module
