local Character = require('source.engine.physics.3d.character')
local Mesh = require('source.engine.composition.mesh')

-- A walker with a real physical body (a capsule) that a NavAgent3D steers. The agent plans routes
-- and hands over at the start of every NavLink3D; this module performs the actions with physics:
--   * jump: it decides when to go (it waits while another walker stands on the landing spot),
--     computes the launch velocity of a ballistic arc that clears the obstacle and lands on the
--     link's far end, throws the body with `Character:launch` and finishes the link when the body
--     has landed near the target (or cancels it, and the agent plans again, when it missed);
--   * climb: gravity is switched off while the body is driven up (or down) the ladder.
local Walker = {}
Walker.__index = Walker

Walker.HEIGHT, Walker.RADIUS = 1.8, 0.5

local CLEARANCE = 1 -- how far above the highest obstacle the feet pass
local LANDING_CLEARANCE = 1.2
local MAX_WAIT = 1
local CLIMB_SPEED = 1.6

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
    agentOptions.autoMove = false -- the body moves the agent, never the other way round
    local agent = world:create('NavAgent3D', agentOptions, body)
    local self = setmetatable({
        world = world,
        body = body,
        agent = agent,
        speed = options.speed or 5,
        others = others,
        character = Character.new(body.body, nil, {
            height = height,
            radius = radius,
            speed = options.speed or 5,
            acceleration = 60,
            airAcceleration = 6,
            groundTolerance = 0.25,
            jumpSpeed = 8,
        }),
    }, Walker)
    agent:connect('LinkReached', function(link)
        self.job = { link = link, waited = 0 }
    end)
    return self
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

-- Launch velocity of a ballistic arc from `from` to `to` (feet positions) whose highest point is
-- `peak`: up to the apex, then down onto the target.
local function arc(from, to, peak, gravity)
    local up = math.sqrt(2 * (peak - from[2]) / gravity)
    local down = math.sqrt(2 * (peak - to[2]) / gravity)
    local time = up + down
    return (to[1] - from[1]) / time, up * gravity, (to[3] - from[3]) / time
end

-- Frame level: the agent has stopped at a link; decide when to start the action.
function Walker:update(dt)
    local job = self.job
    if not job or job.started then
        return
    end
    local target = self.agent:getLinkEnd()
    if not target then
        self.agent:cancelLink()
        self.job = nil
        return
    end
    local action = job.link.action
    if action == 'jump' then
        if job.waited < MAX_WAIT and landingBusy(self, target) then
            job.waited = job.waited + dt
            return
        end
        local from = self.agent:getWorldPosition()
        local data = job.link.data or {}
        local peak = math.max(from[2], target[2], data.peak or -math.huge) + CLEARANCE
        local gravity = -select(2, self.world.physics:getGravity())
        self.character:launch(arc(from, target, peak, gravity))
        job.started, job.target = true, target
        job.from = from
    elseif action == 'climb' then
        job.started, job.target, job.phase = true, target, 0
        self.body.gravityScale = 0
    else
        self.agent:finishLink()
        self.job = nil
    end
end

-- Fixed step (before the physics step): steer the body, advance the running action.
function Walker:step()
    local job, agent, character = self.job, self.agent, self.character
    local crowd = agent._agent
    if job and job.started and job.link.action == 'climb' then
        self:climb(job)
        return
    end
    if crowd and not agent:isActing() then
        character:setMove(crowd.vx / self.speed, crowd.vz / self.speed)
    else
        character:setMove(0, 0)
    end
    character:step()
    if job and job.started then
        if character.airborne then
            job.flying = true
        elseif job.flying then
            -- Landed: finish when close to the planned landing, otherwise plan again.
            local feet, target = agent:getWorldPosition(), job.target
            local flat = math.sqrt((feet[1] - target[1]) ^ 2 + (feet[3] - target[3]) ^ 2)
            self.job = nil
            self.landed = (self.landed or 0) + 1
            if flat < 1.5 and math.abs(feet[2] - target[2]) < 0.8 then
                agent:finishLink()
            else
                self.missed = (self.missed or 0) + 1
                agent:cancelLink()
            end
        end
    end
end

-- The ladder: straight up (or over, then down) with gravity off.
function Walker:climb(job)
    local feet, target = self.agent:getWorldPosition(), job.target
    local vx, vy, vz = 0, 0, 0
    local dx, dy, dz = target[1] - feet[1], target[2] - feet[2], target[3] - feet[3]
    local flat = math.sqrt(dx * dx + dz * dz)
    if job.phase == 0 then
        job.up = target[2] > feet[2]
        job.phase = job.up and 1 or 2
    end
    if job.phase == 1 then -- going up: vertical first
        vy = CLIMB_SPEED
        if dy < 0.1 then
            job.phase = 3
        end
    elseif job.phase == 2 then -- going down: over the edge first
        if flat > 0.2 then
            vx, vz = dx / flat * CLIMB_SPEED, dz / flat * CLIMB_SPEED
        else
            job.phase = 4
        end
    elseif job.phase == 3 then
        if flat > 0.2 then
            vx, vz = dx / flat * CLIMB_SPEED, dz / flat * CLIMB_SPEED
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
        self.job = nil
        self.agent:finishLink()
        return
    end
    self.body.body:setVelocity({ vx, vy, vz })
end

return Walker
