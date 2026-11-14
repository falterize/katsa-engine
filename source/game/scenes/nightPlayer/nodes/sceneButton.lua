local SceneButton = { base = 'Mesh3D' }

function SceneButton.initialize(self)
    self.color = self.color or { 0.95, 0.3, 0.2, 1 }
end

function SceneButton:bindPhysics(physics, player, manager, factory, zone)
    self:connect('contactBegin', function(other)
        if not self.activated and other and other.node == player then
            self.activated = true
            manager:requestSwitch(factory, zone)
        end
    end)
    physics:addBody(self, { type = 'Static', friction = 0.8 })
end

function SceneButton.register(world)
    return world:registerNodeType('SceneButton', SceneButton)
end

return SceneButton
