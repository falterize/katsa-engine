local Tree = require('source.engine.editor.tree.traversal')
local WorkspaceRows = require('source.engine.editor.tree.workspaceRows')

-- Explorer: the node tree of the scene as its own movable window. Selecting a row sets
-- `host.selection`, which the Properties window shows. Fold state and the search text live on
-- the scene's Workspace, so the legacy panel and this window agree.
-- No hotkey: F5-F8 belong to scenes; the toolbar opens it.
local Explorer = { id = 'explorer', title = 'Explorer' }

local INDENT = 14
local REFRESH = 0.3 -- seconds between tree rebuilds; rows are only rebuilt, never drawn stale

function Explorer.new()
    return { query = '', rows = {}, refreshed = -1 }
end

local function refresh(scene, state)
    local workspace = scene.workspace
    local roots, extras = workspace:treeRoots()
    state.rows = Tree.rows(roots, workspace.collapsed, nil, state.query, extras)
    state.refreshed = katsa.timer.getTime()
end

local function drawRow(ig, scene, state, host, row, index)
    local C = ig.C
    local node = row.node
    if node.destroyed then
        return
    end
    local workspace = scene.workspace
    local selected = host.selection == node
    local x = 6 + row.depth * INDENT
    ig.pushID(index)
    if
        C.igSelectable_Bool(
            '##row',
            selected,
            C.ImGuiSelectableFlags_AllowOverlap,
            ig.vec2(0, 0)
        )
    then
        host.selection = node
    end
    ig.sameLine(x)
    if #Tree.children(node) > 0 then
        if ig.smallButton(workspace.collapsed[node] and '+' or '-') then
            workspace.collapsed[node] = not workspace.collapsed[node]
            state.refreshed = -1
        end
    end
    ig.sameLine(x + 24)
    local color = WorkspaceRows.chipColor(node.className)
    ig.textColored(color[1], color[2], color[3], 1, node.name or node.className or 'Node')
    ig.sameLine()
    ig.textDisabled(node.className or 'Node')
    ig.popID()
end

function Explorer.draw(ig, scene, state, host)
    local workspace = scene.workspace
    local width, height = katsa.graphics.getDimensions()
    ig.setNextWindowPos(10, 50)
    ig.setNextWindowSize(math.min(340, width * 0.4), math.min(560, height - 70))
    local visible, open = ig.begin('Explorer', true)
    if visible then
        ig.setNextItemWidth(-1)
        local changed, query = ig.inputText('##search', state.query)
        if changed then
            state.query = query
            state.refreshed = -1
        end
        if ig.button('Groups') then
            require('source.engine.editor.panels.groupEditor').open(workspace)
        end
        ig.sameLine()
        if ig.button('Shaders') then
            require('source.engine.editor.panels.shaderLayers').open(workspace)
        end
        ig.sameLine()
        ig.textDisabled('%d rows', #state.rows)
        ig.separator()
        if katsa.timer.getTime() - state.refreshed > REFRESH then
            refresh(scene, state)
        end
        if ig.beginChild('##rows', 0, 0, false, ig.C.ImGuiWindowFlags_HorizontalScrollbar) then
            -- Only the visible rows are built; spacers keep the scroll range of the full list.
            local line = ig.lineHeight()
            local gap = line - ig.C.igGetTextLineHeight()
            local _, available = ig.available()
            local first = math.max(1, math.floor(ig.scrollY() / line) + 1)
            local last = math.min(#state.rows, first + math.ceil(available / line) + 1)
            if first > 1 then
                ig.dummy(1, (first - 1) * line - gap)
            end
            for index = first, last do
                drawRow(ig, scene, state, host, state.rows[index], index)
            end
            if last < #state.rows then
                ig.dummy(1, (#state.rows - last) * line - gap)
            end
        end
        ig.endChild()
    end
    ig.finish()
    if not open then
        host:close('explorer')
    end
end

return Explorer
