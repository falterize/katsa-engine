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
        }, self.toolbar)
        if callback then
            node:connect('press', callback)
        end
        row = row + 1
        self.toolbar.length = row * 52 + 12
        return node
    end
    button('DirectionalLight3D ON/OFF', 250, function()
        self.directionalShadow.enabled = not self.directionalShadow.enabled
    end)
    button('Directional fill ON/OFF', 350, function()
        self.directionalFill.enabled = not self.directionalFill.enabled
    end)
    button('Spot / Point', 450, function()
        self.shadowSpot.castShadow = not self.shadowSpot.castShadow
        self.shadowPoint.castShadow = not self.shadowSpot.castShadow
    end)
    button('Shadows ON/OFF', 650, function()
        scene.world.environment.shadows.enabled = not scene.world.environment.shadows.enabled
    end)
    button('Caster motion', 850, function(n)
        self.shadowMotion = not self.shadowMotion
        n.text = self.shadowMotion and 'Motion: ON' or 'Motion: OFF'
    end)
    ui:text({
        position = { 0, 8, 0, 270 },
        size = { 1, -16, 0, 88 },

        text = 'Enable both directional sources to compare independent cascades. Rotation '
            .. 'controls their rays; camera movement keeps local maps cached.',
        fontSize = 15,
    }, self.toolbar)
    self.toolbar.length = 366
    self.toolbar.automaticLength = true
    self.toolbar.contentPadding = 8
    self.toolbar.size = { 0, math.min(340, ui.width - 24), 0.45, -24 }
    self.toolbarToggle =
        require('source.engine.ui.widgets.collapsible').create(scene, self.toolbar, 'Lab controls')
end

return Interface
