local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(state)
    local scene, ui = state.scene, state.scene.ui
    local panel = ui:container({
        _viewportAuthored = true,
        name = 'TreeControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 270, 0, 232 },
        backgroundColor = Theme.panel,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, Theme.corner } }, panel)
    local speed = 0
    local speedButton = ui:button({
        position = { 0, 8, 0, 8 },
        size = { 1, -16, 0, 32 },
        text = 'Speed: 0.00',
    }, panel)
    speedButton:connect('press', function()
        speed = speed >= 1 and 0 or speed + 0.25
        state:setSpeed(speed)
        speedButton.text = ('Speed: %.2f'):format(speed)
    end)
    do
        local node = ui:button({
            position = { 0, 8, 0, 48 },
            size = { 1, -16, 0, 32 },
            text = 'Crouch ON / OFF',
        }, panel)
        node:connect('press', function()
            state:toggleCrouch()
        end)
    end
    do
        local node = ui:button({
            position = { 0, 8, 0, 88 },
            size = { 1, -16, 0, 32 },
            text = 'Jump',
        }, panel)
        node:connect('press', function()
            state:jump()
        end)
    end
    local status = ui:create('Label', {
        position = { 0, 8, 0, 130 },
        size = { 1, -16, 0, 44 },
        text = state:describe(),
        fontSize = 14,
    }, panel)
    ui:create('Label', {
        position = { 0, 8, 0, 178 },
        size = { 1, -16, 0, 48 },
        text = 'Speed steps 0 to 1. Buttons only set AnimationTree parameters; the graph blends and switches states.',
        fontSize = 12,
    }, panel)
    state.refreshStatus = function()
        local text = state:describe()
        if status.text ~= text then
            status.text = text
        end
    end
end

return Interface
