local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(state)
    local scene, ui = state.scene, state.scene.ui
    local panel = ui:container({
        _viewportAuthored = true,
        name = 'IKControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 270, 0, 196 },
        backgroundColor = Theme.panel,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, Theme.corner } }, panel)
    local Content = require('scene.scripts.content')
    local solver = ui:button({
        position = { 0, 8, 0, 8 },
        size = { 1, -16, 0, 32 },
        text = 'Arm solver: ' .. Content.armTypes[1],
    }, panel)
    solver.onPress = function()
        local index = state.armType % #Content.armTypes + 1
        state:setArmType(index)
        solver.text = 'Arm solver: ' .. Content.armTypes[index]
    end
    local levels, index = { 1, 0.5, 0 }, 1
    local influence = ui:button({
        position = { 0, 8, 0, 48 },
        size = { 1, -16, 0, 32 },
        text = 'IK influence: 100%',
    }, panel)
    influence.onPress = function()
        index = index % #levels + 1
        state:setInfluence(levels[index])
        influence.text = ('IK influence: %d%%'):format(levels[index] * 100)
    end
    local debug = true
    local toggle = ui:button({
        position = { 0, 8, 0, 88 },
        size = { 1, -16, 0, 32 },
        text = 'IK debug: on',
    }, panel)
    toggle.onPress = function()
        debug = not debug
        state:setDebug(debug)
        toggle.text = 'IK debug: ' .. (debug and 'on' or 'off')
    end
    ui:create('Label', {
        position = { 0, 8, 0, 128 },
        size = { 1, -16, 0, 60 },
        text = 'Both hands follow the red ball; elbows bend toward the yellow hints. '
            .. 'Select an InverseKinematics3D node in the editor to change its type.',
        fontSize = 13,
    }, panel)
end

return Interface
