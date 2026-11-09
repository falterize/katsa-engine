-- NavAgent3D: a walker that follows the NavMesh of a NavMap and steers around other agents. The
-- scene needs `plugins = { 'pathfinding' }` and a baked NavMap.
--
--   local agent = world:create('NavAgent3D', { navMap = map, speed = 4, radius = 0.5 })
--   agent:setTarget({ 20, 0, 12 })               -- or set `targetNode` to chase a node
--   agent:connect('Arrived', function() ... end) -- also 'PathFailed'
--
-- With `autoMove` the node's position follows the simulated agent (put it under an untransformed
-- parent); turn it off to read `agent:getVelocity()` and move a character yourself.
local Definition = {
    base = 'Node3D',
    properties = {
        navMap = {
            default = nil,
            kind = 'node',
            nodeClass = 'NavMap',
            hint = 'NavMap to walk on. Empty = the first baked NavMap of the world.',
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
        state = { default = 'idle', readOnly = true, hint = 'idle, moving, arrived or failed.' },
    },
}

local RETARGET = 0.5

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
    })
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
    if self.autoMove then
        self.position = { agent.x, agent.y, agent.z }
    else
        agent.x, agent.y, agent.z = unpack(self:getWorldPosition())
    end
    -- The crowd runs from the NavMap node's own update; report only changes of its state.
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
