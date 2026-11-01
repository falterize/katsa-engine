local Layers = {}

function Layers.visible(world, node, viewer)
    if not world or not world.layerGroups then
        return true
    end
    local registry = world.layerGroups
    local source, target = node.layerGroup or 'Default', viewer and viewer.layerGroup or 'Default'
    if
        node._visibilityRegistry == registry
        and node._visibilityRevision == registry.revision
        and node._visibilitySource == source
        and node._visibilityTarget == target
    then
        return node._visibilityResult
    end
    local group = registry:canonical(node.layerGroup or 'Default')
    local view = registry:canonical(viewer and viewer.layerGroup or 'Default')
    assert(registry.bits[group], 'Unknown layer group: ' .. tostring(group))
    assert(registry.bits[view], 'Unknown viewer layer group: ' .. tostring(view))
    local result = registry:interacts(view, group)
    node._visibilityRegistry, node._visibilityRevision = registry, registry.revision
    node._visibilitySource, node._visibilityTarget, node._visibilityResult = source, target, result
    return result
end

function Layers.viewer(ui, node)
    if ui.owner then
        local world = ui._sceneWorld or ui.owner._world or ui.owner._sceneWorld
        return world and (world._materialCamera or world.activeCamera)
    end
    local parent = node.parent
    while parent and parent ~= ui do
        if parent:isA('Node2D') then
            return ui.currentCamera or ui
        end
        parent = parent.parent
    end
    return ui
end

return Layers
