-- Agent-side weights, NavArea3D regions and NavLink3D action links with a script-run action.
local Plugins = require('source.engine.plugins')
local World = require('source.engine.world.world')

local Tests = {}

local function build()
    local world = World.new(Tests.manager.resources:scope())
    world:createPhysics({ backend = 'oimo', gravity = { 0, 0, 0 } })
    Plugins.activate(world, { 'pathfinding' })
    world:create('Body3D', { bodyType = 'Static', size = { 40, 1, 40 }, position = { 0, -0.5, 0 } })
    return world
end

local function map(world)
    world:updateNodes(1 / 60)
    local nav = world:create('NavMap3D', { areaSize = { 40, 40 }, cellSize = 1, agentRadius = 0, castTop = 10, castBottom = -5 })
    nav:bake()
    return nav
end

local function detours(path)
    for _, point in ipairs(path and path.points or {}) do
        if math.abs(point[3]) > 5 then
            return true
        end
    end
    return false
end

function Tests.run(tester)
    Tests.manager = tester.manager
    local world = build()
    world:create('NavArea3D', { area = 'water', size = { 8, 3, 12 }, position = { 0, 0, 0 } })
    local nav = map(world)
    local from, to = { -10, 0, 0 }, { 10, 0, 0 }
    tester:check(not detours(nav:findSmoothPath(from, to)), 'unpriced water is walked through (cost 1)')
    local costs = { areaCosts = { water = 50 } }
    tester:check(detours(nav:findSmoothPath(from, to, costs)), 'an agent that prices water at 50 walks around it')
    tester:check(
        nav:findSmoothPath({ 0, 0, 0 }, { 10, 0, 0 }, { areaCosts = { water = false } }) ~= nil,
        'a forbidden area does not trap an agent standing in it'
    )
    nav:destroy()

    world = build()
    world:create('Body3D', { bodyType = 'Static', size = { 2, 4, 40 }, position = { 0, 2, 0 } })
    nav = map(world)
    tester:check(nav:findSmoothPath(from, to) == nil, 'a full-width wall leaves no route')
    local node = world:create('NavLink3D', {
        navMap = nav,
        action = 'jump',
        position = { -3, 0, 0 },
        endOffset = { 6, 0, 0 },
    })
    world:updateNodes(1 / 60)
    local path = nav:findSmoothPath(from, to)
    local linked = false
    for _, link in pairs(path and path.links or {}) do
        linked = linked or link.action == 'jump'
    end
    tester:check(node.state == 'linked' and linked, 'a NavLink3D joins the two sides and routes use it')
    tester:check(
        nav:findSmoothPath(from, to, { actionCosts = { jump = false } }) == nil,
        'an agent that forbids the action finds no route'
    )
    node.active = false
    world:updateNodes(1 / 60)
    tester:check(nav:findSmoothPath(from, to) == nil, 'a disabled link is not used')
    node.active = true
    world:updateNodes(1 / 60)

    local agent = world:create('NavAgent3D', {
        navMap = nav,
        speed = 8,
        position = { -10, 0, 0 },
        areaCosts = 'water = 50',
        actionCosts = 'jump = 3, climb = off',
    })
    world:updateNodes(1 / 60)
    tester:check(
        agent._agent.areaCosts.water == 50 and agent._agent.actionCosts.jump == 3 and agent._agent.actionCosts.climb == false,
        'agent cost texts are parsed per agent'
    )
    local reached, arrived = 0, false
    agent:connect('LinkReached', function()
        reached = reached + 1
    end)
    agent:connect('Arrived', function()
        arrived = true
    end)
    -- The script's side: walk toward the advised corner; at the link start do the action by hand.
    local function walk(dt, jump)
        local next, at = agent:getNextPathPosition(), agent.position
        local dx, dz = next[1] - at[1], next[3] - at[3]
        local length = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
        if agent:getNextAction() == 'jump' and length < 0.3 then
            if jump then
                local landing = agent:getActionTarget()
                agent.position = { landing[1], landing[2], landing[3] }
            end
            return
        end
        local step = math.min(length, 8 * dt)
        agent.position = { at[1] + dx / length * step, at[2], at[3] + dz / length * step }
    end
    agent:setTarget({ 10, 0, 0 })
    local advised, landing
    for _ = 1, 80 do
        world:updateNodes(1 / 20)
        if agent:getNextAction() == 'jump' then
            advised, landing = agent.action, agent:getActionTarget()
            break
        end
        walk(1 / 20, false)
    end
    tester:check(advised == 'jump' and landing and landing[1] > 0, 'the agent advises the jump before it reaches the link start')
    local x = agent.position[1]
    for _ = 1, 10 do
        world:updateNodes(1 / 20)
        walk(1 / 20, false)
    end
    tester:check(
        agent:getNextAction() == 'jump' and reached == 0 and agent.position[1] - x < 6,
        'without the jump the agent keeps advising it and does not cross by itself'
    )
    for _ = 1, 120 do
        world:updateNodes(1 / 20)
        walk(1 / 20, true)
    end
    tester:check(reached == 1 and arrived and agent.position[1] > 5, 'after the script jumps the agent reports LinkReached and walks on to its goal')
    tester:check(agent.fits, 'a small agent fits the baked mesh')
    agent.radius = 40
    world:updateNodes(1 / 20)
    tester:check(not agent.fits and agent.fitProblem:find('agentRadius'), 'an agent wider than the baked clearance reports that it does not fit')
    agent:destroy()
    nav:destroy()
end

return Tests
