local Animation = require('source.game.characters.animation')
local Controller = require('source.game.characters.controller')
local Math = require('source.game.characters.math')
local Models = require('source.engine.import.models')

-- A walker with a real physical body driven like a player: the StareShooter character model and
-- controller (`source/game/characters`: capsule movement, state machine, animation blending). A
-- NavAgent3D (Godot style) only says where to go and which action is next; this script presses
-- the keys:
--   * walking: the agent's wanted velocity becomes the controller's move input;
--   * jump: it runs at the link start and, close enough, presses jump, so the body leaves the
--     ground with the controller's jump power and its running speed, and steers in the air toward
--     the landing like a player would (less input when it is going to land early). It waits while
--     another walker stands on the landing spot. A jump that falls short is simply tried again
--     from the ground; one that strays far makes the agent plan anew;
--   * climb: gravity is off while the body is driven up (or down) the ladder, with the walk
--     animation playing and the model turned toward the ladder.
local Walker = {}
Walker.__index = Walker

Walker.HEIGHT, Walker.RADIUS = 2, 0.5
Walker.MODEL = 'assets/models/characters/player.glb'

local LANDING_CLEARANCE = 1.2
local MAX_WAIT = 1
local CLIMB_SPEED = 1.6
local TAKEOFF = 0.45 -- how close to the link start a player presses jump
local JUMP_POWER = 10
local TINT = 0.55 -- how strongly the walker colour shows on the model

-- The StareShooter tuning with this walker's speeds.
local function settingsFor(speed)
    return {
        walkSpeed = speed,
        runSpeed = speed * 1.6,
        jumpPower = JUMP_POWER,
        acceleration = 50,
        friction = 35,
        gravity = 24.5,
        radius = Walker.RADIUS,
        standingHeight = Walker.HEIGHT,
        crouchingHeight = 1,
        heightSpeed = 10,
        crouchSpeedFactor = 0.65,
        blendSpeed = 5,
    }
end

-- Mixes a colour into every mesh of the model so walkers can be told apart.
local function tint(root, color)
    for _, node in ipairs(root:getDescendants()) do
        if node:isA('Mesh3D') and node.color then
            local base = node.color
            node.color = {
                base[1] * (1 - TINT) + color[1] * TINT,
                base[2] * (1 - TINT) + color[2] * TINT,
                base[3] * (1 - TINT) + color[3] * TINT,
                base[4] or 1,
            }
        end
    end
end

-- options: name, position (feet), color, speed, plus any NavAgent3D property (navMap,
-- areaCosts, actionCosts, ...).
function Walker.new(scene, options, others)
    local world = scene.world
    local height, radius = Walker.HEIGHT, Walker.RADIUS
    local feet = options.position
    local speed = options.speed or 5
    local body = world:create('Body3D', {
        name = options.name,
        position = { feet[1], feet[2] + height / 2 + 0.05, feet[3] },
        size = { radius * 2, height, radius * 2 },
        collider = { shape = 'Capsule', radius = radius, height = height - 2 * radius },
        rotationFactor = { 0, 0, 0 },
        gravityScale = 0, -- the controller applies gravity itself, like StareShooter
        autoSleep = false,
        friction = 0,
        restitution = 0,
        linearDamping = 0,
        angularDamping = 0,
        navWalkable = false,
    })
    body:update(0)
    local asset = Models.load(Walker.MODEL, scene.resources)
    Models.instantiate(world, asset, {
        name = options.name .. 'Visual',
        position = { 0, -height / 2, 0 },
        rotation = { 0, 180, 0 },
        scale = { 0.65, 0.65, 0.65 },
        parent = body,
    })
    if options.color then
        tint(asset.root, options.color)
    end
    local agentOptions = {}
    for key, value in pairs(options) do
        agentOptions[key] = value
    end
    agentOptions.position, agentOptions.color = nil, nil
    agentOptions.height, agentOptions.feetOffset = height, height / 2
    local agent = world:create('NavAgent3D', agentOptions, body)
    -- Crouching never happens here, so the controller's collider handle is a stub.
    local controller =
        Controller.new(body.physics, { position = { 0, 0, 0 } }, nil, settingsFor(speed))
    controller.model = asset
    return setmetatable({
        world = world,
        body = body,
        agent = agent,
        speed = speed,
        others = others,
        jumps = 0,
        controller = controller,
        animation = Animation.new(controller),
    }, Walker)
end

local function flat(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
end

local function landingBusy(self, target)
    for _, other in ipairs(self.others) do
        if other ~= self then
            local p = other.agent:getWorldPosition()
            if
                math.abs(p[1] - target[1]) < LANDING_CLEARANCE
                and math.abs(p[3] - target[3]) < LANDING_CLEARANCE
            then
                return true
            end
        end
    end
    return false
end

-- Time until the feet (rising at `vy`) are down at height `dy` relative to now.
local function fallTime(vy, dy, gravity)
    local disc = vy * vy - 2 * gravity * dy
    if disc < 0 then
        return 0.3
    end
    return (vy + math.sqrt(disc)) / gravity
end

-- Per frame: blend the animation tracks from the controller state.
function Walker:update(dt)
    self.animation:update(dt)
end

-- Fixed step (before the physics step): turn the agent's advice into key presses.
function Walker:step(dt)
    local agent, controller = self.agent, self.controller
    local vx, _, vz = agent:getVelocity()
    local action = agent:getNextAction()
    local feet = agent:getWorldPosition()
    controller.input.jump = false
    if self.climbing then
        self:climb(feet)
        return
    end
    local moveX, moveZ = vx / self.speed, vz / self.speed
    if action == 'jump' and controller.air then
        -- In the air: steer toward the landing, gently when it is not far any more.
        local landing = agent:getActionTarget()
        if landing then
            local distance = flat(feet, landing)
            local left =
                fallTime(controller.velocity[2], landing[2] - feet[2], controller.settings.gravity)
            local push = math.min(1, distance / math.max(0.05, self.speed * left))
            local dx, dz = landing[1] - feet[1], landing[3] - feet[3]
            local length = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
            moveX, moveZ = dx / length * push, dz / length * push
        end
    elseif action == 'jump' then
        local start, landing = agent:getNextPathPosition(), agent:getActionTarget()
        local blocked = landing and (self.waited or 0) < MAX_WAIT and landingBusy(self, landing)
        self.waited = blocked and (self.waited or 0) + dt or 0
        if blocked then
            moveX, moveZ = 0, 0
        elseif
            landing
            and controller.grounded
            and flat(feet, start) <= TAKEOFF
            and flat(feet, landing) > 0.6
        then
            -- The player presses jump on the run, facing the landing.
            controller.input.jump = true
            self.jumps = self.jumps + 1
        end
    elseif action == 'climb' then
        local start = agent:getNextPathPosition()
        if flat(feet, start) < 0.5 and controller.grounded then
            self.climbing = { target = agent:getActionTarget(), phase = 0 }
            self.body.physics:setVelocity({ 0, 0, 0 })
        end
    end
    controller:setMove(moveX, moveZ)
    controller:step(dt)
end

-- The ladder: straight up (or over, then down) without gravity, walking in place.
function Walker:climb(feet)
    local job, controller = self.climbing, self.controller
    local target = job.target
    local vx, vy, vz = 0, 0, 0
    if not target then
        self.climbing = nil
        return
    end
    local dx, dy, dz = target[1] - feet[1], target[2] - feet[2], target[3] - feet[3]
    local length = math.sqrt(dx * dx + dz * dz)
    if job.phase == 0 then
        job.phase = target[2] > feet[2] and 1 or 2
    end
    if job.phase == 1 then -- going up: vertical first
        vy = CLIMB_SPEED
        if dy < 0.1 then
            job.phase = 3
        end
    elseif job.phase == 2 then -- going down: over the edge first
        if length > 0.2 then
            vx, vz = dx / length * CLIMB_SPEED, dz / length * CLIMB_SPEED
        else
            job.phase = 4
        end
    elseif job.phase == 3 then
        if length > 0.2 then
            vx, vz = dx / length * CLIMB_SPEED, dz / length * CLIMB_SPEED
        else
            job.phase = 5
        end
    elseif job.phase == 4 then
        vy = -CLIMB_SPEED
        if dy > -0.1 then
            job.phase = 5
        end
    end
    local velocity = controller.velocity
    if job.phase == 5 then
        self.climbing = nil
        velocity[1], velocity[2], velocity[3] = 0, 0, 0
        return
    end
    -- Face the ladder and play the walk cycle while climbing.
    if math.abs(dx) + math.abs(dz) > 0.2 then
        controller.visualYaw = Math.angle(controller.visualYaw, math.atan2(dx, -dz), 0.2)
    end
    controller.walkBlend, controller.crouchBlend, controller.air = 1, 0, false
    controller.walkScale = 1.2
    controller.smooth.yaw:capture(controller.visualYaw)
    controller.smooth.walk:capture(1)
    controller.smooth.crouch:capture(0)
    velocity[1], velocity[2], velocity[3] = vx, vy, vz
    self.body.physics:setVelocity({ vx, vy, vz })
end

return Walker
