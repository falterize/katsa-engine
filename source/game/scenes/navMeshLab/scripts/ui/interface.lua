local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(state)
    local scene, ui = state.scene, state.scene.ui
    local panel = ui:container({
        _viewportAuthored = true,
        name = 'NavControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 270, 0, 176 },
        backgroundColor = Theme.panel,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, Theme.corner } }, panel)
    local blocking = true
    local obstacle = ui:button({
        position = { 0, 8, 0, 8 },
        size = { 1, -16, 0, 32 },
        text = 'Pillar blocks: on',
    }, panel)
    obstacle.onPress = function()
        blocking = not blocking
        state:setObstacleBlocking(blocking)
        obstacle.text = 'Pillar blocks: ' .. (blocking and 'on' or 'off')
    end
    local debug = true
    local view = ui:button({
        position = { 0, 8, 0, 48 },
        size = { 1, -16, 0, 32 },
        text = 'Navigation view: on',
    }, panel)
    view.onPress = function()
        debug = not debug
        scene.world.environment.debug.pathfinding.enabled = debug
        view.text = 'Navigation view: ' .. (debug and 'on' or 'off')
    end
    ui:create('Label', {
        position = { 0, 8, 0, 88 },
        size = { 1, -16, 0, 80 },
        text = 'Blue walkers chase the yellow goal around the walls and each other. '
            .. 'The red pillar is a NavObstacle3D: the mesh under it is rebuilt as it slides.',
        fontSize = 13,
    }, panel)
end

return Interface
