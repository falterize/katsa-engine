-- Crowd: agents that follow mesh paths and steer around each other.
--
--   local crowd = NavMesh.Crowd.new(mesh)
--   local agent = crowd:add({ x = 0, y = 0, z = 0, radius = 0.5, maxSpeed = 4 })
--   crowd:setTarget(agent, 20, 0, 12)
--   crowd:update(dt)                     -- then read agent.x, agent.y, agent.z, agent.vx, agent.vz
--
-- Each update an agent walks toward the next corner of its path, then picks the velocity with the
-- lowest penalty among a small sample (close to the wanted velocity and the current one, and far
-- from collisions predicted within `horizon` seconds), accelerates toward it and moves; the move
-- is clamped to the mesh. Paths are found again when the mesh changed (an obstacle moved) or the
-- target moved, a few agents per update (the longest-waiting first) so a change never costs one
-- big spike. An agent keeps following its old path until the new one is ready.
--
-- Costs belong to the agent: `agent.areaCosts` ({ water = 50 }) and `agent.actionCosts`
-- ({ jump = 3, climb = false }) weigh routes for that agent only; unset values use the defaults.
--
-- Action links (jump, climb, door ...) are not performed here. When an agent reaches the start of
-- one it stops, `agent.link` is set, `agent.state` stays 'moving' and `agent.acting` is true; the
-- game performs the action however it likes (moving the agent with `place`) and then calls
-- `finishLink` (the agent continues from the far end) or `cancelLink` (the route is renewed).
local Crowd = {}
Crowd.__index = Crowd

local HORIZON = 1.5
local SAMPLES = 8
local REPATHS_PER_UPDATE = 4
local RETRY_SECONDS = 0.5

function Crowd.new(mesh, options)
    options = options or {}
    return setmetatable({
        mesh = mesh,
        agents = {},
        horizon = options.horizon or HORIZON,
        repathsPerUpdate = options.repathsPerUpdate or REPATHS_PER_UPDATE,
        grid = {},
    }, Crowd)
end

-- options: x, y, z, radius (0.5), maxSpeed (4), acceleration (16), stopDistance (0.3),
-- avoidance (true).
function Crowd:add(options)
    local agent = {
        x = options.x or 0,
        y = options.y or 0,
        z = options.z or 0,
        vx = 0,
        vz = 0,
        radius = options.radius or 0.5,
        maxSpeed = options.maxSpeed or 4,
        acceleration = options.acceleration or 16,
        stopDistance = options.stopDistance or 0.3,
        avoidance = options.avoidance ~= false,
        state = 'idle',
        areaCosts = options.areaCosts,
        actionCosts = options.actionCosts,
        acting = false,
        retry = 0,
        waited = 0,
        fresh = true,
    }
    self.agents[#self.agents + 1] = agent
    return agent
end

function Crowd:remove(agent)
    for i, other in ipairs(self.agents) do
        if other == agent then
            table.remove(self.agents, i)
            return true
        end
    end
    return false
end

function Crowd:setTarget(agent, x, y, z)
    agent.target = { x, y, z }
    agent.state, agent.retry, agent.fresh = 'moving', 0, false
    agent.waited = agent.waited or 0
end

function Crowd:clearTarget(agent)
    agent.target, agent.path, agent.state = nil, nil, 'idle'
    agent.acting, agent.link = false, nil
end

-- Moves an agent that is performing an action (a jump arc) to a world position.
function Crowd:place(agent, x, y, z)
    agent.x, agent.y, agent.z = x, y, z
end

-- The action is done: the agent stands at the far end of its link and walks on.
function Crowd:finishLink(agent)
    local link = agent.link
    if not link then
        return false
    end
    local path = agent.path
    local index = agent.linkIndex
    if path and index and path.points[index + 1] then
        local point = path.points[index + 1]
        agent.x, agent.y, agent.z = point[1], point[2], point[3]
        agent.level = path.levels[index + 1]
        path.index = index + 2
    end
    agent.vx, agent.vz = 0, 0
    agent.acting, agent.link, agent.linkIndex = false, nil, nil
    return true
end

-- The action failed or was abandoned: the agent stays where it is and finds a new route.
function Crowd:cancelLink(agent)
    agent.acting, agent.link, agent.linkIndex = false, nil, nil
    agent.path, agent.fresh = nil, false
    agent.retry = 0
end

-- Next corner of the route: corners within reach are passed, except the start of an action link,
-- which is returned until the agent has really arrived there (isStart is true then).
local function nextCorner(path, agent, reach)
    while path.index <= #path.points do
        local point = path.points[path.index]
        local dx, dz = point[1] - agent.x, point[3] - agent.z
        local near = math.sqrt(dx * dx + dz * dz) <= reach
        if path.roles and path.roles[path.index] == 'start' then
            return point, true, near
        end
        if not near then
            return point, false, false
        end
        path.index = path.index + 1
    end
end

-- Earliest time within `horizon` at which an agent moving with (vx, vz) touches neighbour b.
local function collisionTime(a, vx, vz, b, horizon)
    local px, pz = b.x - a.x, b.z - a.z
    local wx, wz = vx - b.vx, vz - b.vz
    local reach = a.radius + b.radius
    local c = px * px + pz * pz - reach * reach
    local closing = px * wx + pz * wz
    if c <= 0 then
        return closing > 0 and 0 or horizon
    end
    local qa = wx * wx + wz * wz
    if qa < 1e-9 or closing <= 0 then
        return horizon
    end
    local disc = closing * closing - qa * c
    if disc < 0 then
        return horizon
    end
    local t = (closing - math.sqrt(disc)) / qa
    return t < 0 and horizon or math.min(t, horizon)
end

local function neighbours(self, agent, range, out)
    for i = #out, 1, -1 do
        out[i] = nil
    end
    local size = self.cellSize
    local cx, cz = math.floor(agent.x / size), math.floor(agent.z / size)
    for dz = -1, 1 do
        for dx = -1, 1 do
            local list = self.grid[(cz + dz) * 100003 + (cx + dx)]
            if list then
                for _, other in ipairs(list) do
                    if other ~= agent then
                        local ddx, ddz = other.x - agent.x, other.z - agent.z
                        if ddx * ddx + ddz * ddz <= range * range then
                            out[#out + 1] = other
                        end
                    end
                end
            end
        end
    end
    return out
end

local function bin(self)
    local widest = 1
    for _, agent in ipairs(self.agents) do
        widest = math.max(widest, agent.maxSpeed * self.horizon + agent.radius * 2)
    end
    self.cellSize = widest
    self.grid = {}
    for _, agent in ipairs(self.agents) do
        local key = math.floor(agent.z / widest) * 100003 + math.floor(agent.x / widest)
        local list = self.grid[key]
        if not list then
            list = {}
            self.grid[key] = list
        end
        list[#list + 1] = agent
    end
    return widest
end

-- Velocity with the lowest penalty among the wanted one and two rings around the origin.
local function steer(self, agent, wantX, wantZ, near)
    local best, bestX, bestZ = math.huge, wantX, wantZ
    local speed = agent.maxSpeed
    local horizon = self.horizon
    local function consider(vx, vz)
        local soonest = horizon
        for _, other in ipairs(near) do
            soonest = math.min(soonest, collisionTime(agent, vx, vz, other, horizon))
        end
        local penalty = 2 * math.sqrt((vx - wantX) ^ 2 + (vz - wantZ) ^ 2)
            + 0.75 * math.sqrt((vx - agent.vx) ^ 2 + (vz - agent.vz) ^ 2)
            + 4 * speed * (1 - soonest / horizon)
        if penalty < best then
            best, bestX, bestZ = penalty, vx, vz
        end
    end
    consider(wantX, wantZ)
    for ring = 1, 2 do
        for i = 0, SAMPLES - 1 do
            local angle = i * 2 * math.pi / SAMPLES
            consider(math.cos(angle) * speed * ring / 2, math.sin(angle) * speed * ring / 2)
        end
    end
    return bestX, bestZ
end

local function repath(self, agent)
    local path, reason = self.mesh:findPath({ agent.x, agent.y, agent.z }, agent.target, {
        areaCosts = agent.areaCosts,
        actionCosts = agent.actionCosts,
    })
    agent.failure = reason
    agent.waited, agent.fresh = 0, true
    if path then
        agent.path = path
        agent.state, agent.retry = 'moving', 0
    else
        agent.path = nil
        agent.state, agent.retry = 'failed', RETRY_SECONDS
    end
    return path ~= nil
end

function Crowd:update(dt)
    if dt <= 0 then
        return
    end
    local mesh = self.mesh
    mesh:refresh()
    local range = bin(self)
    local near = {}
    -- Agents that need a new path, the longest-waiting first (a moving target asks every frame).
    local needing = self.needing or {}
    self.needing = needing
    for i = #needing, 1, -1 do
        needing[i] = nil
    end
    for _, agent in ipairs(self.agents) do
        if agent.target and not agent.acting then
            if agent.state == 'failed' then
                agent.retry = agent.retry - dt
            end
            local stale = agent.path and agent.path.revision ~= mesh.revision
            if not agent.fresh or stale or (not agent.path and agent.retry <= 0) then
                agent.waited = agent.waited + 1
                needing[#needing + 1] = agent
            end
        end
    end
    table.sort(needing, function(a, b)
        return a.waited > b.waited
    end)
    for i = 1, math.min(#needing, self.repathsPerUpdate) do
        repath(self, needing[i])
    end
    for _, agent in ipairs(self.agents) do
        local wantX, wantZ = 0, 0
        if agent.target then
            local path = agent.path
            if path and agent.acting then
                -- Waiting for the game to finish the action.
            elseif path then
                local point, isStart, arrived = nextCorner(path, agent, math.max(agent.radius, 0.4))
                local tx, tz = point and point[1], point and point[3]
                if isStart and arrived then
                    agent.acting, agent.link, agent.linkIndex = true, path.links[path.index], path.index
                end
                local last = path.points[#path.points]
                local toGoalX, toGoalZ = last[1] - agent.x, last[3] - agent.z
                local remaining = math.sqrt(toGoalX ^ 2 + toGoalZ ^ 2)
                if agent.acting then
                    wantX, wantZ = 0, 0
                elseif not tx or remaining <= agent.stopDistance then
                    agent.path, agent.state = nil, 'arrived'
                    agent.target = nil
                else
                    local dx, dz = tx - agent.x, tz - agent.z
                    local length = math.sqrt(dx * dx + dz * dz)
                    if length > 1e-6 then
                        -- Slow down over the last stretch so the agent stops instead of orbiting.
                        local speed = math.min(agent.maxSpeed, remaining / 0.4)
                        wantX, wantZ = dx / length * speed, dz / length * speed
                    end
                end
            end
        end
        if agent.acting then
            agent.vx, agent.vz = 0, 0
            goto continue
        end
        local vx, vz = wantX, wantZ
        if agent.avoidance and (wantX ~= 0 or wantZ ~= 0 or agent.vx ~= 0 or agent.vz ~= 0) then
            vx, vz = steer(self, agent, wantX, wantZ, neighbours(self, agent, range, near))
        end
        local ax, az = vx - agent.vx, vz - agent.vz
        local change = math.sqrt(ax * ax + az * az)
        local limit = agent.acceleration * dt
        if change > limit then
            ax, az = ax / change * limit, az / change * limit
        end
        agent.vx, agent.vz = agent.vx + ax, agent.vz + az
        if agent.vx ~= 0 or agent.vz ~= 0 then
            local nx, nz = agent.x + agent.vx * dt, agent.z + agent.vz * dt
            local cx, cz, polygon = mesh:clamp(nx, nz, agent.y, 2)
            if cx then
                -- The velocity that was really achieved, never above the top speed: a snap back
                -- onto the mesh must not turn into a huge velocity that flings the agent aside.
                local rx, rz = (cx - agent.x) / dt, (cz - agent.z) / dt
                local speed = math.sqrt(rx * rx + rz * rz)
                if speed > agent.maxSpeed then
                    rx, rz = rx / speed * agent.maxSpeed, rz / speed * agent.maxSpeed
                end
                agent.vx, agent.vz = rx, rz
                agent.x, agent.z = cx, cz
                agent.y = mesh:heightAt(polygon.level, cx, cz) or agent.y
                agent.level = polygon.level
            else
                agent.vx, agent.vz = 0, 0
            end
        end
        ::continue::
    end
end

return Crowd
