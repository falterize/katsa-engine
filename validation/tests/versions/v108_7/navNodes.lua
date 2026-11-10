-- NavMap3D bakes a NavMesh from physics; NavObstacle3D and NavAgent3D drive it.
local Plugins = require('source.engine.plugins')
local World = require('source.engine.world.world')

local Tests = {}

function Tests.run(tester)
    local world = World.new(tester.manager.resources:scope())
    world:createPhysics({ backend = 'oimo', gravity = { 0, 0, 0 } })
    Plugins.activate(world, { 'pathfinding' })
    world:create('Body3D', { bodyType = 'Static', size = { 40, 1, 40 }, position = { 0, -0.5, 0 } })
    world:create('Body3D', { bodyType = 'Static', size = { 3, 4, 20 }, position = { 0, 2, -15 } })
    world:updateNodes(1 / 60)
    local map = world:create('NavMap3D', {
        areaSize = { 40, 40 },
        cellSize = 1,
        agentRadius = 0,
        castTop = 10,
        castBottom = -5,
    })
    local free = map:bake()
    tester:check(free > 1000 and map:getMesh():polygonCount() > 0, 'NavMap3D bake builds the NavMesh')
    local from, to = { -10, 0, 0 }, { 10, 0, 0 }
    local straight = map:findSmoothPath(from, to)
    tester:check(straight ~= nil and #straight.points == 2, 'a straight route has only its end points')
    local around = map:findSmoothPath({ -10, 0, -8 }, { 10, 0, -8 })
    tester:check(around and #around.points > 2, 'the baked wall forces a route around it')

    local obstacle = world:create('NavObstacle3D', { shape = 'Circle', radius = 3, position = { 0, 0, 0 } })
    world:updateNodes(1 / 60)
    local blocked = map:findSmoothPath(from, to)
    local detour = false
    for _, point in ipairs(blocked and blocked.points or {}) do
        detour = detour or math.abs(point[3]) > 2.5
    end
    tester:check(detour, 'a NavObstacle3D makes routes detour around it')
    obstacle.position = { 0, 0, 12 }
    world:updateNodes(1 / 60)
    tester:check(#map:findSmoothPath(from, to).points == 2, 'moving the obstacle opens the way again')
    obstacle:destroy()

    local agent = world:create('NavAgent3D', { navMap = map, speed = 6, position = { -10, 0, 0 } })
    local arrived = 0
    agent:connect('Arrived', function()
        arrived = arrived + 1
    end)
    world:updateNodes(1 / 60)
    agent:setTarget(to)
    for _ = 1, 600 do
        world:updateNodes(1 / 60)
        -- Like a script would: step toward the advised corner at the agent's speed.
        if not agent:isNavigationFinished() then
            local next, at = agent:getNextPathPosition(), agent.position
            local dx, dz = next[1] - at[1], next[3] - at[3]
            local length = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
            local step = math.min(length, 6 / 60)
            agent.position = { at[1] + dx / length * step, at[2], at[3] + dz / length * step }
        end
    end
    tester:check(
        arrived == 1 and math.abs(agent.position[1] - 10) < 0.6 and agent:isTargetReached(),
        'a NavAgent3D advises the way and reports Arrived while the script moves the body'
    )
    agent:destroy()
    map:destroy()
end

return Tests
