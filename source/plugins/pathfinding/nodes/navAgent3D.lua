-- NavAgent3D: a walker that follows the NavMesh of a NavMap3D and steers around other agents. The
-- scene needs `plugins = { 'pathfinding' }` and a baked NavMap3D.
--
--   local agent = world:create('NavAgent3D', { navMap = map, speed = 4, radius = 0.5 })
--   agent:setTarget({ 20, 0, 12 })               -- or set `targetNode` to chase a node
--   agent:connect('Arrived', function() ... end) -- also 'PathFailed'
--
-- Costs belong to the agent, never to the map or the link. `areaCosts` and `actionCosts` are
-- texts like 'water = 50, mud = 3' / 'jump = 3, climb = off' (a number multiplies the cost of
-- walking in the area or crossing a link of that action; `off` forbids it). Unset names use the
-- defaults: every area 1, `jump` 2, other actions 1. A large number makes a route a last resort.
-- From code: agent:setAreaCost('water', 50), agent:setActionCost('jump', false).
--
-- Actions are performed by your script: at the start of a NavLink3D the agent stops and emits
-- 'LinkReached' (link); move it with `agent:placeAt(x, y, z)` (a jump arc, for example) and call
-- `agent:finishLink()`. `agent:cancelLink()` renews the route instead.
--
-- With `autoMove` the node's position follows the simulated agent (put it under an untransformed
-- parent); turn it off to read `agent:getVelocity()` and move a character yourself.
local Definition = {
    base = 'Node3D',
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
        speed = { default = 4, min = 0, hint = 'Top walking speed, units per second.' },
        acceleration = { default = 16, min = 0, hint = 'How fast the agent reaches its wanted velocity.' },
        radius = { default = 0.5, min = 0.05, hint = 'Space the agent takes when avoiding others.' },
        stoppingDistance = { default = 0.3, min = 0, hint = 'The agent has arrived this close to the target.' },
        avoidance = { default = true, hint = 'Steer around other agents of the same map.' },
        autoMove = { default = true, hint = 'Move this node with the agent. Off: read getVelocity() yourself.' },
        areaCosts = { default = '', hint = "Cost of walking in areas, e.g. 'water = 50, mud = 3'. Empty = every area costs 1; 'off' forbids." },
        actionCosts = { default = '', hint = "Cost of link actions, e.g. 'jump = 3, climb = off'. Defaults: jump 2, others 1; 'off' forbids." },
        state = { default = 'idle', readOnly = true, hint = 'idle, moving, arrived or failed.' },
        action = { default = '', readOnly = true, hint = 'Action of the link the agent is performing, empty otherwise.' },
    },
}

local RETARGET = 0.5

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
        acceleration = self.acceleration,
        stopDistance = self.stoppingDistance,
        avoidance = self.avoidance,
        areaCosts = parseCosts(self.areaCosts),
        actionCosts = parseCosts(self.actionCosts),
    })
    self._areaText, self._actionText = self.areaCosts, self.actionCosts
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
    self._announced = nil
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

-- The NavLink3D link being crossed (see 'LinkReached'), its start and far end as { x, y, z }.
function Definition:getLink()
    return self._agent and self._agent.link
end

function Definition:getLinkEnd()
    local agent = self._agent
    local path = agent and agent.path
    local point = path and agent.linkIndex and path.points[agent.linkIndex + 1]
    return point and { point[1], point[2], point[3] }
end

-- Moves the agent (and, with autoMove, this node) while your script performs an action.
function Definition:placeAt(x, y, z)
    if self._agent then
        self._crowd:place(self._agent, x, y, z)
        if self.autoMove then
            self.position = { x, y, z }
        end
    end
end

function Definition:finishLink()
    return self._agent ~= nil and self._crowd:finishLink(self._agent)
end

function Definition:cancelLink()
    if self._agent then
        self._crowd:cancelLink(self._agent)
    end
end

function Definition:isActing()
    return self._agent ~= nil and self._agent.acting
end

function Definition:getVelocity()
    local agent = self._agent
    return agent and agent.vx or 0, 0, agent and agent.vz or 0
end

function Definition:isMoving()
    return self.state == 'moving'
end

function Definition:update(dt)
    if not self:_join() then
        return
    end
    local agent = self._agent
    agent.radius, agent.maxSpeed, agent.acceleration = self.radius, self.speed, self.acceleration
    agent.stopDistance, agent.avoidance = self.stoppingDistance, self.avoidance
    if self._areaText ~= self.areaCosts then
        self._areaText, agent.areaCosts, agent.fresh = self.areaCosts, parseCosts(self.areaCosts), false
    end
    if self._actionText ~= self.actionCosts then
        self._actionText, agent.actionCosts, agent.fresh =
            self.actionCosts, parseCosts(self.actionCosts), false
    end
    local chased = self.targetNode
    if chased and not chased.destroyed then
        local position = chased:getWorldPosition()
        local goal = self._goal
        if
            not goal
            or math.abs(goal[1] - position[1]) + math.abs(goal[3] - position[3]) > RETARGET
        then
            self:setTarget(position)
        end
    end
    local link = agent.acting and agent.link
    if link and self._actionLink ~= link then
        self._actionLink = link
        self.action = link.action
        self:emit('LinkReached', link)
    elseif not link and self._actionLink then
        self._actionLink, self.action = nil, ''
    end
    if self.autoMove then
        self.position = { agent.x, agent.y, agent.z }
    else
        agent.x, agent.y, agent.z = unpack(self:getWorldPosition())
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
