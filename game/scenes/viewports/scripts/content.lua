-- Independent worlds share immutable resources, never lighting/camera/simulation state.
local Demo = {}
Demo.__index = Demo

function Demo.new(scene)
    return setmetatable({ scene = scene, views = {} }, Demo)
end

function Demo:update(dt)
    self.scene.world:updateNodes(dt)
end

return Demo
