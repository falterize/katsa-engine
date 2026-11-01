local ipairs = require('source.engine.math.array').ipairs
local Theme = require('source.engine.ui.theme')
local Tween = require('source.engine.animation.tween')

local Interface = {}

function Interface.create(self)
    local ui = self.scene.ui
    self.panel = ui:container({
        _viewportAuthored = true,
        name = 'AnimationControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 290, 0.66, -124 },
        backgroundColor = Theme.panel,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, Theme.corner } }, self.panel)
    require('source.engine.ui.widgets.collapsible').create(self.scene, self.panel, 'Ramp / Tween')
    local list = ui:scroll({
        position = { 0, 8, 0, 8 },
        size = { 1, -16, 1, -16 },
        automaticLength = true,
        contentPadding = 12,
    }, self.panel)
    local y = 0

    local function button(text, callback)
        ui:button({
            position = { 0, 0, 0, y },
            size = { 1, 0, 0, 36 },
            text = text,
            fontSize = 13,
            backgroundColor = Theme.button,
            radius = Theme.corner,
            onPress = callback,
        }, list)
        y = y + 42
    end
    button('Prepared Ramp: play', function()
        self.ramp:play()
    end)
    for _, method in ipairs({ 'pause', 'resume', 'stop' }) do
        button('Ramp: ' .. method, function()
            self.ramp[method](self.ramp)
        end)
    end
    button('Ramp Playing true / false', function()
        self.ramp.Playing = not self.ramp.Playing
    end)
    button('Ramp Enabled true / false', function()
        self.ramp.Enabled = not self.ramp.Enabled
    end)
    button('Edit Ramp / curves', function()
        self.scene.workspace:toggle(true)
        self.scene.workspace:select(self.ramp)
    end)
    button('World TimeScale 1 / .25 / 0', function()
        local root = self.scene.world.root
        root.timeScale = root.timeScale == 1 and 0.25 or root.timeScale == 0.25 and 0 or 1
    end)
    self.fade = ui:container(
        { position = { 0, 0, 0, y }, size = { 1, 0, 0, 66 }, backgroundColor = { 0.15, 0.35, 0.5 } },
        list
    )
    ui:create('Ramp', {
        name = 'ColorRamp',
        interpolation = 'Curve',
        points = {
            { time = 0, value = { 1, 0.3, 0.1, 1 }, outgoing = { 0.2, 0 } },
            { time = 1, value = { 0.1, 0.7, 1, 0.3 }, incoming = { 0.8, 1 } },
        },
    }, self.fade)
    y = y + 72
    self.tween = Tween.new(
        self.fade,
        { playbackTime = 1, reverses = true, repeatCount = 1 },
        { backgroundTransparency = 0.75 }
    )
    button('Programmatic multi-cycle Tween', function()
        self.tween:play()
    end)
    self.status = ui:text({
        position = { 0, 0, 0, y },
        size = { 1, 0, 0, 70 },
        text = 'Prepared Ramp is stopped until play()',
        fontSize = 12,
    }, list)
    for _, event in ipairs({ 'Started', 'Completed', 'Stopped', 'Resumed' }) do
        self.ramp:connect(event, function()
            self.status.text = 'Ramp event: ' .. event
        end)
    end
    self.scene.world:create(
        'ParticleEmitter3D',
        { name = 'RampParticles', position = { 55, 0, 60 }, rate = 12, startSize = { 3, 5 } }
    )
end

return Interface
