local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(state)
    local scene, ui = state.scene, state.scene.ui
    local panel = ui:container({
        _viewportAuthored = true,
        name = 'IKControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 250, 0, 150 },
        backgroundColor = Theme.panel,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, Theme.corner } }, panel)
    local levels = { 1, 0.5, 0 }
    local index = 1
    local influence = ui:button({
        position = { 0, 8, 0, 8 },
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
        position = { 0, 8, 0, 48 },
        size = { 1, -16, 0, 32 },
        text = 'IK debug: on',
    }, panel)
    toggle.onPress = function()
        debug = not debug
        state:setDebug(debug)
        toggle.text = 'IK debug: ' .. (debug and 'on' or 'off')
    end
    ui:create('TextLabel', {
        position = { 0, 8, 0, 90 },
        size = { 1, -16, 0, 48 },
        text = 'Red: arm + head. Blue: left arm (FABRIK). Green: left leg (CCD).',
        fontSize = 14,
    }, panel)
end

return Interface
