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
    if self.head then
        local camera = scene.camera
        local look = camera:getLookRotation()
        self.flashlight.rotation[1], self.flashlight.rotation[2], self.flashlight.rotation[3] =
            -look[1], -look[2], 0
        self.flashlight.nextUpdate = 0
    end
end

return Methods
