-- The toggle is a sibling, so a collapsed panel has no old hit or clipping region.
local Collapsible = {}

function Collapsible.create(scene, panel, title, position)
    local ui = panel.ui or scene.root:find('World3D/World2D')
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
    -- The scene's ImGui host (when it has one) shows the panel as a window instead.
    local entry = { title = title, panel = panel, toggle = toggle, startOpen = expanded }
    scene.controlPanels = scene.controlPanels or {}
    scene.controlPanels[#scene.controlPanels + 1] = entry
    if scene.adoptControlPanel then
        scene:adoptControlPanel(entry)
    end
    panel:onDestroy(function()
        entry.destroyed = true
        if not toggle.destroyed then
            toggle:destroy()
        end
    end)
    return toggle
end

-- Loose scene controls (buttons, sliders) that have no panel of their own: with an ImGui host
-- they are mirrored in one window and the engine nodes are hidden; without it nothing changes.
-- `nodes` is the list of controls in display order.
function Collapsible.adopt(scene, title, nodes, onAdopt)
    -- A single node is a panel (hidden as a whole); a list is a set of loose controls.
    local entry = { title = title, startOpen = true, onAdopt = onAdopt }
    if nodes.isA then
        entry.panel = nodes
    else
        entry.nodes = nodes
    end
    scene.controlPanels = scene.controlPanels or {}
    scene.controlPanels[#scene.controlPanels + 1] = entry
    if scene.adoptControlPanel then
        scene:adoptControlPanel(entry)
    end
    return entry
end

return Collapsible
