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
    button('Simulation pause / resume', 0, function()
        scene.physics.paused = not scene.physics.paused
    end)
    button('Reset scene', 0, function()
        scene.manager:switch(require('source.game.runtime.game').new, self.zone)
    end)
    ui:text({
        position = { 0, 8, 0, 114 },
        size = { 1, -16, 0, 76 },
        text = 'Stack, bouncing ball and pendulum. Select Mesh3D / Body3D / Collider3D in '
            .. 'Workspace for physical settings.',
        textScaled = true,
        maxTextSize = 15,
    }, self.toolbar)
    self.toolbar.length = 198
    if self.independentCollider then
        row = 4
        button('Collider3D: sphere / box', 0, function()
            self.independentCollider.shape = self.independentCollider.shape == 'sphere' and 'box'
                or 'sphere'
        end)
        button('Interpolation ON/OFF', 0, function(n)
            scene.physics:setInterpolation(not scene.physics.interpolate)
            n.text = scene.physics.interpolate and 'Interpolation: ON' or 'Interpolation: OFF'
        end)
        button('Reset independent body', 0, function()
            self.independentBody.physics:teleport({ -130, 75, 80 })
            self.independentBody.physics:setVelocity({ 0, 0, 0 })
        end)
    end
    self.toolbar.automaticLength = true
    self.toolbar.contentPadding = 8
    self.toolbar.size = { 0, math.min(340, ui.width - 24), 0.45, -24 }
    self.toolbarToggle =
        require('source.engine.ui.widgets.collapsible').create(scene, self.toolbar, 'Lab controls')
end

return Interface
