local UI = require('source.engine.ui')

local Interface = {}

function Interface.create(self)
    local scene, ui = self.scene, self.scene.ui
    self.toolbar = ui:scroll({
        _viewportAuthored = true,
        name = 'Lab controls',
        position = { 0, 12, 0, 112 },
        size = { 0, 340, 0.45, -24 },
        length = 52,
        backgroundColor = { 0.035, 0.065, 0.105 },
    }, ui.content)
    local row = 0

    local function button(text, x, callback)
        local node = ui:button({
            position = { 0, 8, 0, row * 52 + 6 },
            size = { 1, -16, 0, 44 },
            text = text,
            fontSize = 17,
            backgroundColor = { 0.085, 0.135, 0.19 },
            onPress = callback,
        }, self.toolbar)
        row = row + 1
        self.toolbar.length = row * 52 + 12
        return node
    end
    button('Active camera', 250, function()
        scene.camera =
            scene.world:setCamera(scene.camera == self.primary and self.alternate or self.primary)
    end)
    button('Camera3D layer group', 450, function()
        scene.camera.layerGroup = scene.camera.layerGroup == 'Default' and 'SceneCamera'
            or 'Default'
    end)
    local panel = ui:create('ScrollFrame', {
        size = { 0, 260, 0, 280 },
        position = UI.udim2(1, -28, 0.5, 0),
        anchorPoint = { 1, 0.5 },

        length = 640,
        backgroundColor = { 0.04, 0.08, 0.14 },
        backgroundTransparency = 1 - 0.92,
    }, ui.content)
    require('source.engine.ui.widgets.collapsible').create(
        scene,
        panel,
        'Node properties',
        { 1, -192, 0, 66 }
    )
    ui:create('UICorner', { radius = { 0, 14 } }, panel)
    for i = 1, 10 do
        local row = ui:create('Button', {
            position = { 0, 12, 0, (i - 1) * 62 + 10 },
            size = { 0, 236, 0, 52 },

            text = 'Node property ' .. i,
            fontSize = 22,
            backgroundColor = { 0.1, 0.25, 0.35 },
            backgroundTransparency = 1 - 1,
            onPress = function(n)
                n.text = 'Pressed ' .. i
            end,
        }, panel)
        ui:create('UICorner', { radius = { 0, 12 } }, row)
    end
    self.toolbar.automaticLength = true
    self.toolbar.contentPadding = 8
    self.toolbar.size = { 0, math.min(340, ui.width - 24), 0.45, -24 }
    self.toolbarToggle =
        require('source.engine.ui.widgets.collapsible').create(scene, self.toolbar, 'Lab controls')
end

return Interface
