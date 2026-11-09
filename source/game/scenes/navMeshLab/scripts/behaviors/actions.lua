-- Performs the actions of NavLink3D links for the agents of this scene. The pathfinding plugin
-- stops an agent at the start of a link and emits 'LinkReached'; everything after that is here:
-- when to start (a jump waits while another walker stands on the landing spot), how it looks (an
-- arc for 'jump', up-then-over for 'climb') and when it is over (`agent:finishLink()`).
local Actions = {}
Actions.__index = Actions

local JUMP_SPEED = 1.3 -- times the agent's walking speed
local LANDING_CLEARANCE = 1.2
local MAX_WAIT = 1

function Actions.new(agents)
    return setmetatable({ agents = agents, running = {} }, Actions)
end

function Actions:attach(agent)
    agent:connect('LinkReached', function(link)
        self.running[agent] = { link = link, waited = 0, t = 0 }
    end)
end

local function landingBusy(self, agent, target)
    for _, other in ipairs(self.agents) do
        if other ~= agent then
            local p = other.position
            if math.abs(p[1] - target[1]) < LANDING_CLEARANCE and math.abs(p[3] - target[3]) < LANDING_CLEARANCE then
                return true
            end
        end
    end
    return false
end

local function begin(self, agent, run)
    local target = agent:getLinkEnd()
    if not target then
        agent:cancelLink()
        self.running[agent] = nil
        return
    end
    local here = agent.position
    local flat = math.sqrt((target[1] - here[1]) ^ 2 + (target[3] - here[3]) ^ 2)
    run.from = { here[1], here[2], here[3] }
    run.to = target
    if run.link.action == 'jump' then
        run.duration = run.link.duration > 0 and run.link.duration
            or math.max(0.35, flat / (agent.speed * JUMP_SPEED))
        run.arc = math.max(run.link.arcHeight or 1, 0.4)
    elseif run.link.action == 'climb' then
        run.duration = math.max(0.6, math.abs(target[2] - here[2]) / 1.5 + flat / 3)
        run.arc = 0
    else
        run.duration, run.arc = 0.05, 0
    end
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

function Actions:update(dt)
    for agent, run in pairs(self.running) do
        if agent.destroyed then
            self.running[agent] = nil
        elseif not run.from then
            -- Deciding when to go: wait for the landing spot to clear, but not for ever.
            local target = agent:getLinkEnd()
            if run.link.action ~= 'jump' or run.waited >= MAX_WAIT or not target or not landingBusy(self, agent, target) then
                begin(self, agent, run)
            else
                run.waited = run.waited + dt
            end
        else
            run.t = math.min(1, run.t + dt / run.duration)
            local t, a, b = run.t, run.from, run.to
            local x, y, z
            if run.link.action == 'climb' then
                -- Up first and over the edge when climbing up; over first and down when going down.
                local up = b[2] > a[2]
                local vertical = up and math.min(1, t / 0.7) or math.max(0, (t - 0.3) / 0.7)
                local flat = up and math.max(0, (t - 0.7) / 0.3) or math.min(1, t / 0.3)
                x, z = lerp(a[1], b[1], flat), lerp(a[3], b[3], flat)
                y = lerp(a[2], b[2], vertical)
            else
                x, y, z = lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t)
                y = y + 4 * run.arc * t * (1 - t)
            end
            agent:placeAt(x, y, z)
            if t >= 1 then
                self.running[agent] = nil
                agent:finishLink()
            end
        end
    end
end

return Actions
