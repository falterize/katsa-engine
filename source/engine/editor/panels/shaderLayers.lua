local ipairs = require('source.engine.math.array').ipairs

local Editor = {}

function Editor.open(workspace)
    if workspace.popup then
        workspace.popup:close(true)
    end
    workspace.selected = workspace.selected or workspace.scene.world.root
    local world = workspace.selected._world
        or workspace.selected._sceneWorld
        or workspace.scene.world
    local registry = world.shaderLayers
    local popup = require('source.engine.editor.panels.popup').new(
        workspace,
        { key = 'Shader Layers', kind = 'string', value = '', readOnly = true }
    )
    workspace.popup = popup
    popup.readOnlyHint = true
    local selected = 'Default'
    local render
    render = function()
        while #popup.body.children > 0 do
            popup.body.children[#popup.body.children]:destroy()
        end
        popup.title.text = 'Shader layers / ' .. world.root.name
        popup.message.text = 'Directed checkboxes: selected upper layer suppresses lower layer.'
        popup:input('Add layer', '', 0, function(name)
            registry:add(name)
            selected = name
            render()
            return true
        end)
        popup:input('Priority', tostring(registry:priority(selected)), 42, function(text)
            local number = tonumber(text)
            if not number then
                return false, 'Enter a number'
            end
            local ok, err = pcall(registry.setPriority, registry, selected, number)
            if ok then
                render()
            end
            return ok, tostring(err)
        end)
        for i, name in ipairs(registry.names) do
            popup.ui:button({
                position = { 0, 4, 0, 88 + (i - 1) * 38 },
                size = { 0.48, -8, 0, 34 },
                text = name .. ' (' .. registry:priority(name) .. ')',
                fontSize = 12,
                backgroundColor = { 0.085, 0.135, 0.19 },
                onPress = function()
                    selected = name
                    render()
                end,
            }, popup.body)
            local available = registry:priority(selected) > registry:priority(name)
            popup.ui:button({
                position = { 0.48, 0, 0, 88 + (i - 1) * 38 },
                size = { 0.52, -4, 0, 34 },
                text = (registry:suppresses(selected, name) and '[x] Suppress ' or '[ ] Suppress ')
                    .. name,
                fontSize = 12,
                textScaled = true,
                maxTextSize = 12,
                enabled = available,
                backgroundColor = { 0.085, 0.135, 0.19 },
                onPress = function()
                    registry:setSuppressed(selected, name, not registry:suppresses(selected, name))
                    render()
                end,
            }, popup.body)
        end
        popup.body.length = 92 + #registry.names * 38
    end
    render()
    return popup
end

return Editor
