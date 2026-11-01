local Theme = require('source.engine.ui.theme')
local Interface = {}

function Interface.create(state)
    local scene, ui = state.scene, state.scene.ui
    state.status = ui:text({
        name = 'RunnerStatus',
        position = { 0.5, 0, 0, 112 },
        anchorPoint = { 0.5, 0 },
        size = { 1, -24, 0, 30 },
        text = 'Ability Runner 2D | Checkpoint 0/3',
        textScaled = true,
        maxTextSize = 16,
        backgroundColor = Theme.panel,
        backgroundTransparency = 0.2,
        zIndex = 10,
    }, ui.content)
    local panel = ui:scroll({
        name = 'RunnerControls',
        position = { 0, 12, 0, 155 },
        size = { 0, 280, 0, 210 },
        length = 260,
        visible = false,
        backgroundColor = Theme.panel,
        zIndex = 20,
    }, ui.content)
    state.controlsPanel = panel
    require('source.engine.ui.widgets.collapsible').create(scene, panel, 'Runner 2D / controls')
    ui:text({
        position = { 0, 8, 0, 8 },
        size = { 1, -16, 0, 92 },
        text = 'A/D or touch: move\nSpace: jump twice | Shift: dash\nC: slide | R: respawn\nGold '
            .. 'crystals save checkpoints.\nRed lava resets to the last checkpoint.',
        textScaled = true,
        maxTextSize = 14,
    }, panel)
    ui:button({
        position = { 0, 8, 0, 110 },
        size = { 1, -16, 0, 36 },
        text = 'Respawn checkpoint',
        onPress = function()
            state.controller:request('respawn')
        end,
    }, panel)
    ui:button({
        position = { 0, 8, 0, 154 },
        size = { 1, -16, 0, 36 },
        text = 'Physics debug ON/OFF',
        onPress = function()
            state.physics.debug.enabled = not state.physics.debug.enabled
        end,
    }, panel)
    ui:button({
        position = { 0, 8, 0, 198 },
        size = { 1, -16, 0, 36 },
        text = 'Player visual layer ON/OFF',
        onPress = function()
            local groups = scene.world.layerGroups
            groups:set(
                ui.currentCamera.layerGroup,
                'Player',
                not groups:interacts(ui.currentCamera.layerGroup, 'Player')
            )
        end,
    }, panel)
    for i, action in ipairs({ 'Jump', 'Dash', 'Slide' }) do
        ui:button({
            name = action .. 'Action',
            position = { 1, -12, 1, -18 - (i - 1) * 52 },
            anchorPoint = { 1, 1 },
            size = { 0, 112, 0, 44 },
            text = action,
            backgroundColor = Theme.accent,
            radius = Theme.corner,
            zIndex = 20,
            onPress = function()
                state.controller:request(action:lower())
            end,
        }, ui.content)
    end
    for i, direction in ipairs({ 'Left', 'Right' }) do
        local held = direction == 'Left' and state.touchLeft or state.touchRight
        local function release(_, _, _, id)
            held[id or 'mouse'] = nil
        end
        ui:button({
            name = direction .. 'Action',
            position = { 0, 12 + (i - 1) * 100, 1, -18 },
            anchorPoint = { 0, 1 },
            size = { 0, 88, 0, 54 },
            text = direction,
            backgroundColor = Theme.button,
            radius = Theme.corner,
            zIndex = 20,
            onPress = function(_, _, _, id)
                held[id or 'mouse'] = true
            end,
            onRelease = release,
            onCancel = release,
        }, ui.content)
    end
end

return Interface
