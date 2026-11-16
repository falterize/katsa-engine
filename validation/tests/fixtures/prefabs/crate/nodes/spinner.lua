-- A node type of the prefab scene: its `update` runs in every world that holds a copy.
local Spinner = {
    base = 'Node3D',
    properties = { speed = { default = 90, hint = 'Degrees per second around Y.' } },
}

function Spinner:update(dt)
    self.rotation = { 0, self.rotation[2] + self.speed * dt, 0 }
end

function Spinner.register(world)
    return world:registerNodeType('Spinner', Spinner)
end

return Spinner
