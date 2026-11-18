-- Pure tree helpers for the Workspace panel: the visible rows of a tree with some branches
-- collapsed, the reparent rules and range selection. Nodes are opaque values; `childrenOf(node)`
-- and `parentOf(node)` are supplied by the caller, so this runs without the engine.
local TreeModel = {}

-- Rows in drawing order: { node, depth, hasChildren, expanded }. `expanded` maps node -> true.
-- The root itself is row 1 at depth 0 and is always shown.
function TreeModel.flatten(root, childrenOf, expanded, out)
    out = out or {}
    local count = 0
    local function visit(node, depth)
        local children = childrenOf(node)
        local open = expanded[node] == true
        count = count + 1
        local row = out[count] or {}
        out[count] = row
        row.node, row.depth, row.hasChildren, row.expanded = node, depth, #children > 0, open
        if open then
            for _, child in ipairs(children) do
                visit(child, depth + 1)
            end
        end
    end
    visit(root, 0)
    for index = #out, count + 1, -1 do
        out[index] = nil
    end
    return out
end

function TreeModel.isDescendant(node, ancestor, parentOf)
    local current = parentOf(node)
    while current do
        if current == ancestor then
            return true
        end
        current = parentOf(current)
    end
    return false
end

-- A node may move under `newParent` unless that is itself or one of its own descendants.
function TreeModel.canReparent(node, newParent, parentOf)
    return newParent ~= nil
        and newParent ~= node
        and not TreeModel.isDescendant(newParent, node, parentOf)
end

-- Of a selection, only the nodes whose ancestors are not also selected: moving or deleting
-- a group already carries its children.
function TreeModel.topLevel(nodes, parentOf)
    local selected = {}
    for _, node in ipairs(nodes) do
        selected[node] = true
    end
    local result = {}
    for _, node in ipairs(nodes) do
        local covered, current = false, parentOf(node)
        while current do
            if selected[current] then
                covered = true
                break
            end
            current = parentOf(current)
        end
        if not covered then
            result[#result + 1] = node
        end
    end
    return result
end

-- Nodes of the rows between two nodes (inclusive, in either order); nil if one is not listed.
function TreeModel.range(rows, a, b)
    local first, last
    for index, row in ipairs(rows) do
        if row.node == a or row.node == b then
            if not first then
                first = index
            end
            last = index
        end
    end
    if not first or (a ~= b and first == last) then
        return nil
    end
    local result = {}
    for index = first, last do
        result[#result + 1] = rows[index].node
    end
    return result
end

return TreeModel
