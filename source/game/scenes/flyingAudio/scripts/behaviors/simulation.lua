local Methods = {}

-- The flight path: position at orbit time t (seconds of simulated physics).
function Methods.orbit(t)
    local angle = t * 0.65
    return math.sin(angle) * 110, 65 + math.sin(angle * 2) * 25, 90 + math.cos(angle) * 65
end

-- Runs before every fixed physics step. The kinematic body is given the exact velocity that lands
-- it on the next point of the path, independent of how many steps a frame runs (a per-frame
-- velocity from a stale position made the cube stutter). The renderer interpolates between steps.
function Methods:beforeStep(fixedDelta)
    if not (self.flying and self.placed) then
        return
    end
    local x0, y0, z0 = Methods.orbit(self.orbitTime)
    self.orbitTime = self.orbitTime + fixedDelta
    local x1, y1, z1 = Methods.orbit(self.orbitTime)
    local v = self.velocity
    v[1], v[2], v[3] = (x1 - x0) / fixedDelta, (y1 - y0) / fixedDelta, (z1 - z0) / fixedDelta
    self.flying.physics:setVelocity(v)
end

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
    if self.flying and not self.placed then
        -- Start on the orbit instead of launching the kinematic body across the map.
        self.placed = true
        local x, y, z = Methods.orbit(self.orbitTime)
        self.flying.position = { x, y, z }
        self.velocity[1], self.velocity[2], self.velocity[3] = 0, 0, 0
        self.flying.physics:setVelocity(self.velocity)
    end
    scene.physics:update(dt)
    scene.world:updateNodes(dt)
end

return Methods
