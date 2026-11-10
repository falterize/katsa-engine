local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(state)
    local scene, ui = state.scene, state.scene.ui
    local panel = ui:container({
        _viewportAuthored = true,
        name = 'NavControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 290, 0, 330 },
        backgroundColor = Theme.panel,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, Theme.corner } }, panel)
    local blocking = true
    local obstacle = ui:button({
        position = { 0, 8, 0, 8 },
        size = { 1, -16, 0, 32 },
        text = 'Pillar blocks: on',
    }, panel)
    obstacle:connect('press', function()
        blocking = not blocking
        state:setObstacleBlocking(blocking)
        obstacle.text = 'Pillar blocks: ' .. (blocking and 'on' or 'off')
    end)
    local debug = true
    local view = ui:button({
        position = { 0, 8, 0, 48 },
        size = { 1, -16, 0, 32 },
        text = 'Navigation view: on',
    }, panel)
    view:connect('press', function()
        debug = not debug
        scene.world.environment.debug.pathfinding.enabled = debug
        view.text = 'Navigation view: ' .. (debug and 'on' or 'off')
    end)
    ui:create('Label', {
        position = { 0, 8, 0, 88 },
        size = { 1, -16, 0, 230 },
        text = 'Blue walkers chase the yellow goal and jump the curbs when that is shorter. '
            .. 'The red pillar is a NavObstacle3D.\n\n'
            .. 'Yard (east, weights are set per agent): orange Jumper drops off the platform (jump 0.3); '
            .. 'yellow Hiker never jumps and takes the stairs or ramp; green Walker avoids the pond '
            .. '(water 50) while blue Wader wades through (water 1); purple Climber uses the '
            .. 'NavLink3D ladder (climb 0.5).\n\n'
            .. 'Orange arcs = jump links, magenta = the ladder.',
        fontSize = 13,
    }, panel)
end

return Interface
