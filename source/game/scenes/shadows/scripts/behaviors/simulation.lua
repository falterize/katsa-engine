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
    if self.shadowCube then
        local target = self.shadowMotion and math.sin(scene.time) * 55
            or self.shadowCube.position[1]
        if dt > 0 then
            self.velocity[1], self.velocity[2], self.velocity[3] =
                (target - self.shadowCube.position[1]) / dt, 0, 0
            self.shadowCube.physics:setVelocity(self.velocity)
        end
    end
    scene.physics:update(dt)
    scene.world:updateNodes(dt)
end

return Methods
