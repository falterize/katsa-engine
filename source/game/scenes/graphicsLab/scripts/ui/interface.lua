local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(self)
    local scene, ui = self.scene, self.scene.ui
    local panel = ui:scroll({
        _viewportAuthored = true,
        name = 'MaximumGraphicsControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 280, 0.66, -124 },
        length = 470,
        visible = false,
        backgroundColor = Theme.panel,
    }, ui.content)
    require('source.engine.ui.widgets.collapsible').create(scene, panel, 'Maximum graphics')
    ui:text({
        position = { 0, 8, 0, 8 },
        size = { 1, -16, 0, 64 },
        text = 'Highest supported resolution / MSAA. 32 lights, PCSS, mapped surfaces and '
            .. 'shadowed colliding particles, and every post-processing effect.',
        textScaled = true,
        maxTextSize = 14,
    }, panel)
    do
        local node = ui:button({
            position = { 0, 8, 0, 78 },
            size = { 1, -16, 0, 34 },
            text = 'Particle shadows ON / OFF',
            textScaled = true,
            maxTextSize = 14,
            radius = Theme.corner,
        }, panel)
        node:connect('press', function()
            self.emitter.castShadow = not self.emitter.castShadow
            self.emitter.receiveShadow = self.emitter.castShadow
            self.dust.castShadow = self.emitter.castShadow
            self.dust.receiveShadow = self.emitter.castShadow
        end)
    end
    do
        local node = ui:button({
            position = { 0, 8, 0, 120 },
            size = { 1, -16, 0, 34 },
            text = 'Full quality / mobile preview',
            textScaled = true,
            maxTextSize = 14,
            radius = Theme.corner,
        }, panel)
        node:connect('press', function()
            local r = scene.world.environment.render
            r.renderDensity = r.renderDensity == 3 and 1 or 3
            r.msaa = r.renderDensity == 3 and 8 or 0
        end)
    end
    -- One switch per post-processing section, like the Environment rows in the Workspace.
    local effects = {
        { 'Glow', function(e) return e.glow end },
        { 'SSAO', function(e) return e.ssao end },
        { 'Depth of field', function(e) return e.depthOfField end },
        { 'Adjustments', function(e) return e.adjustments end },
        { 'Volumetric fog', function(e) return e.fog end, 'volumetric' },
    }
    local y = 162
    for _, effect in ipairs(effects) do
        do
            local node = ui:button({
                position = { 0, 8, 0, y },
                size = { 1, -16, 0, 34 },
                text = effect[1] .. ' ON / OFF',
                textScaled = true,
                maxTextSize = 14,
                radius = Theme.corner,
            }, panel)
            node:connect('press', function()
                local section = effect[2](scene.world.environment)
                local key = effect[3] or 'enabled'
                section[key] = not section[key]
            end)
        end
        y = y + 42
    end
    do
        local node = ui:button({
            position = { 0, 8, 0, y },
            size = { 1, -16, 0, 34 },
            text = 'FXAA ON / OFF',
            textScaled = true,
            maxTextSize = 14,
            radius = Theme.corner,
        }, panel)
        node:connect('press', function()
            local r = scene.world.environment.render
            r.screenSpaceAA = r.screenSpaceAA == 'FXAA' and 'Disabled' or 'FXAA'
        end)
    end
end

return Interface
