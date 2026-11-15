local Abilities = {}
Abilities.__index = Abilities

function Abilities.new(lab)
    return setmetatable({
        lab = lab,
        jumps = 0,
        dashTime = 0,
        dashCooldown = 0,
        slideTime = 0,
        slideCooldown = 0,
        direction = { 0, 1 },
        velocity = {},
    }, Abilities)
end

function Abilities:jump()
    local c = self.lab.scene.character
    if c.grounded or c.sinceGrounded <= c.coyoteTime then
        c:jump()
        self.jumps = 1
    elseif self.jumps < 2 then
        local v = c.body:getVelocity(self.velocity)
        v[2] = c.jumpSpeed
        c.body:setVelocity(v)
        self.jumps = 2
    else
        return
    end
    self.lab.burst:emit(24)
end

function Abilities:dash()
    if self.dashCooldown > 0 then
        return
    end
    local c = self.lab.scene.character
    local yaw = math.rad(c.camera:getLookRotation()[2])
    local x, z = c.moveX, c.moveZ
    if math.abs(x) + math.abs(z) < 0.05 then
        x, z = 0, 1
    end
    local n = math.sqrt(x * x + z * z)
    self.direction[1] = (x * math.cos(yaw) + z * math.sin(yaw)) / n
    self.direction[2] = (z * math.cos(yaw) - x * math.sin(yaw)) / n
    self.dashTime = 0.2
    self.dashCooldown = 0.8
    self.lab.burst:emit(32)
end

function Abilities:slide()
    if self.slideCooldown > 0 or not self.lab.scene.character.grounded then
        return
    end
    self.slideTime = 0.65
    self.slideCooldown = 1.1
    self.lab.collider.height = 8
    self.lab.scene.character.height = 16
    local body = self.lab.body.physics
    local p = self.lab.body.position
    body:teleport({ p[1], p[2] - 8, p[3] })
    self.lab.rig.root.position[2] = -8
    self.lab.rig.root.rotation[1] = 60
    self.lab.burst:emit(16)
end

function Abilities:step(dt)
    local c = self.lab.scene.character
    self.dashCooldown = math.max(0, self.dashCooldown - dt)
    self.slideCooldown = math.max(0, self.slideCooldown - dt)
    c.speed = self.slideTime > 0 and 120 or 70
    c:step()
    if c.grounded then
        self.jumps = 0
    end
    if self.dashTime > 0 then
        self.dashTime = math.max(0, self.dashTime - dt)
        local v = c.body:getVelocity(self.velocity)
        v[1], v[3] = self.direction[1] * 230, self.direction[2] * 230
        v[2] = math.max(v[2], 0)
        c.body:setVelocity(v)
    end
    if self.slideTime > 0 then
        self.slideTime = math.max(0, self.slideTime - dt)
        if self.slideTime == 0 then
            local p = self.lab.body.position
            local hit = c.body.space:raycast(
                { p[1], p[2] + 8, p[3] },
                { p[1], p[2] + 24, p[3] },
                c.rayFilter
            )
            if hit then
                self.slideTime = 0.05
            else
                self.lab.collider.height = 24
                c.height = 32
                c.body:teleport({ p[1], p[2] + 8, p[3] })
                self.lab.rig.root.position[2] = -16
                self.lab.rig.root.rotation[1] = 0
            end
        end
    end
end

return Abilities
