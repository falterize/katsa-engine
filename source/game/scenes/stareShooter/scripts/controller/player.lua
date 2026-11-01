local Machine = require('scene.scripts.fsm.machine')
local Math = require('scene.scripts.controller.math')
local StepValue = require('source.engine.animation.stepValue')

local Player = {}
Player.__index = Player

function Player.new(body, collider, camera, settings)
    local self = setmetatable({
        body = body,
        collider = collider,
        camera = camera,
        settings = settings,
        height = settings.standingHeight,
        targetHeight = settings.standingHeight,
        input = { x = 0, z = 0, jump = false, crouch = false, sprint = false, shiftlock = false },
        direction = { 0, 0, 0 },
        velocity = { 0, 0, 0 },
        rayStart = {},
        rayEnd = {},
        rayHit = {},
        visualYaw = math.pi,
        cameraYaw = 0,
        grounded = true,
        walkBlend = 0,
        crouchBlend = 0,
        walkScale = 0,
        jumpSequence = 0,
        -- Gameplay state is authored per fixed tick; rendering samples it between ticks.
        smooth = {
            yaw = StepValue.new(math.pi, true),
            walk = StepValue.new(0),
            crouch = StepValue.new(0),
        },
        rayFilter = function(other)
            return other ~= body and other.canCollide
        end,
    }, Player)
    local states = {}
    for _, name in ipairs({ 'idle', 'walk', 'run', 'jump', 'fall', 'crouch' }) do
        states[name] = require('scene.scripts.fsm.states.' .. name)
    end
    self.fsm = Machine.new(self, states)
    return self
end

function Player:setMove(x, z)
    self.input.x, self.input.z = x, z
end

function Player:jump()
    self.input.jump = true
end

function Player:moving()
    return self.direction[1] ~= 0 or self.direction[3] ~= 0
end

function Player:gravity(dt)
    if not self.grounded then
        self.velocity[2] = self.velocity[2] - self.settings.gravity * dt
    elseif self.velocity[2] < 0 then
        self.velocity[2] = 0
    end
end

function Player:rotateVisual()
    local direction = self.direction
    local target = self.input.shiftlock and math.pi - self.cameraYaw
        or (self:moving() and math.atan2(direction[1], -direction[3]))
    if target then
        -- The source uses a 0.2 turn blend per 60 Hz physics tick.
        self.visualYaw = Math.angle(self.visualYaw, target, 0.2)
    end
end

function Player:setWalkScale(scale)
    local facingX, facingZ = math.sin(self.visualYaw), -math.cos(self.visualYaw)
    local dot = self.direction[1] * facingX + self.direction[3] * facingZ
    self.walkScale = self:moving() and scale * (dot > -0.7 and 1 or -1) or 0
end

function Player:step(dt)
    self.body:sync()
    local p = self.body.object.position
    self.body:getVelocity(self.velocity)
    local foot = p[2] - self.settings.standingHeight / 2
    self.rayStart[1], self.rayStart[2], self.rayStart[3] = p[1], foot + self.settings.radius, p[3]
    self.rayEnd[1], self.rayEnd[2], self.rayEnd[3] = p[1], foot - 0.025, p[3]
    local hit = self.body.physics:raycast(self.rayStart, self.rayEnd, self.rayFilter, self.rayHit)
    self.grounded = self.velocity[2] <= 0.05
        and hit ~= nil
        and hit.normal[2] >= math.cos(math.rad(45))
    local yaw = self.cameraYaw
    local x, z = self.input.x, self.input.z
    local length = math.max(1, math.sqrt(x * x + z * z))
    self.direction[1] = (x * math.cos(yaw) + z * math.sin(yaw)) / length
    self.direction[3] = (z * math.cos(yaw) - x * math.sin(yaw)) / length
    self.fsm:update(dt)
    local height = Math.approach(self.height, self.targetHeight, self.settings.heightSpeed * dt)
    if height ~= self.height then
        self.height = height
        -- Godot height includes both hemispheres; engine height is the cylinder.
        -- A fully crouched 1 m capsule with radius 0.5 is exactly a sphere.
        local cylinder = height - 2 * self.settings.radius
        self.collider.shape = cylinder <= 0 and 'Sphere' or 'Capsule'
        self.collider.height = math.max(0.001, cylinder)
        -- Keep the capsule's feet fixed while its top and camera pivot lower.
        self.collider.position[2] = (height - self.settings.standingHeight) / 2
        self.body.object:update(0)
    end
    local smooth = self.smooth
    smooth.yaw:capture(self.visualYaw)
    smooth.walk:capture(self.walkBlend)
    smooth.crouch:capture(self.crouchBlend)
    self.body:setVelocity(self.velocity)
end

return Player
