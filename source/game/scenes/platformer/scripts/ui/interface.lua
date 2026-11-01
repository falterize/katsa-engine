local ipairs = require('source.engine.math.array').ipairs
local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(lab)
    local scene, ui = lab.scene, lab.scene.ui
    lab.status = ui:text({
        _viewportAuthored = true,
        name = 'RunnerStatus',
        position = { 0.5, 0, 0, 112 },
        anchorPoint = { 0.5, 0 },
        size = { 1, -24, 0, 30 },
        text = 'Crystals 0/' .. #lab.pickups,
        textScaled = true,
        maxTextSize = 15,
        backgroundTransparency = 0.2,
        backgroundColor = Theme.panel,
        zIndex = 10,
    }, ui.content)
    local actions = { 'Jump', 'Dash', 'Slide' }
    for i, action in ipairs(actions) do
        ui:button({
            _viewportAuthored = true,
            name = action .. 'Action',
            position = { 1, -12, 1, -18 - (i - 1) * 52 },
            anchorPoint = { 1, 1 },
            size = { 0, 112, 0, 44 },
            textScaled = true,
            maxTextSize = 16,
            text = action,
            backgroundColor = Theme.accent,
            radius = Theme.corner,
            zIndex = 20,
            onPress = function()
                scene.input:trigger(action)
            end,
        }, ui.content)
    end
    local panel = ui:scroll({
        _viewportAuthored = true,
        name = 'RunnerControls',
        position = { 0, 12, 0, 155 },
        size = { 0, 245, 0, 180 },
        length = 180,
        visible = false,
        backgroundColor = Theme.panel,
        zIndex = 10,
    }, ui.content)
    lab.controlsPanel = panel
    ui:create('UICorner', { radius = { 0, Theme.corner } }, panel)
    require('source.engine.ui.widgets.collapsible').create(scene, panel, 'Runner / systems')
    ui:text({
        position = { 0, 8, 0, 8 },
        size = { 1, -16, 0, 54 },
        textScaled = true,
        maxTextSize = 14,
        text = 'WASD / touch: move\nSpace: jump twice | Shift: dash\nC: slide | Crystals: '
            .. 'checkpoint',
        backgroundTransparency = 1,
    }, panel)
    ui:button({
        position = { 0, 8, 0, 68 },
        size = { 1, -16, 0, 30 },
        fontSize = 13,
        text = 'Blend stone / bricks',
        backgroundColor = Theme.button,
        radius = Theme.corner,
        onPress = function()
            lab.materialProgress = 1 - lab.materialProgress
            local Tween = require('source.engine.animation.tween')
            if lab.mixA then
                lab.mixA:stop()
                lab.mixB:stop()
            end
            lab.mixA = Tween.new(
                lab.materialA,
                { playbackTime = 0.8 },
                { transparency = lab.materialProgress }
            )
            lab.mixB = Tween.new(
                lab.materialB,
                { playbackTime = 0.8 },
                { transparency = 1 - lab.materialProgress }
            )
            lab.mixA:play()
            lab.mixB:play()
        end,
    }, panel)
    ui:button({
        position = { 0, 8, 0, 104 },
        size = { 1, -16, 0, 30 },
        fontSize = 13,
        text = 'Shadows Standard / Realistic',
        backgroundColor = Theme.button,
        radius = Theme.corner,
        onPress = function()
            local s = scene.world.environment.shadows
            s.mode = s.mode == 'Standard' and 'Realistic' or 'Standard'
        end,
    }, panel)
    ui:button({
        position = { 0, 8, 0, 140 },
        size = { 1, -16, 0, 26 },
        fontSize = 13,
        text = 'Respawn checkpoint',
        backgroundColor = Theme.button,
        radius = Theme.corner,
        onPress = function()
            lab:respawn()
        end,
    }, panel)
end

return Interface
