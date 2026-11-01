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
    if self.flying then
        local angle = scene.time * 0.65
        local x, y, z =
            math.sin(angle) * 110, 65 + math.sin(angle * 2) * 25, 90 + math.cos(angle) * 65
        local p = self.flying.position
        if dt > 0 then
            self.velocity[1], self.velocity[2], self.velocity[3] =
                (x - p[1]) / dt, (y - p[2]) / dt, (z - p[3]) / dt
            self.flying.body:setVelocity(self.velocity)
        end
    end
    scene.physics:update(dt)
    scene.world:updateNodes(dt)
end

return Methods
