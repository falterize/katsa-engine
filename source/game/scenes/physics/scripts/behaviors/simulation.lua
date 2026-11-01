local Methods = {}

function Methods:update(dt)
    local scene = self.scene
    if self.toolbar then
        self.toolbar.size = {
            0,
            math.min(340, scene.ui.width - 24),
            0,
            math.min(self.toolbar.length, math.max(88, scene.ui.height * 0.45 - 24)),
        }
    end
    scene.physics:update(dt)
    scene.world:updateNodes(dt)
end

return Methods
