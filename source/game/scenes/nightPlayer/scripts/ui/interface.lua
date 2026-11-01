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
    local function inheritLook(camera)
        local rotation = scene.camera:getLookRotation()
        camera._controller.pitch, camera._controller.yaw = rotation[1], rotation[2]
    end
    button('First person', 250, function()
        inheritLook(self.first)
        scene.camera = scene.world:setCamera(self.first, 0.25)
        scene.character.camera = scene.camera
    end)
    button('Third person', 450, function()
        inheritLook(self.third)
        scene.camera = scene.world:setCamera(self.third, 0.25)
        scene.character.camera = scene.camera
    end)
    button('Flashlight', 650, function()
        self.flashlight.enabled = not self.flashlight.enabled
    end)
    self.dayLabel = ui:text({
        position = { 0, 8, 0, 166 },
        size = { 1, -16, 0, 36 },

        text = 'time of day: 00:00',
        fontSize = 20,
    }, self.toolbar)
    self.daySlider = ui:slider({
        position = { 0, 8, 0, 208 },
        size = { 1, -16, 0, 44 },

        min = 0,
        max = 24,
        value = self.dayHour,
        backgroundColor = { 0.04, 0.1, 0.16 },
        backgroundTransparency = 1 - 0.9,
        onChange = function(value)
            self:setTimeOfDay(value)
        end,
    }, self.toolbar)
    ui:text({
        position = { 0, 8, 0, 268 },
        size = { 1, -16, 0, 52 },
        text = 'Aim at the orange cube.\nInteract / F toggles the flashlight.\nTap the cube also '
            .. 'works.',
        fontSize = 12,
        align = 'left',
    }, self.toolbar)
    self.toolbar.length = 326
    self.jumpButton = ui:create('Button', {
        _viewportAuthored = true,
        position = { 1, -14, 1, -150 },
        size = { 0, 90, 0, 48 },
        anchorPoint = { 1, 1 },

        text = 'JUMP',
        fontSize = 24,
        backgroundColor = { 0.12, 0.3, 0.45 },
        backgroundTransparency = 1 - 0.95,
        onPress = function()
            scene.input:trigger('Jump')
        end,
    }, ui.content)
    ui:button({
        _viewportAuthored = true,
        position = { 1, -14, 1, -204 },
        size = { 0, 90, 0, 42 },
        anchorPoint = { 1, 1 },
        text = 'INTERACT',
        fontSize = 14,
        backgroundColor = { 0.085, 0.135, 0.19 },
        onPress = function()
            scene.input:trigger('Interact')
        end,
    }, ui.content)
    self.toolbar.automaticLength = true
    self.toolbar.contentPadding = 8
    self.toolbar.size = { 0, math.min(340, ui.width - 24), 0.45, -24 }
    self.toolbarToggle =
        require('source.engine.ui.widgets.collapsible').create(scene, self.toolbar, 'Lab controls')
end

return Interface
