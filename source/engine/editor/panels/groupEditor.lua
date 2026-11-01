local ipairs = require('source.engine.math.array').ipairs

local Editor = {}

function Editor.open(workspace)
    local Popup = require('source.engine.editor.panels.popup')
    if workspace.popup then
        workspace.popup:close(true)
    end
    workspace.selected = workspace.selected or workspace.scene.world.root
    local popup =
        Popup.new(workspace, { key = 'Groups', kind = 'string', value = '', readOnly = true })
    workspace.popup = popup
    popup.title.text = 'Interaction groups'
    popup.message.text = 'Live edits; each matrix is symmetric.'
    for _, node in ipairs(popup.panel.children) do
        if node.text == 'Apply' then
            node.text = 'Done'
        elseif node.text == 'Cancel' then
            node.text = 'Close'
        end
    end
    local mode, selected, tableView, page = 'Layers', 'Default', false, 1

    local function physics2D()
        local selectedNode = workspace.selected
        local plane = selectedNode
                and selectedNode.isA
                and selectedNode:isA('World2D')
                and selectedNode
            or selectedNode and selectedNode._plane
            or workspace.scene.ui
        return plane.physics2D
    end

    local function registry()
        if mode == 'Layers' then
            return workspace.scene.world.layerGroups
        end
        if mode == 'Collisions 2D' then
            local physics = physics2D()
            return physics and physics.collisionGroups
        end
        return workspace.scene.physics and workspace.scene.physics.collisionGroups
    end
    local render

    local function button(text, x, y, width, fn, enabled)
        return popup.ui:button({
            position = { x, 4, 0, y },
            size = { width, -8, 0, 34 },
            text = text,
            fontSize = 12,
            textScaled = true,
            maxTextSize = 12,
            enabled = enabled ~= false,
            backgroundColor = { 0.09, 0.16, 0.23 },
            onPress = function()
                local ok, err = pcall(fn)
                if not ok then
                    popup.message.text = tostring(err)
                end
            end,
        }, popup.body)
    end
    render = function()
        while #popup.body.children > 0 do
            popup.body.children[#popup.body.children]:destroy()
        end
        local r = registry()
        button('Layers', 0, 0, 1 / 3, function()
            mode = 'Layers'
            selected = 'Default'
            render()
        end)
        button('Collisions 3D', 1 / 3, 0, 1 / 3, function()
            mode = 'Collisions'
            selected = 'Default'
            render()
        end, workspace.scene.physics ~= nil)
        button('Collisions 2D', 2 / 3, 0, 1 / 3, function()
            mode, selected = 'Collisions 2D', 'Default'
            render()
        end, physics2D() ~= nil)
        if not r then
            return
        end
        popup.title.text = mode .. ' groups / ' .. #r.names .. ' of 30'
        popup:input('Add group', '', 40, function(name)
            r:add(name)
            selected = name
            render()
            return true
        end)
        popup:input('Rename', selected, 80, function(name)
            r:rename(selected, name)
            selected = name
            render()
            return true
        end)
        button('Delete selected', 0, 120, 0.5, function()
            r:remove(selected)
            selected = 'Default'
            render()
        end, selected ~= 'Default')
        button(tableView and 'List view' or 'Table view', 0.5, 120, 0.5, function()
            tableView = not tableView
            render()
        end)
        if tableView then
            local columns = math.min(4, #r.names)
            local first = (page - 1) * 4 + 1
            if first > #r.names then
                page = 1
                first = 1
            end
            button('Previous columns', 0, 160, 0.5, function()
                page = math.max(1, page - 1)
                render()
            end)
            button('Next columns', 0.5, 160, 0.5, function()
                page = page + 1
                render()
            end)
            for i = 1, columns do
                local name = r.names[first + i - 1]
                if name then
                    popup.ui:text({
                        position = { 0.3 + (i - 1) * 0.7 / columns, 0, 0, 200 },
                        size = { 0.7 / columns, -2, 0, 34 },
                        text = name,
                        textScaled = true,
                        maxTextSize = 11,
                    }, popup.body)
                end
            end
            for row, a in ipairs(r.names) do
                popup.ui:text({
                    position = { 0, 4, 0, 234 + (row - 1) * 38 },
                    size = { 0.3, -8, 0, 34 },
                    text = a,
                    textScaled = true,
                    maxTextSize = 12,
                    align = 'left',
                }, popup.body)
                for i = 1, columns do
                    local b = r.names[first + i - 1]
                    if b then
                        button(
                            r:interacts(a, b) and '[x]' or '[ ]',
                            0.3 + (i - 1) * 0.7 / columns,
                            234 + (row - 1) * 38,
                            0.7 / columns,
                            function()
                                r:set(a, b, not r:interacts(a, b))
                                render()
                            end
                        )
                    end
                end
            end
            popup.body.length = 238 + #r.names * 38
        else
            popup.ui:text({
                position = { 0, 4, 0, 160 },
                size = { 1, -8, 0, 34 },
                text = selected .. ' interacts with:',
                textScaled = true,
                maxTextSize = 14,
            }, popup.body)
            for i, name in ipairs(r.names) do
                button(name, 0, 198 + (i - 1) * 38, 0.45, function()
                    selected = name
                    render()
                end)
                button(
                    (r:interacts(selected, name) and '[x] ' or '[ ] ') .. name,
                    0.45,
                    198 + (i - 1) * 38,
                    0.55,
                    function()
                        r:set(selected, name, not r:interacts(selected, name))
                        render()
                    end
                )
            end
            popup.body.length = 202 + #r.names * 38
        end
        popup.ui:invalidate()
    end
    render()
    return popup
end

return Editor
