local Content = {}
Content.__index = Content
function Content.new(scene)
    return setmetatable({ scene = scene, steps = 0, events = {} }, Content)
end

function Content:update(dt)
    self.steps = self.steps + 1
    self.scene.world:updateNodes(dt)
end
return Content
