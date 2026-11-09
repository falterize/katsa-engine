-- The AnimationTree and NavMesh demo scenes load, run and react to their controls.
local Module = {}

local function open(name, width, height)
    local window = assert(katsa.window.create(width or 480, height or 300, { title = name }))
    local scene = window:runScene(name, { fps = 1000 })
    return window, scene, scene:getScene()
end

function Module.run(self)
    local window, scene, hosted = open('animationTreeLab')
    local lab = hosted.demo
    scene:step(0.05)
    lab:setSpeed(1)
    lab:jump()
    for _ = 1, 6 do
        scene:step(0.05)
    end
    self:check(lab.tree:get('grounded') == false and lab.tree.tree:state() == 'Air',
        'The animationTreeLab jump button moves the AnimationTree into the Air state')
    for _ = 1, 40 do
        scene:step(0.05)
    end
    self:check(lab.tree.tree:state() == 'Ground', 'The tree returns to Ground when the jump ends')
    window:close()

    window, scene, hosted = open('navMeshLab')
    lab = hosted.demo
    local starts = {}
    for index, agent in ipairs(lab.agents) do
        starts[index] = { agent.position[1], agent.position[3] }
    end
    local visual = lab.agents[1].children[1]
    local startVisual = visual:getWorldPosition()
    local fastest = 0
    for _ = 1, 60 do
        scene:step(0.05)
        for _, agent in ipairs(lab.agents) do
            local speed = math.sqrt(agent._agent.vx ^ 2 + agent._agent.vz ^ 2)
            fastest = math.max(fastest, speed - agent.speed)
        end
    end
    local walking = 0
    for index, agent in ipairs(lab.agents) do
        local moved = math.abs(agent.position[1] - starts[index][1])
            + math.abs(agent.position[3] - starts[index][2])
        walking = walking + (moved > 1 and 1 or 0)
    end
    local after = visual:getWorldPosition()
    local visualMoved = math.abs(after[1] - startVisual[1]) + math.abs(after[3] - startVisual[3])
    self:check(
        lab.map:isBaked() and walking == #lab.agents and visualMoved > 1,
        'Every navMeshLab agent and its visible walker moves toward the moving goal'
    )
    self:check(fastest < 0.01, 'No navMeshLab agent ever exceeds its top speed (no sideways flings)')
    window:close()

    -- Painting: a click on the TileMap puts the selected brush into the cell under the pointer.
    window, scene, hosted = open('tileMapLab', 1280, 720)
    lab = hosted.demo
    scene:step(0.05)
    scene:step(0.05)
    self:check(hosted.world.activeCamera == nil, 'tileMapLab has no active 3D camera (no 3D render or joystick)')
    local map = lab.map
    local x0, y0 = map._x, map._y
    local cell = 32
    local cellX, cellY = 3, 3
    local px, py = x0 + cellX * cell + cell / 2, y0 + cellY * cell + cell / 2
    lab.brush = 17
    scene:receive('mousemoved', px, py, 0, 0)
    scene:receive('mousepressed', px, py, 1, false, 1)
    scene:receive('mousereleased', px, py, 1, false, 1)
    scene:step(0.05)
    self:check(map:getCell(cellX, cellY, 'Ground') == 17, 'A click on the tileMapLab map paints the brush tile')
    window:close()
end

return Module
