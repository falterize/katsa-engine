local BillboardUI = require('source.engine.ui')

local BillboardDemo = {}

function BillboardDemo.build(scene)
    local world = scene.world

    local function panel(name, position, size, mode, onTop, color, title, subtitle)
        local b = BillboardUI.newBillboard(world, {
            name = name,
            position = position,
            size = size,
            sizeMode = mode,
            onTop = onTop,
            maxDistance = 320,
        })
        b.ui:create(
            'Frame',
            { position = { 0, 0, 0, 0 }, size = { 0, 240, 0, 120 }, backgroundColor = color },
            b.ui.content
        )
        b.title = b.ui:create(
            'Label',
            { position = { 0, 0, 0, 12 }, size = { 0, 240, 0, 30 }, text = title, fontSize = 22 },
            b.ui.content
        )
        b.subtitle = b.ui:create('Label', {
            position = { 0, 0, 0, 73 },
            size = { 0, 240, 0, 30 },

            text = subtitle,
            fontSize = 19,
        }, b.ui.content)
        return b
    end
    local fixed = panel(
        'Fixed',
        { -55, 32, 160 },
        { 170, 85 },
        'Screen',
        true,
        { 32 / 255, 68 / 255, 100 / 255, 1 },
        'SCREEN SIZE',
        'Constant screen size'
    )
    local moving = panel(
        'World3D',
        { 55, 32, 160 },
        { 50, 25 },
        'World3D',
        true,
        { 72 / 255, 45 / 255, 110 / 255, 1 },
        'WORLD SIZE',
        'Size follows distance'
    )
    panel(
        'Depth',
        { 0, 0, 45 },
        { 15, 7.5 },
        'World3D',
        false,
        { 170 / 255, 70 / 255, 40 / 255, 1 },
        'OnTop = false',
        'Behind the stone cube'
    )
    panel(
        'OnTop',
        { 40, 0, 50 },
        { 22, 11 },
        'World3D',
        true,
        { 30 / 255, 130 / 255, 100 / 255, 1 },
        'OnTop = true',
        'Visible through objects'
    )
    local button = panel(
        'Button',
        { -65, -18, 140 },
        { 170, 85 },
        'Screen',
        true,
        { 28 / 255, 34 / 255, 48 / 255, 1 },
        'BUTTON / CLICKS',
        'Clicks: 0'
    )
    button.size = { 0, 210, 0, 125 }
    button.subtitle.position = { 0, 0, 0, 96 }
    button.subtitle.size = { 0, 240, 0, 24 }
    local clicks = 0
    do
        local node = button.ui:create('Button', {
            position = { 0, 16, 0, 40 },
            size = { 0, 208, 0, 50 },

            backgroundColor = { 40 / 255, 160 / 255, 230 / 255 },
            backgroundTransparency = 1 - 1,
            text = 'CHANGE SIZE',
            fontSize = 17,
        }, button.ui.content)
        node:connect('press', function()
            clicks = clicks + 1
            button.subtitle.text = 'Clicks: ' .. clicks
            button.dirty = true
            if moving.sizeMode == 'World3D' then
                moving.sizeMode = 'Screen'
                moving.size = { 0, 170, 0, 85 }
                moving.title.text = 'SCREEN SIZE'
            else
                moving.sizeMode = 'World3D'
                moving.size = { 0, 50, 0, 25 }
                moving.title.text = 'WORLD SIZE'
            end
            moving.dirty = true
            scene.audio:play('assets/audio/effects/click.wav', { group = 'ui', timeScaled = false })
        end)
    end
    local image = panel(
        'Image',
        { 65, -24, 170 },
        { 170, 85 },
        'Screen',
        true,
        { 28 / 255, 70 / 255, 65 / 255, 1 },
        'IMAGE + ALPHA',
        'Transparency = 0.25'
    )
    image.transparency = 0.25
    image.ui:create(
        'ImageRect',
        { position = { 0, 94, 0, 44 }, size = { 0, 52, 0, 32 }, image = 'bricks' },
        image.ui.content
    )
    return { fixed = fixed, moving = moving, button = button, image = image }
end

return BillboardDemo
