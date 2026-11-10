local ipairs = require('source.engine.math.array').ipairs

local Interface = {}

function Interface.create(self)
    self.focusButton = self.scene.ui:button({
        _viewportAuthored = true,
        position = { 0, 12, 0, 66 },
        size = { 0, 180, 0, 38 },
        text = 'Focus spawn controls',
        textScaled = true,
        maxTextSize = 15,
        backgroundColor = { 0.09, 0.2, 0.29 },
    }, self.scene.ui.content)
    self.focusButton:connect('press', function()
        local p = self.board.position
        self.scene.camera.position = { p[1], p[2], p[3] - 110 }
        self.scene.camera.rotation = { 0, 0, 0 }
        self.scene.input:reset()
    end)
    local ui = self.board.ui
    local panel =
        ui:container({ size = { 1, 0, 1, 0 }, backgroundColor = { 0.035, 0.08, 0.14 } }, self.board)
    require('source.engine.ui.widgets.collapsible').create(
        self.scene,
        panel,
        'Spawn / reset',
        { 0, 6, 0, -42 }
    )
    ui:create('UICorner', { radius = { 0, 16 } }, panel)
    ui:create(
        'UIStroke',
        { target = 'Border', color = { 0.3, 0.8, 1 }, thickness = { 0, 2 } },
        panel
    )
    ui:text({
        position = { 0, 12, 0, 10 },
        size = { 1, -24, 0, 44 },
        text = 'Collision box',
        textScaled = true,
        maxTextSize = 26,
    }, panel)
    local buttons = {
        {
            'Start',
            function()
                self.running = true
            end,
        },
        {
            'Stop',
            function()
                self.running = false
            end,
        },
        {
            'Spawn one',
            function()
                self:spawn()
            end,
        },
        {
            'Reset',
            function()
                self:reset()
            end,
        },
    }
    for i, b in ipairs(buttons) do
        local button = ui:button({
            position = { 0, 15, 0, 54 + (i - 1) * 43 },
            size = { 1, -30, 0, 40 },
            text = b[1],
            backgroundColor = { 0.1, 0.24, 0.34 },
        }, panel)
        if b[2] then
            button:connect('press', b[2])
        end
        ui:create('UICorner', { radius = { 0, 8 } }, button)
    end
    self.count = ui:text({
        position = { 0, 10, 1, -48 },
        size = { 1, -20, 0, 40 },
        text = 'Bodies: 5',
        fontSize = 18,
    }, panel)
end

return Interface
