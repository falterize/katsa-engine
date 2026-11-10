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
-- Action links (jump, climb, door ...) are crossed one of two ways. A simulated agent (the default)
-- teleports to the far end of the link when it reaches the start. An `external` agent is moved by
-- the game (a physical body, like Godot's NavigationAgent): the crowd only reads its position
-- (`x, y, z`, plus the measured velocity `vx, vz`) and writes what to do next:
--   agent.nextPoint   the corner to walk to (a link start while an action is ahead)
--   agent.link        the link whose action is ahead or under way, nil otherwise
--   agent.linkIndex   index of the link start in the path (the far end is the next point)
--   agent.safeX/safeZ the wanted velocity after avoiding neighbours
--   agent.crossed     counts finished links; agent.lastLink is the latest one
-- A link is finished when the agent stands near its far end; leaving the route by more than
-- `pathMaxDistance` (or falling below a link) renews the path.
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
-- avoidance (true), external (false), pathDistance (corner reach, default max(radius, 0.4)),
-- pathMaxDistance (3, external agents: farthest allowed from the route before a new path).
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
        external = options.external == true,
        pathDistance = options.pathDistance,
        pathMaxDistance = options.pathMaxDistance or 3,
        state = 'idle',
        areaCosts = options.areaCosts,
        actionCosts = options.actionCosts,
        crossed = 0,
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
    agent.link, agent.linkIndex, agent.nextPoint = nil, nil, nil
end

-- The agent has crossed the link that starts at `index` of its path: it continues after the far
-- end. A simulated agent is put there; an external one has already arrived.
local function cross(agent, path, index)
    local far = path.points[index + 1]
    if not agent.external then
        agent.x, agent.y, agent.z = far[1], far[2], far[3]
        agent.vx, agent.vz = 0, 0
    end
    agent.level = path.levels[index + 1]
    agent.lastLink = path.links[index]
    agent.crossed = agent.crossed + 1
    path.index = index + 2
end

-- Next corner of the route: corners within reach are passed. At the start of an action link a
-- simulated agent crosses as soon as it is there; an external agent keeps heading for the start
-- (the game performs the action) until it stands near the far end. `isStart` is true while the
-- returned corner is a link start.
local function nextCorner(path, agent, reach)
    while path.index <= #path.points do
        local index = path.index
        local point = path.points[index]
        local dx, dz = point[1] - agent.x, point[3] - agent.z
        local near = math.sqrt(dx * dx + dz * dz) <= reach
        if path.roles and path.roles[index] == 'start' then
            local far = path.points[index + 1]
            if agent.external and far then
                local fx, fz = far[1] - agent.x, far[3] - agent.z
                if math.sqrt(fx * fx + fz * fz) <= reach and math.abs(far[2] - agent.y) <= 1 then
                    cross(agent, path, index)
                    goto continue
                end
            elseif near and far then
                cross(agent, path, index)
                goto continue
            end
            return point, true
        end
        if not near then
            return point, false
        end
        path.index = index + 1
        ::continue::
    end
end

local function segmentDistance(px, pz, ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az
    local length = dx * dx + dz * dz
    local t = length > 1e-9 and math.max(0, math.min(1, ((px - ax) * dx + (pz - az) * dz) / length)) or 0
    local qx, qz = ax + dx * t, az + dz * t
    return math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2)
end

-- True while the agent is clearly above the walkable surface under it.
local function inAir(mesh, agent)
    local cx, cz, polygon = mesh:clamp(agent.x, agent.z, agent.y, 2)
    if not cx then
        return true
    end
    local ground = mesh:heightAt(polygon.level, cx, cz)
    return ground ~= nil and agent.y - ground > 0.3
end

-- An action is under way: the body left the link start toward the far end (or is in the air). A
-- new route would start from the ground below and forget the landing, so changes of the target or
-- the mesh wait until the body stands at the far end.
local function committed(mesh, agent)
    local path, index = agent.path, agent.linkIndex
    local a, b = path.points[index], path.points[index + 1]
    local dx, dz = b[1] - a[1], b[3] - a[3]
    local length = dx * dx + dz * dz
    if length > 1e-9 and ((agent.x - a[1]) * dx + (agent.z - a[3]) * dz) / length > 0.1 then
        return true
    end
    return inAir(mesh, agent)
end

-- How far an external agent is from the stretch of the route it is on (huge after falling below
-- a link it should have crossed).
local function deviation(path, agent)
    local index = path.index
    local points = path.points
    local here = points[index]
    if not here then
        return 0
    end
    local best = math.huge
    local before = points[index - 1]
    local isLink = path.roles and path.roles[index] == 'start'
    if before then
        best = segmentDistance(agent.x, agent.z, before[1], before[3], here[1], here[3])
    end
    if isLink and points[index + 1] then
        local far = points[index + 1]
        if agent.y < math.min(here[2], far[2]) - 1.5 then
            return math.huge
        end
        best = math.min(best, segmentDistance(agent.x, agent.z, here[1], here[3], far[1], far[3]))
    end
    return best == math.huge and 0 or best
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
    -- Corners (and finished actions) are passed before anything asks for a new route.
    for _, agent in ipairs(self.agents) do
        if agent.target and agent.path then
            nextCorner(agent.path, agent, agent.pathDistance or math.max(agent.radius, 0.4))
        end
    end
    for _, agent in ipairs(self.agents) do
        if agent.target then
            if agent.state == 'failed' then
                agent.retry = agent.retry - dt
            end
            local path = agent.path
            local wants = not agent.fresh
                or (path and path.revision ~= mesh.revision)
                or (not path and agent.retry <= 0)
            if wants and path and agent.external and agent.link and committed(mesh, agent) then
                wants = false
            end
            -- Straying from the route (a missed jump, a fall) always asks for a new one.
            if agent.external and path and agent.fresh and deviation(path, agent) > agent.pathMaxDistance then
                wants = true
            end
            if wants then
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
        agent.nextPoint, agent.link, agent.linkIndex = nil, nil, nil
        local path = agent.target and agent.path
        if path then
            local point, isStart = nextCorner(path, agent, agent.pathDistance or math.max(agent.radius, 0.4))
            local last = path.points[#path.points]
            local toGoalX, toGoalZ = last[1] - agent.x, last[3] - agent.z
            local remaining = math.sqrt(toGoalX ^ 2 + toGoalZ ^ 2)
            -- Standing above the last corner in the middle of an action is not arriving.
            if not point or (remaining <= agent.stopDistance and not isStart) then
                agent.path, agent.state = nil, 'arrived'
                agent.target = nil
            else
                agent.nextPoint = point
                if isStart then
                    agent.link, agent.linkIndex = path.links[path.index], path.index
                end
                local dx, dz = point[1] - agent.x, point[3] - agent.z
                local length = math.sqrt(dx * dx + dz * dz)
                if length > 1e-6 then
                    -- Slow down over the last stretch so the agent stops instead of orbiting.
                    local speed = math.min(agent.maxSpeed, remaining / 0.4)
                    wantX, wantZ = dx / length * speed, dz / length * speed
                end
            end
        end
        local vx, vz = wantX, wantZ
        if agent.avoidance and (wantX ~= 0 or wantZ ~= 0 or agent.vx ~= 0 or agent.vz ~= 0) then
            vx, vz = steer(self, agent, wantX, wantZ, neighbours(self, agent, range, near))
        end
        if agent.external then
            -- The game moves the agent; it only learns the velocity it should aim for.
            agent.safeX, agent.safeZ = vx, vz
            goto continue
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
