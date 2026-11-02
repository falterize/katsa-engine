local ipairs = require('../../math.array').ipairs

local Character = {}
Character.__index = Character
local probes = { { 0, 0 }, { -0.5, 0 }, { 0.5, 0 }, { 0, -0.5 }, { 0, 0.5 } }

local function approach(current, target, delta)
    return current < target and math.min(target, current + delta)
        or math.max(target, current - delta)
end

function Character.new(body, camera, settings)
    settings = settings or {}
    body:set({
        rotationFactor = { 0, 0, 0 },
        autoSleep = false,
        friction = settings.friction or 0.2,
    })
    return setmetatable({
        body = body,
        camera = camera,
        speed = settings.speed or 65,
        jumpSpeed = settings.jumpSpeed or 100,
        radius = settings.radius or 8,
        height = settings.height or 32,
        acceleration = settings.acceleration or 650,
        airAcceleration = settings.airAcceleration or 220,
        maxSlopeAngle = settings.maxSlopeAngle or 50,
        coyoteTime = settings.coyoteTime or 0.1,
        jumpBuffer = settings.jumpBuffer or 0.12,
        groundTolerance = settings.groundTolerance or 3,
        moveX = 0,
        moveZ = 0,
        velocity = {},
        rayStart = {},
        rayEnd = {},
        rayHit = {},
        groundNormal = { 0, 1, 0 },
        sinceGrounded = math.huge,
        jumpRemaining = 0,
        rayFilter = function(other)
            return other ~= body and other.canCollide
        end,
    }, Character)
end

function Character:setMove(x, z)
    self.moveX, self.moveZ = x, z
end

function Character:jump()
    self.jumpRemaining = self.jumpBuffer
end

function Character:step()
    local body, dt = self.body, self.body.physics.fixedDelta
    body:sync()
    local p, v = body.object.position, body:getVelocity(self.velocity)
    local foot = p[2] - self.height / 2
    self.grounded = false
    if v[2] < 10 then
        local minNormal = math.cos(math.rad(self.maxSlopeAngle))
        for _, probe in ipairs(probes) do
            local x, z = p[1] + probe[1] * self.radius, p[3] + probe[2] * self.radius
            self.rayStart[1], self.rayStart[2], self.rayStart[3] = x, foot + self.radius, z
            self.rayEnd[1], self.rayEnd[2], self.rayEnd[3] = x, foot - self.groundTolerance, z
            local hit =
                body.physics:raycast(self.rayStart, self.rayEnd, self.rayFilter, self.rayHit)
            if hit and hit.normal[2] >= minNormal then
                self.grounded = true
                for i = 1, 3 do
                    self.groundNormal[i] = hit.normal[i]
                end
                break
            end
        end
    end
    self.sinceGrounded = self.grounded and 0 or self.sinceGrounded + dt
    local yaw = math.rad(self.camera:getLookRotation()[2])
    local length = math.max(1, math.sqrt(self.moveX ^ 2 + self.moveZ ^ 2))
    local x, z = self.moveX / length, self.moveZ / length
    local targetX = (x * math.cos(yaw) + z * math.sin(yaw)) * self.speed
    local targetZ = (z * math.cos(yaw) - x * math.sin(yaw)) * self.speed
    local acceleration = (self.grounded and self.acceleration or self.airAcceleration) * dt
    v[1], v[3] = approach(v[1], targetX, acceleration), approach(v[3], targetZ, acceleration)
    if self.jumpRemaining > 0 and self.sinceGrounded <= self.coyoteTime then
        v[2], self.jumpRemaining, self.sinceGrounded = self.jumpSpeed, 0, math.huge
        self.grounded = false
    end
    self.jumpRemaining = math.max(0, self.jumpRemaining - dt)
    body:setVelocity(v)
end

return Character
