-- The on-foot player: the StareShooter character controller (capsule Body3D, fixed-step state
-- machine, crouch, walk/crouch blends) plus the `drive` and `passenger` states used while riding a
-- car. The replicated model (pose, state and animation blends) is refreshed every step.
local StateMachine = require('source.engine.core.stateMachine')
local Math = require('./math')
local WalkerEntity = require('../shared.walkerEntity')
local Arena = require('../shared.arena')
local StepValue = require('source.engine.animation.stepValue')

local Walker = {}
Walker.__index = Walker

-- The StareShooter character's tuning.
Walker.SEAT_LIFT = 0.5 -- capsule centre above the seat, or above the chassis centre without a car view (m)

Walker.settings = {
    walkSpeed = 5,
    runSpeed = 8,
    jumpPower = 6,
    acceleration = 50,
    friction = 35,
    gravityMultiplier = 2.5, -- walker gravity = world gravity x this (9.81 x 2.5 = 24.5, snappy jumps)
    radius = 0.5,
    standingHeight = 2,
    crouchingHeight = 1,
    heightSpeed = 10,
    crouchSpeedFactor = 0.65,
    blendSpeed = 5,
    mass = 80,
    stickReach = 0.45, -- how far below the feet the ground still counts while walking
    stickSpeed = 12, -- fastest snap down onto the terrain (m/s)
    jumpGrace = 0.2, -- after a jump starts, the ground cannot catch the player for this long (s)
    coyoteTime = 0.12, -- grace after the ground disappears (curbs, bumps, mesh seams)
}

function Walker.new(world, model, settings)
    settings = settings or Walker.settings
    local cylinder = settings.standingHeight - 2 * settings.radius
    local body = world:create('Body3D', {
        name = 'Walker' .. tostring(model.playerId),
        position = { model.x, model.y + settings.standingHeight / 2, model.z },
        size = { settings.radius * 2, settings.standingHeight, settings.radius * 2 },
        collider = { shape = 'Capsule', radius = settings.radius, height = cylinder },
        mass = settings.mass,
        rotationFactor = { 0, 0, 0 },
        gravityScale = 0, -- gravity is integrated by the states so jumps are tuned directly
        autoSleep = false,
        friction = 0,
        restitution = 0,
        linearDamping = 0,
        angularDamping = 0,
    })
    -- The child collider is what crouching resizes.
    local collider = world:create('Collider3D', {
        name = 'Capsule',
        shape = 'Capsule',
        radius = settings.radius,
        height = cylinder,
    }, body)
    body:update(0)
    local self = setmetatable({
        model = model,
        node = body,
        collider = collider,
        body = body.body,
        settings = settings,
        height = settings.standingHeight,
        targetHeight = settings.standingHeight,
        input = {
            forward = 0,
            right = 0,
            jump = false,
            crouch = false,
            sprint = false,
            shiftlock = false,
        },
        direction = { 0, 0, 0 },
        velocity = { 0, 0, 0 },
        rayStart = {},
        rayEnd = {},
        rayHit = {},
        visualYaw = math.rad(model.heading or 0), -- heading: forward = (sin, cos)
        cameraYaw = 0,
        grounded = false,
        groundGap = 0,
        carry = { 0, 0, 0 }, -- horizontal velocity of the moving ground that is part of `velocity`
        platform = { 0, 0, 0 },
        -- Gameplay state is authored per fixed tick; rendering samples it between ticks.
        smooth = {
            yaw = StepValue.new(math.rad(model.heading or 0), true),
            walk = StepValue.new(0),
            crouch = StepValue.new(0),
        },
        jumpTimer = 0,
        airTime = 0,
        air = true,
        walkBlend = 0,
        crouchBlend = 0,
        walkScale = 0,
        jumpSequence = 0,
        seat = { 0, 0, 0 },
    }, Walker)
    self.rayFilter = function(other)
        return other ~= self.body and other.canCollide
    end
    local states = {}
    for _, name in ipairs(WalkerEntity.states) do
        states[name] = require('scene.scripts.walker.states.' .. name)
    end
    self.fsm = StateMachine.new(self, states, 'fall')
    return self
end

function Walker:moving()
    return self.direction[1] ~= 0 or self.direction[3] ~= 0
end

-- Downward acceleration (m/s^2): follows the physics world's gravity, so changing it in the
-- scene changes jump height. `settings.gravity` overrides it with an absolute value.
function Walker:gravityAcceleration()
    local settings = self.settings
    if settings.gravity then
        return settings.gravity
    end
    local physics = self.body.physics
    local _, y = physics:getGravity()
    return math.abs(y) * settings.gravityMultiplier
end

function Walker:gravity(dt)
    if self.grounded and not self.coyote then
        if self.groundGap > 0.03 then
            -- Walking down a slope or over a bump: stay glued to the terrain instead of hovering.
            self.velocity[2] = -math.min(self.groundGap / dt, self.settings.stickSpeed)
        elseif self.velocity[2] < 0 then
            self.velocity[2] = 0
        end
    else
        self.velocity[2] = self.velocity[2] - self:gravityAcceleration() * dt
    end
end

-- Turns toward the movement direction, or toward the camera while shift-locked. The 0.2 blend per
-- 60 Hz tick is the source game's.
function Walker:rotateVisual()
    local target = self.input.shiftlock and self.cameraYaw
        or (self:moving() and math.atan2(self.direction[1], self.direction[3]))
    if target then
        self.visualYaw = Math.angle(self.visualYaw, target, 0.2)
    end
end

-- Animation speed: reversed while moving against the facing (strafing backwards).
function Walker:setWalkScale(scale)
    local facingX, facingZ = math.sin(self.visualYaw), math.cos(self.visualYaw)
    local dot = self.direction[1] * facingX + self.direction[3] * facingZ
    self.walkScale = self:moving() and scale * (dot > -0.7 and 1 or -1) or 0
end

function Walker:setRiding(on)
    self.riding = on
    self.node.canCollide = not on
end

-- The seat: the car's chassis centre and its up axis, both at the pose the car is drawn at (the
-- session passes the body's render pose every frame while riding). The capsule centre sits
-- SEAT_LIFT above the chassis centre along that axis, not along world Y, so it stays on a
-- tilted car.
function Walker:setSeat(x, y, z, upX, upY, upZ)
    local seat = self.seat
    seat[1], seat[2], seat[3] = x, y, z
    seat[4], seat[5], seat[6] = upX or 0, upY or 1, upZ or 0
end

function Walker:rideAlong()
    local seat = self.seat
    local lift = Walker.SEAT_LIFT
    self.node.position = {
        seat[1] + (seat[4] or 0) * lift,
        seat[2] + (seat[5] or 1) * lift,
        seat[3] + (seat[6] or 0) * lift,
    }
    self.velocity[1], self.velocity[2], self.velocity[3] = 0, 0, 0
    self.grounded, self.air = true, false
    self.walkBlend, self.crouchBlend, self.walkScale = 0, 0, 0
end

-- Moves the capsule to the seat right now. The body is teleported, which also resets its render
-- pose, so the capsule is drawn exactly at the seat this frame instead of trailing a step behind.
function Walker:placeAtSeat()
    self:rideAlong()
    self.body:sync()
end

-- Puts the walker on foot at feet position (x, y, z).
function Walker:place(x, y, z)
    -- Never inside the terrain: the ground mesh only collides from above.
    y = math.max(y, Arena.ground(x, z) + 0.1)
    self.node.position = { x, y + self.settings.standingHeight / 2, z }
    self.velocity[1], self.velocity[2], self.velocity[3] = 0, 0, 0
    self.body:sync()
    self.smooth.yaw:reset(self.visualYaw)
    self.fsm:change('fall')
end

function Walker:enterCar(seat)
    self.fsm:change(seat == 1 and 'drive' or 'passenger')
end

function Walker:isRiding()
    return self.riding == true
end

function Walker:step(dt)
    self.body:sync()
    local settings = self.settings
    local p = self.node.position
    self.body:getVelocity(self.velocity)
    if not self.riding then
        local foot = p[2] - settings.standingHeight / 2
        -- Fell through the map (spawned inside the terrain, or a huge time step): put the player
        -- back on the surface instead of falling forever.
        local half = Arena.size / 2 + 3 -- beyond the boundary walls: escaped the arena
        local gx = math.max(-half, math.min(half, p[1]))
        local gz = math.max(-half, math.min(half, p[3]))
        if foot < Arena.ground(gx, gz) - 2 or p[1] ~= gx or p[3] ~= gz then
            self:place(gx, math.max(Arena.ground(gx, gz), 0) + 1.5, gz)
            p = self.node.position
            foot = p[2] - settings.standingHeight / 2
        end
        -- Uneven terrain: while walking on the ground the ray reaches further down, so a small
        -- drop (slope, bump, seam between mesh triangles) never reads as a fall.
        local reach = (self.grounded and not self.coyote) and settings.stickReach or 0.05
        self.rayStart[1], self.rayStart[2], self.rayStart[3] = p[1], foot + settings.radius, p[3]
        self.rayEnd[1], self.rayEnd[2], self.rayEnd[3] = p[1], foot - reach, p[3]
        local hit =
            self.body.physics:raycast(self.rayStart, self.rayEnd, self.rayFilter, self.rayHit)
        -- Climbing a slope the physics lifts the body (positive vertical speed), so rising is no
        -- proof of leaving the ground: only the moments right after a jump are excluded.
        self.jumpTimer = math.max(0, self.jumpTimer - dt)
        local onGround = self.jumpTimer == 0
            and hit ~= nil
            and hit.normal[2] >= math.cos(math.rad(50))
        if onGround then
            self.airTime = 0
            self.coyote = false
            self.groundGap = math.max(0, foot - hit.position[2])
        else
            self.airTime = self.airTime + dt
            -- A short grace period keeps the walking state through one-frame ground misses.
            self.coyote = self.grounded and self.jumpTimer == 0 and self.airTime < settings.coyoteTime
        end
        self.grounded = onGround or self.coyote
        -- Standing on something that moves (a car roof): the character rides along. `velocity`
        -- is kept relative to that ground while the states run, then the ground's is added back.
        local platform, carry = self.platform, self.carry
        platform[1], platform[2], platform[3] = 0, 0, 0
        if onGround and hit.body and hit.body ~= self.body and hit.body.type ~= 'Static' then
            hit.body:getPointVelocity(hit.position, platform)
        end
        if self.grounded then
            self.velocity[1], self.velocity[3] = self.velocity[1] - carry[1], self.velocity[3] - carry[3]
        end
        carry[1], carry[3] = 0, 0
        -- Forward is the camera's facing, right is its screen-right (the engine is left-handed).
        local sin, cos = math.sin(self.cameraYaw), math.cos(self.cameraYaw)
        local f, r = self.input.forward, self.input.right
        local x, z = sin * f + cos * r, cos * f - sin * r
        local length = math.max(1, math.sqrt(x * x + z * z))
        self.direction[1], self.direction[3] = x / length, z / length
        if f == 0 and r == 0 then
            self.direction[1], self.direction[3] = 0, 0
        end
    else
        self.direction[1], self.direction[3] = 0, 0
    end
    local wasGrounded = self.grounded
    self.fsm:update(dt)
    if wasGrounded and not self.riding then
        self.velocity[1] = self.velocity[1] + self.platform[1]
        self.velocity[3] = self.velocity[3] + self.platform[3]
        self.carry[1], self.carry[3] = self.platform[1], self.platform[3]
    end
    local height = Math.approach(self.height, self.targetHeight, settings.heightSpeed * dt)
    if height ~= self.height then
        self.height = height
        -- The engine's capsule height is the cylinder; a fully crouched 1 m capsule of radius
        -- 0.5 is exactly a sphere.
        local cylinder = height - 2 * settings.radius
        self.collider.shape = cylinder <= 0 and 'Sphere' or 'Capsule'
        self.collider.height = math.max(0.001, cylinder)
        -- Keep the feet fixed while the top lowers.
        self.collider.position[2] = (height - settings.standingHeight) / 2
        self.node:update(0)
    end
    self.body:setVelocity(self.velocity)
    local model = self.model
    p = self.node.position
    model.x, model.y, model.z = p[1], p[2] - settings.standingHeight / 2, p[3]
    model.heading = math.deg(self.visualYaw) % 360
    local smooth = self.smooth
    smooth.yaw:capture(self.visualYaw)
    smooth.walk:capture(self.walkBlend)
    smooth.crouch:capture(self.crouchBlend)
    model.state = WalkerEntity.stateIndex[self.fsm.name]
    model.speed = math.sqrt(self.velocity[1] ^ 2 + self.velocity[3] ^ 2)
    model.walkBlend, model.crouchBlend = self.walkBlend, self.crouchBlend
    model.walkScale, model.air, model.jumpSequence = self.walkScale, self.air, self.jumpSequence % 256
end

-- The pose that is drawn: the body's interpolated render matrix and the sampled step values.
-- Returns feet x, y, z, heading (degrees), walk and crouch blends.
function Walker:renderPose()
    local physics = self.body.physics
    local m = self.node:getRenderWorldMatrix()
    local smooth = self.smooth
    return m[4],
        m[8] - self.settings.standingHeight / 2,
        m[12],
        math.deg(smooth.yaw:sampleFor(physics)) % 360,
        smooth.walk:sampleFor(physics),
        smooth.crouch:sampleFor(physics)
end

function Walker:destroy()
    self.node:destroy()
end

return Walker
