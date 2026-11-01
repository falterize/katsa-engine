local Order = {}

local function less(a, b)
    local za, zb = a.node.zIndex or 0, b.node.zIndex or 0
    if za ~= zb then
        return za < zb
    end
    local world = a.node._sceneWorld or b.node._sceneWorld
    if world then
        local pa = a.node:isA('Shader2D') and world.shaderLayers:priority(a.node.shaderLayer) or 0
        local pb = b.node:isA('Shader2D') and world.shaderLayers:priority(b.node.shaderLayer) or 0
        if pa ~= pb then
            return pa < pb
        end
    end
    return a.index < b.index
end

-- Rendering order must never mutate the authoring hierarchy used by Workspace.
function Order.refresh(children)
    local view = children._layoutOrder or { entries = {}, nodes = {} }
    children._layoutOrder = view
    for i, node in ipairs(children) do
        local entry = view.entries[i] or {}
        entry.node, entry.index = node, i
        view.entries[i] = entry
    end
    for i = #view.entries, #children + 1, -1 do
        view.entries[i] = nil
    end
    table.sort(view.entries, less)
    for i, entry in ipairs(view.entries) do
        view.nodes[i] = entry.node
    end
    for i = #view.nodes, #children + 1, -1 do
        view.nodes[i] = nil
    end
    return view.nodes
end

function Order.get(children)
    return children._layoutOrder and children._layoutOrder.nodes or children
end

return Order
