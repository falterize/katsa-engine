-- Shader layers: Default2D / Default3D, a symmetric interaction matrix and the 3D rule.
local Module = {}

function Module.run(self)
    local layers = require('source.engine.shaders.layers').new()
    self:check(
        layers.names[1] == 'Default2D' and layers.names[2] == 'Default3D',
        'shader layers start with Default2D and Default3D'
    )
    self:check(not layers:interacts('Default2D', 'Default3D'), '2D and 3D start separated')
    self:check(not layers:affects3D('Default2D'), 'Default2D does not process the 3D render')
    layers:setInteracts('Default2D', 'Default3D', true)
    self:check(layers:affects3D('Default2D'), 'interacting with Default3D lets a layer process 3D')
    self:check(layers:interacts('Default3D', 'Default2D'), 'the matrix is symmetric')
    layers:setInteracts('Default2D', 'Default3D', false)
    layers:add('Pixel', 20)
    self:check(layers:interacts('Pixel', 'Default3D'), 'new layers interact with existing ones')
    layers:setInteracts('Pixel', 'Default3D', false)
    self:check(layers:suppresses('Pixel', 'Default3D'), 'a higher non-interacting layer suppresses')
    self:check(not layers:suppresses('Default3D', 'Pixel'), 'a lower layer never suppresses upward')
    layers:rename('Pixel', 'Retro')
    self:check(layers:priority('Retro') == 20 and not layers:interacts('Retro', 'Default3D'), 'rename keeps priority and links')
    layers:remove('Retro')
    self:check(layers.priorities.Retro == nil, 'a layer can be removed')
end

return Module
