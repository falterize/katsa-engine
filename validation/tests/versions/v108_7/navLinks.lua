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
    agent:setTarget({ 10, 0, 0 })
    for _ = 1, 80 do
        world:updateNodes(1 / 20)
        if agent:isActing() then
            break
        end
    end
    tester:check(reached == 1 and agent.action == 'jump', 'the agent stops at the link and reports LinkReached')
    local x = agent.position[1]
    for _ = 1, 10 do
        world:updateNodes(1 / 20)
    end
    tester:check(math.abs(agent.position[1] - x) < 0.01, 'the agent waits while the script performs the action')
    local target = agent:getLinkEnd()
    agent:placeAt(target[1], target[2], target[3])
    agent:finishLink()
    for _ = 1, 60 do
        world:updateNodes(1 / 20)
    end
    tester:check(arrived and agent.position[1] > 5, 'after finishLink the agent walks on to its goal')
    nav:destroy()
end

return Tests
