local Character = require('source.engine.physics.3d.character')
local Mesh = require('source.engine.composition.mesh')

-- A walker with a real physical body (a capsule) driven like a player. A NavAgent3D (Godot style)
-- only says where to go and which action is next; this script presses the keys:
--   * walking: the agent's wanted velocity becomes the character's move input;
--   * jump: it runs at the link start and, close enough, presses jump, so the body leaves the
--     ground with the character's fixed jump speed and keeps its running speed. In the air it
--     steers toward the landing spot like a player would (less input when it is going to land
--     early). It waits while another walker stands on the landing spot. A jump that falls short
--     is simply tried again from the ground; one that strays far makes the agent plan anew;
--   * climb: gravity is switched off while the body is driven up (or down) the ladder.
local Walker = {}
Walker.__index = Walker

Walker.HEIGHT, Walker.RADIUS = 1.8, 0.5

local LANDING_CLEARANCE = 1.2
local MAX_WAIT = 1
local CLIMB_SPEED = 1.6
local TAKEOFF = 0.45 -- how close to the link start a player presses jump
local JUMP_SPEED = 10

-- options: name, position (feet), color, speed, plus any NavAgent3D property (navMap,
-- areaCosts, actionCosts, ...).
function Walker.new(world, options, others)
    local height, radius = Walker.HEIGHT, Walker.RADIUS
    local feet = options.position
    local body = world:create('Body3D', {
        name = options.name,
        position = { feet[1], feet[2] + height / 2 + 0.05, feet[3] },
        size = { radius * 2, height, radius * 2 },
        collider = { shape = 'Capsule', height = height - 2 * radius, radius = radius },
        density = 1,
        friction = 0.2,
        rotationFactor = { 0, 0, 0 },
        autoSleep = false,
        navWalkable = false,
    })
    Mesh.create(world, {
        name = options.name .. 'Visual',
        kind = 'capsule',
        size = { radius * 2, height, radius * 2 },
        color = options.color,
    }, body)
    local agentOptions = {}
    for key, value in pairs(options) do
        agentOptions[key] = value
    end
    agentOptions.position, agentOptions.color = { 0, -height / 2, 0 }, nil
    agentOptions.height = height
    local agent = world:create('NavAgent3D', agentOptions, body)
    return setmetatable({
        world = world,
        body = body,
        agent = agent,
        speed = options.speed or 5,
        others = others,
        jumps = 0,
        character = Character.new(body.body, nil, {
            height = height,
            radius = radius,
            speed = options.speed or 5,
            acceleration = 60,
            airAcceleration = 30,
            groundTolerance = 0.25,
            jumpSpeed = JUMP_SPEED,
        }),
    }, Walker)
end

local function flat(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
end

local function landingBusy(self, target)
    for _, other in ipairs(self.others) do
        if other ~= self then
            local p = other.agent:getWorldPosition()
            if math.abs(p[1] - target[1]) < LANDING_CLEARANCE and math.abs(p[3] - target[3]) < LANDING_CLEARANCE then
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

-- Fixed step (before the physics step): turn the agent's advice into key presses.
function Walker:step()
    local agent, character = self.agent, self.character
    local vx, _, vz = agent:getVelocity()
    local action = agent:getNextAction()
    local feet = agent:getWorldPosition()
    local dt = self.body.body.physics.fixedDelta
    if self.climbing then
        self:climb(feet)
        return
    end
    local moveX, moveZ = vx / self.speed, vz / self.speed
    local flying = self.flying
    if flying then
        -- The ground probe still sees the floor in the first moments of a jump, so the flight
        -- is tracked here: it ends when the body is down again after rising.
        flying.time = flying.time + dt
        local vy = self.body.body:getVelocity({})[2]
        if character.grounded and flying.time > 0.2 and vy <= 0.5 then
            self.flying = nil
        end
    end
    if action == 'jump' and self.flying then
        -- In the air: steer toward the landing, gently when it is not far any more.
        local landing = agent:getActionTarget() or self.flying.landing
        local distance = flat(feet, landing)
        local vy = self.body.body:getVelocity({})[2]
        local left = fallTime(vy, landing[2] - feet[2], -select(2, self.world.physics:getGravity()))
        local push = math.min(1, distance / math.max(0.05, self.speed * left))
        local dx, dz = landing[1] - feet[1], landing[3] - feet[3]
        local length = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
        character:setMove(dx / length * push, dz / length * push)
    elseif action == 'jump' then
        local start, landing = agent:getNextPathPosition(), agent:getActionTarget()
        local blocked = landing and (self.waited or 0) < MAX_WAIT and landingBusy(self, landing)
        self.waited = blocked and (self.waited or 0) + dt or 0
        if blocked then
            moveX, moveZ = 0, 0
        elseif landing and character.grounded and flat(feet, start) <= TAKEOFF and flat(feet, landing) > 0.6 then
            -- The player presses jump on the run, facing the landing.
            character:jump()
            self.jumps = self.jumps + 1
            self.flying = { time = 0, landing = landing }
        end
        character:setMove(moveX, moveZ)
    elseif action == 'climb' then
        local start = agent:getNextPathPosition()
        if flat(feet, start) < 0.5 and character.grounded then
            self.climbing = { target = agent:getActionTarget(), phase = 0 }
            self.body.gravityScale = 0
        else
            character:setMove(moveX, moveZ)
        end
    else
        character:setMove(moveX, moveZ)
    end
    character:step()
end

-- The ladder: straight up (or over, then down) with gravity off.
function Walker:climb(feet)
    local job = self.climbing
    local target = job.target
    if not target then
        self.climbing = nil
        self.body.gravityScale = 1
        return
    end
    local vx, vy, vz = 0, 0, 0
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
    if job.phase == 5 then
        self.body.gravityScale = 1
        self.climbing = nil
        return
    end
    self.body.body:setVelocity({ vx, vy, vz })
end

return Walker
