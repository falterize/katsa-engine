local ipairs = require('source.engine.math.array').ipairs

local Interface = {}

function Interface.create(self)
    for _, panel in ipairs(self.panels) do
        local ui = panel.ui
        local frame =
            ui:container({ size = { 1, 0, 1, 0 }, backgroundColor = { 0.08, 0.15, 0.23 } }, panel)
        ui:create('UICorner', { radius = { 0, 20 } }, frame)
        ui:create('Ramp', {
            rotation = 45,
            points = {
                { time = 0, value = { 0.08, 0.22, 0.35, 1 } },
                {
                    time = 1,
                    value = { 0.2, 0.1, 0.3, 1 },
                },
            },
        }, frame)
        ui:create(
            'UIStroke',
            { target = 'Border', thickness = { 0, 3 }, color = { 0.4, 0.8, 1 } },
            frame
        )
        ui:text({
            position = { 0.5, 0, 0.25, 0 },
            size = { 0.9, 0, 0.28, 0 },
            anchorPoint = { 0.5, 0.5 },
            text = panel.name,
            textScaled = true,
            maxTextSize = 40,
        }, frame)
        local b = ui:button({
            position = { 0.5, 0, 0.68, 0 },
            size = { 0.85, 0, 0.28, 0 },
            anchorPoint = { 0.5, 0.5 },
            text = 'Press / touch',
            textScaled = true,
            maxTextSize = 30,
            backgroundColor = { 0.2, 0.45, 0.6 },
            onPress = function()
                self.clicks = self.clicks + 1
            end,
        }, frame)
        ui:create('UICorner', { radius = { 0, 14 } }, b)
        ui:create('UIStroke', { target = 'Text', thickness = { 0, 1 }, color = { 0, 0, 0 } }, b)
    end
    self.overlay.ui:text({
        size = { 1, 0, 1, 0 },
        text = 'onTop = true',
        backgroundColor = { 0.5, 0.16, 0.1 },
        backgroundTransparency = 0.2,
        textScaled = true,
    }, self.overlay)
    local board = self.attachmentBoard
    self.attachmentTitle = board.ui:text({
        position = { 0, 8, 0, 4 },
        size = { 1, -16, 0, 36 },
        text = 'Attachment3D / Support offset',
        textScaled = true,
        maxTextSize = 24,
        backgroundColor = { 0.04, 0.11, 0.16 },
    }, board)
    self.attachmentButton = board.ui:button({
        position = { 0, 8, 0, 44 },
        size = { 1, -16, 0, 60 },
        text = 'Clicks: 0',
        textScaled = true,
        maxTextSize = 22,
        backgroundColor = { 0.1, 0.32, 0.4 },
        onPress = function()
            self.attachmentClicks = self.attachmentClicks + 1
            self.attachmentButton.text = 'Clicks: ' .. self.attachmentClicks
        end,
    }, board)
    board.ui:button({
        position = { 0, 8, 0, 110 },
        size = { 1, -16, 0, 60 },
        text = 'Switch offset',
        textScaled = true,
        maxTextSize = 20,
        backgroundColor = { 0.13, 0.2, 0.32 },
        onPress = function()
            self.offsetMode = self.offsetMode == 'Support' and 'World3D' or 'Support'
            board.offset = self.offsetMode == 'Support' and { 0, 18, 0 } or { 0, 0, 0 }
            board.offsetWorldSpace = self.offsetMode == 'World3D' and { 0, 18, 0 } or { 0, 0, 0 }
            self.attachmentTitle.text = 'Attachment3D / ' .. self.offsetMode .. ' offset'
        end,
    }, board)
    local ui = self.scene.ui
    local controls = ui:container({
        _viewportAuthored = true,
        name = 'SurfaceControls',
        visible = false,
        position = { 0, 12, 0, 112 },
        size = { 0, 260, 0, 150 },
    }, ui.content)
    require('source.engine.ui.widgets.collapsible').create(self.scene, controls, 'Surface controls')
    ui:button({
        position = { 0, 4, 0, 4 },
        size = { 1, -8, 0, 44 },
        text = 'Decal3D size: 75% / 40%',
        textScaled = true,
        maxTextSize = 18,
        backgroundColor = { 0.1, 0.25, 0.35 },
        onPress = function()
            local factor = self.litter.size[1] == 0.75 and 0.4 or 0.75
            self.litter.size = { factor, 0, factor, 0 }
        end,
    }, controls)
    ui:button({
        position = { 0, 4, 0, 54 },
        size = { 1, -8, 0, 42 },
        text = 'Panel extent: support / fixed',
        textScaled = true,
        maxTextSize = 16,
        backgroundColor = { 0.1, 0.25, 0.35 },
        onPress = function()
            self.extentFixed = not self.extentFixed
            board.extentsOffset = self.extentFixed and { 0, 0, 0 } or { 0, 1, 0 }
            board.extentsOffsetWorldSpace = self.extentFixed and { 0, 1, 0 } or { 0, 0, 0 }
        end,
    }, controls)
    ui:button({
        position = { 0, 4, 0, 100 },
        size = { 1, -8, 0, 42 },
        text = 'Panel tilt: on / off',
        textScaled = true,
        maxTextSize = 16,
        backgroundColor = { 0.1, 0.25, 0.35 },
        onPress = function()
            board.rotation = board.rotation[1] == 0 and { 12, 20, 8 } or { 0, 0, 0 }
        end,
    }, controls)
    self.status = self.scene.ui:text({
        position = { 0.5, 0, 1, -35 },
        size = { 1, -24, 0, 48 },
        anchorPoint = { 0.5, 0.5 },
        text = 'Walk around the six local faces. Touch a panel.',
        fontSize = 20,
    }, self.scene.ui.content)
end

return Interface
