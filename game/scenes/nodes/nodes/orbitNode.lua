local OrbitNode = { base = 'Node3D' }

function OrbitNode.initialize(self)
    self.angularSpeed = self.angularSpeed or 25
end

function OrbitNode:update(dt)
    self.rotation[2] = self.rotation[2] + self.angularSpeed * dt
end

function OrbitNode.register(world)
    return world:registerNodeType('OrbitNode', OrbitNode)
end

return OrbitNode
