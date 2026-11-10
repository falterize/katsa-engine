-- The toggle is a sibling, so a collapsed panel has no old hit or clipping region.
local Collapsible = {}

function Collapsible.create(scene, panel, title, position)
    local ui = panel.ui or scene.ui
    local parent = panel.parent
    local expanded = panel.visible ~= false
    local toggle
    toggle = ui:button({
        _viewportAuthored = true,
        name = title .. 'Toggle',
        position = position or { 0, 12, 0, 66 },
        size = { 0, 180, 0, 38 },
        text = (expanded and '− ' or '+ ') .. title,
        textScaled = true,
        maxTextSize = 15,
        zIndex = (panel.zIndex or 0) + 1,
        backgroundColor = { 0.09, 0.2, 0.29 },
        radius = require('source.engine.ui.theme').corner,
    }, parent)
    toggle:connect('press', function()
        expanded = not expanded
        panel.visible = expanded
        toggle.text = (expanded and '− ' or '+ ') .. title
        scene.input:reset()
    end)
    panel:onDestroy(function()
        if not toggle.destroyed then
            toggle:destroy()
        end
    end)
    return toggle
end

return Collapsible
