local ipairs = require('source.engine.math.array').ipairs

local Interface = {}

function Interface.create(self)
    local ui = self.scene.ui
    local root = ui:container({
        name = 'UIGallery',
        _viewportAuthored = true,
        position = { 0.5, 0, 0.6, 0 },
        size = { 0.82, 0, 0.65, 0 },
        anchorPoint = { 0.5, 0.5 },
        backgroundColor = { 0.035, 0.065, 0.12 },
    }, ui.content)
    self.root = root
    require('source.engine.ui.widgets.collapsible').create(self.scene, root, 'UI Gallery')
    ui:create('UICorner', { radius = { 0, 18 } }, root)
    ui:create(
        'UIStroke',
        { target = 'Border', thickness = { 0, 2 }, color = { 0.3, 0.7, 1 } },
        root
    )
    ui:text({
        position = { 0, 20, 0, 10 },
        size = { 1, -40, 0, 42 },
        text = 'UI / Scale + Offset + AnchorPoint',
        textScaled = true,
        maxTextSize = 28,
    }, root)
    local left = ui:scroll({
        position = { 0, 18, 0, 65 },
        size = { 0.48, -20, 1, -85 },
        automaticLength = true,
        contentPadding = 30,
        backgroundColor = { 0.06, 0.11, 0.19 },
    }, root)
    ui:text({
        position = { 0, 12, 0, 10 },
        size = { 1, -24, 0, 90 },
        text = '<b>Bold</b> <i>Italic</i> <u>Underline</u>\n<font color="#55CCFF">Blue</font> '
            .. '<s>Strike</s>\n&lt;escaped&gt;',
        richText = true,
        textScaled = true,
        maxTextSize = 22,
        fontSize = 22,
    }, left)
    local gradient = ui:text({
        position = { 0, 12, 0, 115 },
        size = { 1, -24, 0, 70 },
        text = 'Gradient + TextScaled',
        textScaled = true,
        maxTextSize = 36,
        backgroundColor = { 0.1, 0.2, 0.3 },
    }, left)
    ui:create('Ramp', {
        target = 'Text',
        points = {
            { time = 0, value = { 1, 0.3, 0.4, 1 } },
            { time = 1, value = { 0.3, 1, 1, 1 } },
        },
    }, gradient)
    ui:create('UICorner', { radius = { 0, 14 } }, gradient)
    ui:create(
        'UIStroke',
        { target = 'Border', thickness = { 0, 2 }, color = { 0.6, 0.8, 1 } },
        gradient
    )
    ui:create('UIStroke', { target = 'Text', thickness = { 0, 1 }, color = { 0, 0, 0 } }, gradient)
    self.button = ui:button({
        position = { 0, 12, 0, 205 },
        size = { 1, -24, 0, 50 },
        text = 'Click / tap: 0',
        backgroundColor = { 0.1, 0.32, 0.45 },
    }, left)
    self.button:connect('press', function()
        self.presses = self.presses + 1
        self.button.text = 'Click / tap: ' .. self.presses
    end)
    self.value = ui:text({
        position = { 0, 12, 0, 270 },
        size = { 1, -24, 0, 35 },
        text = 'Slider: 50%',
        fontSize = 20,
    }, left)
    do
        local node = ui:slider({
            position = { 0, 12, 0, 312 },
            size = { 1, -24, 0, 40 },
            value = 0.5,
        }, left)
        node:connect('changed', function(v)
            self.value.text = string.format('Slider: %.0f%%', v * 100)
        end)
    end
    self.fitImage = ui:image({
        name = 'FitModeExample',
        fitMode = 'Fit',
        pixelate = true,
        tileSize = { 0, 48, 0, 48 },
        position = { 0, 12, 0, 375 },
        size = { 1, -24, 0, 130 },
        image = 'scene://textures/litter.png',
        backgroundColor = { 0.15, 0.2, 0.3 },
        backgroundTransparency = 0.25,
        imageColor = { 1, 0.7, 0.4 },
        imageTransparency = 0.1,
    }, left)
    local modes = { 'Fit', 'Crop', 'Stretch', 'Tile' }
    self.fitIndex = 1
    do
        local node = ui:button({
            position = { 0, 12, 0, 510 },
            size = { 1, -24, 0, 36 },
            text = 'Cycle FitMode / Pixel',
            textScaled = true,
            maxTextSize = 16,
        }, left)
        node:connect('press', function()
            self.fitIndex = self.fitIndex % 4 + 1
            self.fitImage.imageMode = self.fitIndex == 4 and 'Tiles' or 'Decal'
            self.fitImage.fitMode = self.fitIndex == 4 and 'Stretch' or modes[self.fitIndex]
            self.fitImage.pixelate = not self.fitImage.pixelate
        end)
    end
    local group = ui:canvasGroup(
        { position = { 0, 12, 0, 556 }, size = { 1, -24, 0, 170 }, transparency = 0.35 },
        left
    )
    self.opacityGroup = group
    ui:text({
        size = { 1, 0, 1, 0 },
        text = 'CanvasGroup opacity\nScrolled and clipped',
        textScaled = true,
        backgroundColor = { 0.15, 0.35, 0.5 },
    }, group)
    do
        local node = ui:button({
            position = { 0, 12, 0, 735 },
            size = { 1, -24, 0, 44 },
            text = 'Text gradient: fill / outline',
            textScaled = true,
            maxTextSize = 16,
        }, left)
        node:connect('press', function()
            self.outlineOnly = not self.outlineOnly
            for _, node in ipairs(gradient.children) do
                if node:isA('Ramp') and node.target == 'Text' then
                    for _, point in ipairs(node.bindings.textTransparency) do
                        point.value = self.outlineOnly and 1 or 0
                    end
                elseif node:isA('UIStroke') and node.target == 'Text' then
                    node.color = { 1, 0.4, 0.2 }
                    node.thickness = { 0, 3 }
                end
            end
        end)
    end
    local right = ui:scroll({
        position = { 0.5, 0, 0, 65 },
        size = { 0.5, -18, 1, -85 },
        automaticLength = true,
        contentPadding = 20,
        backgroundColor = { 0.06, 0.11, 0.19 },
    }, root)
    self.left, self.right = left, right
    require('scene.scripts.ui.examples.textBoxes').create(self, left)
    require('scene.scripts.ui.examples.scrolling').create(ui, right)
    ui:text({
        position = { 0, 10, 0, 10 },
        size = { 1, -20, 0, 45 },
        text = 'relativeTo: XY / XX / YY',
        textScaled = true,
    }, right)
    for i, mode in ipairs({ 'XY', 'XX', 'YY' }) do
        local box = ui:container({
            position = { 0, 12, 0, 65 + (i - 1) * 105 },
            size = { 0.18, 0, 0.18, 0 },
            sizeRelativeTo = mode,
            backgroundColor = { 0.12 * i, 0.35, 0.6 },
        }, right)
        ui:text({ size = { 1, 0, 1, 0 }, text = mode, textScaled = true, maxTextSize = 22 }, box)
        ui:text({
            position = { 0.4, 0, 0, 65 + (i - 1) * 105 },
            size = { 0.58, 0, 0, 75 },
            text = mode
                .. ' uses '
                .. (
                    mode == 'XY' and 'each parent axis'
                    or mode == 'XX' and 'parent width'
                    or 'parent height'
                ),
            textScaled = true,
            maxTextSize = 20,
        }, right)
    end
end

return Interface
