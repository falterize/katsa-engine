local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(self)
    local scene, ui = self.scene, self.scene.ui
    local panel = ui:scroll({
        _viewportAuthored = true,
        name = 'AnimationPhysicsControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 300, 0.66, -124 },
        length = 570,
        visible = false,
        backgroundColor = Theme.panel,
    }, ui.content)
    require('source.engine.ui.widgets.collapsible').create(scene, panel, 'Animation + physics')
    local y = 8

    local function button(text, fn)
        do
            local node = ui:button({
                position = { 0, 8, 0, y },
                size = { 1, -16, 0, 34 },
                text = text,
                textScaled = true,
                maxTextSize = 14,
                radius = Theme.corner,
            }, panel)
            if fn then
                node:connect('press', fn)
            end
        end
        y = y + 40
    end
    button('Wave: play with FadeIn', function()
        self.tracks.wave:play()
    end)
    button('Wave: stop with FadeOut', function()
        self.tracks.wave:stop()
    end)
    button('Wave Order: 0 / 1 / 2', function()
        self.tracks.wave.order = (self.tracks.wave.order + 1) % 3
    end)
    button('Wave mask: arm / whole rig', function()
        if next(self.tracks.wave.boneMask) then
            self.savedMask = self.tracks.wave.boneMask
            self.tracks.wave.boneMask = {}
        else
            self.tracks.wave.boneMask = self.savedMask or {}
        end
    end)
    button('Rig body: kinematic / dynamic', function()
        self.rigBody.bodyType = self.rigBody.bodyType == 'Kinematic' and 'Dynamic' or 'Kinematic'
    end)
    button('Drop six rolling spheres', function()
        self:dropBalls()
    end)
    button('Physics debug', function()
        scene.physics.debugEnabled = not scene.physics.debugEnabled
    end)
    button('Bone debug', function()
        self.animator.debugEnabled = not self.animator.debugEnabled
    end)
    local label = ui:text({
        position = { 0, 8, 0, y },
        size = { 1, -16, 0, 26 },
        text = 'Animation Speed: 1.00',
        fontSize = 14,
    }, panel)
    y = y + 30
    do
        local node = ui:slider({
            position = { 0, 8, 0, y },
            size = { 1, -16, 0, 36 },
            min = -2,
            max = 3,
            value = 1,
        }, panel)
        node:connect('changed', function(value)
            for _, track in pairs(self.tracks) do
                track.speed = value
            end
            label.text = string.format('Animation Speed: %.2f', value)
        end)
    end
    y = y + 42
    self.info = ui:text({
        position = { 0, 8, 0, y },
        size = { 1, -16, 0, 100 },
        text = 'Same Order blends weights. Higher Order overrides masked bones. Inspect '
            .. 'constraints to choose attachments.',
        fontSize = 13,
        verticalAlign = 'top',
    }, panel)
end

return Interface
