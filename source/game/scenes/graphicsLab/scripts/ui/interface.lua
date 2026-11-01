local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(self)
    local scene, ui = self.scene, self.scene.ui
    local panel = ui:scroll({
        _viewportAuthored = true,
        name = 'MaximumGraphicsControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 280, 0.66, -124 },
        length = 170,
        visible = false,
        backgroundColor = Theme.panel,
    }, ui.content)
    require('source.engine.ui.widgets.collapsible').create(scene, panel, 'Maximum graphics')
    ui:text({
        position = { 0, 8, 0, 8 },
        size = { 1, -16, 0, 64 },
        text = 'Highest supported resolution / MSAA. 32 lights, PCSS, mapped surfaces and '
            .. 'shadowed colliding particles.',
        textScaled = true,
        maxTextSize = 14,
    }, panel)
    ui:button({
        position = { 0, 8, 0, 78 },
        size = { 1, -16, 0, 34 },
        text = 'Particle shadows ON / OFF',
        textScaled = true,
        maxTextSize = 14,
        radius = Theme.corner,
        onPress = function()
            self.emitter.castShadow = not self.emitter.castShadow
            self.emitter.receiveShadow = self.emitter.castShadow
            self.dust.castShadow = self.emitter.castShadow
            self.dust.receiveShadow = self.emitter.castShadow
        end,
    }, panel)
    ui:button({
        position = { 0, 8, 0, 120 },
        size = { 1, -16, 0, 34 },
        text = 'Full quality / mobile preview',
        textScaled = true,
        maxTextSize = 14,
        radius = Theme.corner,
        onPress = function()
            local r = scene.world.environment.render
            r.renderDensity = r.renderDensity == 3 and 1 or 3
            r.msaa = r.renderDensity == 3 and 8 or 0
        end,
    }, panel)
end

return Interface
