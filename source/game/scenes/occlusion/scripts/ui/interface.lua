local ipairs = require('source.engine.math.array').ipairs
local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(self)
    local scene, ui = self.scene, self.scene.ui
    local panel = ui:scroll({
        _viewportAuthored = true,
        name = 'OcclusionControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 280, 0.66, -124 },
        length = 202,
        visible = false,
        backgroundColor = Theme.panel,
    }, ui.content)
    require('source.engine.ui.widgets.collapsible').create(scene, panel, 'Occlusion culling')
    ui:text({
        position = { 0, 8, 0, 8 },
        size = { 1, -16, 0, 54 },
        textScaled = true,
        maxTextSize = 14,
        text = 'Compare whole objects and hidden triangles. Partial mesh mode exposes a single '
            .. 'tiled panel.',
    }, panel)
    self.toggle = ui:button({
        position = { 0, 8, 0, 70 },
        size = { 1, -16, 0, 34 },
        text = 'Occlusion ON',
        textScaled = true,
        maxTextSize = 14,
        radius = Theme.corner,
        onPress = function()
            local render = scene.world.environment.render
            render.occlusionCulling = not render.occlusionCulling
            self.toggle.text = render.occlusionCulling and 'Occlusion ON' or 'Occlusion OFF'
        end,
    }, panel)
    ui:button({
        position = { 0, 8, 0, 112 },
        size = { 1, -16, 0, 34 },
        text = 'Wall motion ON / OFF',
        textScaled = true,
        maxTextSize = 14,
        radius = Theme.corner,
        onPress = function()
            self.moving = not self.moving
        end,
    }, panel)
    ui:button({
        position = { 0, 8, 0, 154 },
        size = { 1, -16, 0, 34 },
        text = 'Partial mesh ON / OFF',
        textScaled = true,
        maxTextSize = 14,
        radius = Theme.corner,
        onPress = function()
            self.partialPanel.visible = not self.partialPanel.visible
            self.wall.size[1] = self.partialPanel.visible and 80 or 240
        end,
    }, panel)
end

return Interface
