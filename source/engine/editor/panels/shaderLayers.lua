local ipairs = require('../../math.array').ipairs

-- Shader layers dialog: the same matrix editor as Layers groups, without the 2D/3D tabs.
local Editor = {}

function Editor.open(workspace)
    local Popup = require('source.engine.editor.panels.popup')
    if workspace.popup then
        workspace.popup:close(true)
    end
    workspace.selected = workspace.selected or workspace.scene.world.root
    local popup =
        Popup.new(workspace, { key = 'ShaderLayers', kind = 'string', value = '', readOnly = true })
    workspace.popup = popup
    local world = workspace.scene.world
    local registry = world.shaderLayers
    popup.message.text = 'Live edits; each matrix is symmetric.'
    for _, node in ipairs(popup.panel.children) do
        if node.text == 'Apply' then
            node.text = 'Done'
        elseif node.text == 'Cancel' then
            node.text = 'Close'
        end
    end
    local selected, tableView, page = 'Default3D', false, 1
    local render

    local function button(text, x, y, width, fn, enabled)
        local node = popup.ui:button({
            position = { x, 4, 0, y },
            size = { width, -8, 0, 34 },
            text = text,
            fontSize = 12,
            textScaled = true,
            maxTextSize = 12,
            enabled = enabled ~= false,
            backgroundColor = { 0.09, 0.16, 0.23 },
        }, popup.body)
        node:connect('press', function()
            local ok, err = pcall(fn)
            if not ok then
                popup.message.text = tostring(err)
            end
        end)
        return node
    end
    local function isDefault(name)
        return name == 'Default2D' or name == 'Default3D'
    end
    render = function()
        while #popup.body.children > 0 do
            popup.body.children[#popup.body.children]:destroy()
        end
        popup.title.text = 'Shader layers / ' .. #registry.names .. ' of 30'
        popup:input('Add layer', '', 0, function(name)
            registry:add(name)
            selected = name
            render()
            return true
        end)
        popup:input('Rename', selected, 42, function(name)
            registry:rename(selected, name)
            selected = name
            render()
            return true
        end)
        popup:input('Priority', tostring(registry:priority(selected)), 84, function(text)
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
        button('Delete selected', 0, 126, 0.5, function()
            registry:remove(selected)
            selected = 'Default3D'
            render()
        end, not isDefault(selected))
        button(tableView and 'List view' or 'Table view', 0.5, 126, 0.5, function()
            tableView = not tableView
            render()
        end)
        local names = registry.names
        if tableView then
            local columns = math.min(4, #names)
            local first = (page - 1) * 4 + 1
            if first > #names then
                page, first = 1, 1
            end
            button('Previous columns', 0, 166, 0.5, function()
                page = math.max(1, page - 1)
                render()
            end)
            button('Next columns', 0.5, 166, 0.5, function()
                page = page + 1
                render()
            end)
            for i = 1, columns do
                local name = names[first + i - 1]
                if name then
                    popup.ui:text({
                        position = { 0.3 + (i - 1) * 0.7 / columns, 0, 0, 206 },
                        size = { 0.7 / columns, -2, 0, 34 },
                        text = name,
                        textScaled = true,
                        maxTextSize = 11,
                    }, popup.body)
                end
            end
            for row, a in ipairs(names) do
                popup.ui:text({
                    position = { 0, 4, 0, 240 + (row - 1) * 38 },
                    size = { 0.3, -8, 0, 34 },
                    text = a,
                    textScaled = true,
                    maxTextSize = 12,
                    align = 'left',
                }, popup.body)
                for i = 1, columns do
                    local b = names[first + i - 1]
                    if b then
                        button(
                            registry:interacts(a, b) and '[x]' or '[ ]',
                            0.3 + (i - 1) * 0.7 / columns,
                            240 + (row - 1) * 38,
                            0.7 / columns,
                            function()
                                registry:setInteracts(a, b, not registry:interacts(a, b))
                                render()
                            end,
                            a ~= b
                        )
                    end
                end
            end
            popup.body.length = 244 + #names * 38
        else
            popup.ui:text({
                position = { 0, 4, 0, 166 },
                size = { 1, -8, 0, 34 },
                text = selected .. ' interacts with:',
                textScaled = true,
                maxTextSize = 14,
            }, popup.body)
            for i, name in ipairs(names) do
                button(name .. ' (' .. registry:priority(name) .. ')', 0, 204 + (i - 1) * 38, 0.45, function()
                    selected = name
                    render()
                end)
                button(
                    (registry:interacts(selected, name) and '[x] ' or '[ ] ') .. name,
                    0.45,
                    204 + (i - 1) * 38,
                    0.55,
                    function()
                        registry:setInteracts(selected, name, not registry:interacts(selected, name))
                        render()
                    end,
                    selected ~= name
                )
            end
            popup.body.length = 208 + #names * 38
        end
        popup.ui:invalidate()
    end
    render()
    return popup
end

return Editor
