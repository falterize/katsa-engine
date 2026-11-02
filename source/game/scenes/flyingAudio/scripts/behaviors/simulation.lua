local Methods = {}

-- Units per second; the orbit itself needs about 100.
local MAX_SPEED = 400

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
        if not self.placed then
            -- The orbit starts away from the spawn point; teleport once instead of launching the
            -- kinematic body across the map in a single tiny first step.
            self.placed = true
            self.flying.position = { x, y, z }
            self.velocity[1], self.velocity[2], self.velocity[3] = 0, 0, 0
            self.flying.body:setVelocity(self.velocity)
        elseif dt > 0 then
            -- A near-zero frame delta (the first frame after loading) must not turn a small
            -- displacement into an enormous or non-finite velocity.
            local step = math.max(dt, 1 / 120)
            local vx, vy, vz = (x - p[1]) / step, (y - p[2]) / step, (z - p[3]) / step
            local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
            if speed ~= speed or speed == math.huge then
                vx, vy, vz = 0, 0, 0
            elseif speed > MAX_SPEED then
                local scale = MAX_SPEED / speed
                vx, vy, vz = vx * scale, vy * scale, vz * scale
            end
            self.velocity[1], self.velocity[2], self.velocity[3] = vx, vy, vz
            self.flying.body:setVelocity(self.velocity)
        end
    end
    scene.physics:update(dt)
    scene.world:updateNodes(dt)
end

return Methods
