-- NavAgent3D: plans routes on the NavMesh of a NavMap3D for a body that YOUR script moves, like
-- Godot's NavigationAgent3D. The node never moves anything. It tells the script where to go next,
-- which action comes next and how to steer around other agents; it stores the cost weights.
-- The scene needs `plugins = { 'pathfinding' }` and a baked NavMap3D. The node is purely technical
-- (no transform of its own): create it as a child of the body; the agent stands at that body's
-- origin lowered by `feetOffset`. Without a spatial parent use `agent:setPosition({ x, y, z })`.
--
--   local agent = world:create('NavAgent3D', { navMap = map, speed = 4, radius = 0.5 }, body)
--   agent:setTarget({ 20, 0, 12 })                 -- or set `targetNode` to chase a node
--   -- every frame / physics step:
--   if not agent:isNavigationFinished() then
--       local next = agent:getNextPathPosition()   -- walk toward this point
--       local vx, _, vz = agent:getVelocity()      -- wanted velocity, neighbours avoided
--       local action = agent:getNextAction()       -- '' or 'jump', 'climb', 'door' ...
--       local landing = agent:getActionTarget()    -- where that action ends (or nil)
--   end
--   agent:connect('Arrived', f)  -- also 'PathFailed' and 'LinkReached' (link)
--
-- Actions: a NavLink3D on the route shows up as `getNextAction()` while the agent is on its way to
-- the link's start and during the action itself; `getNextPathPosition()` is the link start until
-- the body stands near the far end, then the route goes on. The script decides when and how to
-- jump, climb or open: a Character that presses jump, a tween, an animation. If the body ends up
-- off the route (a missed jump) a new route is planned from where it stands (`pathMaxDistance`).
--
-- Costs belong to the agent, never to the map or the link. `areaCosts` and `actionCosts` are
-- texts like 'water = 50, mud = 3' / 'jump = 3, climb = off' (a number multiplies the cost of
-- walking in the area or crossing a link of that action; `off` forbids it). Unset names use the
-- defaults: every area 1, `jump` 2, other actions 1. A large number makes a route a last resort.
-- From code: agent:setAreaCost('water', 50), agent:setActionCost('jump', false).
--
-- Size: the map is baked for one body size (NavMap3D `agentRadius`, `agentHeight`, `maxStep`,
-- `maxSlope`); nothing is measured from the body. `radius` and `height` describe this agent so
-- `fits` can say whether the baked mesh keeps it clear of walls and ceilings (`fitProblem` tells
-- what to raise on the map). `radius` also sets the space the agent takes when avoiding others.
local Definition = {
    base = 'Node',
    properties = {
        navMap = {
            default = nil,
            kind = 'node',
            nodeClass = 'NavMap3D',
            hint = 'NavMap3D to walk on. Empty = the first baked NavMap3D of the world.',
        },
        targetNode = {
            default = nil,
            kind = 'node',
            nodeClass = 'Node3D',
            hint = 'Node to walk to. The route is renewed when it moves.',
        },
        speed = { default = 4, min = 0, hint = 'Top walking speed the avoidance plans with, units per second.' },
        radius = { default = 0.5, min = 0.05, hint = 'Body radius: space taken when avoiding others, checked against the baked clearance.' },
        feetOffset = { default = 0, hint = 'How far below the parent node the agent stands (half the body height for a centred body).' },
        height = { default = 1.5, min = 0.1, hint = 'Body height, checked against the NavMap3D agentHeight.' },
        pathDesiredDistance = { default = 0.5, min = 0.05, hint = 'A route corner counts as reached this close.' },
        targetDesiredDistance = { default = 0.3, min = 0, hint = 'The target counts as reached this close.' },
        pathMaxDistance = { default = 3, min = 0.1, hint = 'Farthest the body may stray from the route before a new route is planned.' },
        avoidance = { default = true, hint = 'Steer around other agents of the same map.' },
        areaCosts = { default = '', hint = "Cost of walking in areas, e.g. 'water = 50, mud = 3'. Empty = every area costs 1; 'off' forbids." },
        actionCosts = { default = '', hint = "Cost of link actions, e.g. 'jump = 3, climb = off'. Defaults: jump 2, others 1; 'off' forbids." },
        state = { default = 'idle', readOnly = true, hint = 'idle, moving, arrived or failed.' },
        action = { default = '', readOnly = true, hint = 'Action ahead on the route (jump, climb ...), empty otherwise.' },
        fits = { default = true, readOnly = true, hint = 'False when the baked mesh is too tight for radius / height.' },
        fitProblem = { default = '', readOnly = true, hint = 'What to change when the agent does not fit.' },
    },
}

local RETARGET = 0.5
local VELOCITY_SMOOTHING = 0.5

-- 'water = 50, mud = 3, climb = off' -> { water = 50, mud = 3, climb = false }
local function parseCosts(text)
    local costs = {}
    for name, value in tostring(text or ''):gmatch('([%w_%.%-]+)%s*=%s*([%w_%.%-]+)') do
        local lower = value:lower()
        if lower == 'off' or lower == 'false' or lower == 'inf' or lower == 'forbid' then
            costs[name] = false
        elseif tonumber(value) then
            costs[name] = math.max(0, tonumber(value))
        end
    end
    return costs
end

local function mapOf(self)
    local map = self.navMap
    if map and (map.destroyed or not map:isBaked()) then
        return nil
    end
    if not map then
        local world = self._world or self._sceneWorld
        for _, known in ipairs(world and world.navMaps or {}) do
            if not known.destroyed and known:isBaked() then
                return known
            end
        end
    end
    return map
end

-- Where the agent stands: the point given to setPosition, otherwise the parent's world position
-- lowered by `feetOffset`.
function Definition:getWorldPosition()
    local own = self._position
    if own then
        return { own[1], own[2], own[3] }
    end
    local parent = self.parent
    if parent and parent.getWorldPosition and not parent:isA('World3D') then
        local p = parent:getWorldPosition()
        return { p[1], p[2] - self.feetOffset, p[3] }
    end
    return { 0, 0, 0 }
end

function Definition:setPosition(point)
    self._position = { point[1], point[2], point[3] }
end

-- Joins the crowd of the map as soon as it is baked (the map can be baked after this node).
function Definition:_join()
    local map = mapOf(self)
    if not map then
        return false
    end
    if self._agent and self._map == map then
        return true
    end
    self:_leave()
    local position = self:getWorldPosition()
    self._map, self._crowd = map, map:getCrowd()
    self._agent = self._crowd:add({
        x = position[1],
        y = position[2],
        z = position[3],
        radius = self.radius,
        maxSpeed = self.speed,
        stopDistance = self.targetDesiredDistance,
        pathDistance = self.pathDesiredDistance,
        pathMaxDistance = self.pathMaxDistance,
        avoidance = self.avoidance,
        external = true,
        areaCosts = parseCosts(self.areaCosts),
        actionCosts = parseCosts(self.actionCosts),
    })
    self._areaText, self._actionText = self.areaCosts, self.actionCosts
    self._last, self._crossed = { position[1], position[2], position[3] }, 0
    if not self._connected then
        self._connected = true
        self:onDestroy(function()
            self:_leave()
        end)
    end
    if self._goal then
        self._crowd:setTarget(self._agent, self._goal[1], self._goal[2], self._goal[3])
    end
    return true
end

function Definition:_leave()
    if self._crowd and self._agent then
        self._crowd:remove(self._agent)
    end
    self._agent, self._crowd, self._map = nil, nil, nil
end

-- Walks to { x, y, z } (y = height of the surface there).
function Definition:setTarget(point)
    self._goal = { point[1], point[2], point[3] }
    if self._agent then
        self._crowd:setTarget(self._agent, point[1], point[2], point[3])
    end
end

function Definition:clearTarget()
    self._goal = nil
    if self._agent then
        self._crowd:clearTarget(self._agent)
    end
end

-- Code-side costs: they replace the matching entry of the text properties until it changes.
function Definition:setAreaCost(name, cost)
    if self._agent then
        self._agent.areaCosts[name] = cost
        self._agent.fresh = false
    end
end

function Definition:setActionCost(name, cost)
    if self._agent then
        self._agent.actionCosts[name] = cost
        self._agent.fresh = false
    end
end

-- The corner to walk to now, { x, y, z }; the node's own position when there is no route.
function Definition:getNextPathPosition()
    local point = self._agent and self._agent.nextPoint
    if point then
        return { point[1], point[2], point[3] }
    end
    return self:getWorldPosition()
end

-- Action of the NavLink3D ahead ('jump', 'climb' ...), '' on plain ground.
function Definition:getNextAction()
    local link = self._agent and self._agent.link
    return link and link.action or ''
end

-- The NavLink3D object ahead (see NavLink3D:getLink), its data table, or nil.
function Definition:getNextLink()
    return self._agent and self._agent.link
end

-- Where the action ahead ends, { x, y, z }, or nil on plain ground.
function Definition:getActionTarget()
    local agent = self._agent
    local path = agent and agent.link and agent.path
    local point = path and path.points[agent.linkIndex + 1]
    return point and { point[1], point[2], point[3] }
end

-- The route as a list of { x, y, z, action = name } (action is set on link starts).
function Definition:getPath()
    local agent = self._agent
    local path = agent and agent.path
    local list = {}
    for i = path and path.index or 1, path and #path.points or 0 do
        local point = path.points[i]
        local link = path.links[i]
        list[#list + 1] = { point[1], point[2], point[3], action = path.roles[i] == 'start' and link and link.action or nil }
    end
    return list
end

-- Wanted velocity toward the next corner after steering around neighbours: (vx, 0, vz).
function Definition:getVelocity()
    local agent = self._agent
    return agent and agent.safeX or 0, 0, agent and agent.safeZ or 0
end

function Definition:isNavigationFinished()
    return self.state ~= 'moving'
end

function Definition:isTargetReached()
    return self.state == 'arrived'
end

function Definition:isMoving()
    return self.state == 'moving'
end

function Definition:getDistanceToTarget()
    local goal = self._goal
    if not goal then
        return 0
    end
    local position = self:getWorldPosition()
    return math.sqrt((goal[1] - position[1]) ^ 2 + (goal[3] - position[3]) ^ 2)
end

-- Compares the body with what the map was baked for.
local function checkFit(self, map)
    local clearance, height = map:getClearance()
    local problem = ''
    if self.radius > clearance + 1e-6 then
        problem = ('radius %.2f is wider than the baked clearance %.2f: raise NavMap3D.agentRadius'):format(
            self.radius,
            clearance
        )
    elseif self.height > height + 1e-6 then
        problem = ('height %.2f is taller than NavMap3D.agentHeight %.2f'):format(self.height, height)
    end
    if problem ~= self.fitProblem then
        self.fitProblem, self.fits = problem, problem == ''
    end
end

function Definition:update(dt)
    if not self:_join() then
        return
    end
    local agent = self._agent
    local position = self:getWorldPosition()
    -- External agents are moved by the script: read the position and measure the velocity the
    -- neighbours avoid (smoothed, because the body moves in fixed steps).
    if dt > 0 then
        local last = self._last
        local k = VELOCITY_SMOOTHING
        agent.vx = agent.vx * (1 - k) + (position[1] - last[1]) / dt * k
        agent.vz = agent.vz * (1 - k) + (position[3] - last[3]) / dt * k
    end
    self._last = { position[1], position[2], position[3] }
    agent.x, agent.y, agent.z = position[1], position[2], position[3]
    agent.radius, agent.maxSpeed = self.radius, self.speed
    agent.stopDistance, agent.pathDistance = self.targetDesiredDistance, self.pathDesiredDistance
    agent.pathMaxDistance, agent.avoidance = self.pathMaxDistance, self.avoidance
    if self._areaText ~= self.areaCosts then
        self._areaText, agent.areaCosts, agent.fresh = self.areaCosts, parseCosts(self.areaCosts), false
    end
    if self._actionText ~= self.actionCosts then
        self._actionText, agent.actionCosts, agent.fresh =
            self.actionCosts, parseCosts(self.actionCosts), false
    end
    checkFit(self, self._map)
    local chased = self.targetNode
    if chased and not chased.destroyed then
        local point = chased:getWorldPosition()
        local goal = self._goal
        if not goal or math.abs(goal[1] - point[1]) + math.abs(goal[3] - point[3]) > RETARGET then
            self:setTarget(point)
        end
    end
    local link = agent.link
    local action = link and link.action or ''
    if action ~= self.action then
        self.action = action
    end
    if agent.crossed ~= self._crossed then
        self._crossed = agent.crossed
        self:emit('LinkReached', agent.lastLink)
    end
    -- The crowd runs from the NavMap3D node's own update; report only changes of its state.
    if agent.state ~= self.state then
        self.state = agent.state
        if agent.state == 'arrived' then
            self:emit('Arrived')
        elseif agent.state == 'failed' then
            self:emit('PathFailed')
        end
    end
end

return Definition
