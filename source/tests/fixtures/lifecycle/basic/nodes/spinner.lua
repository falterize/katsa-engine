local Spinner = {
    base = 'Mesh3D',
    properties = {
        spinSpeed = { default = 45, min = -360, max = 360, hint = 'Degrees per second.' },
    },
}

function Spinner.initialize(self)
    self:onDestroy(function()
        self.wasReleased = true
    end)
end

function Spinner:start()
    self:addTag('Animated')
end

function Spinner:update(dt)
    self.rotation[2] = self.rotation[2] + self.spinSpeed * dt
end

function Spinner.register(world)
    return world:registerNodeType('Spinner', Spinner)
end

return Spinner
