-- The AnimationTree and NavMesh demo scenes load, run and react to their controls.
local Module = {}

local function open(name)
    local window = assert(katsa.window.create(480, 300, { title = name }))
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
    local agent = lab.agents[1]
    local visual = agent.children[1]
    local startX, startZ = agent.position[1], agent.position[3]
    local startVisual = visual:getWorldPosition()
    for _ = 1, 60 do
        scene:step(0.05)
    end
    local moved = math.abs(agent.position[1] - startX) + math.abs(agent.position[3] - startZ)
    local after = visual:getWorldPosition()
    local visualMoved = math.abs(after[1] - startVisual[1]) + math.abs(after[3] - startVisual[3])
    self:check(
        lab.map:isBaked() and moved > 1 and visualMoved > 1,
        'The navMeshLab agents and their visible walkers move toward the goal on the baked NavMesh'
    )
    window:close()
end

return Module
