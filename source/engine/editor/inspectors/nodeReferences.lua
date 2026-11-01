local Schema = require('source.engine.editor.inspectors.schema')

local References = {}

function References.expected(target, key)
    if key == 'geometrySource' then
        return 'Node3D'
    end
    if key == 'attachment0' or key == 'attachment1' then
        return target:isA('Constraint2D') and 'Attachment2D' or 'Attachment3D'
    end
    local descriptor = Schema.descriptor(target, key)
    return descriptor.kind == 'node' and (descriptor.nodeClass or 'Node') or nil
end

function References.accepts(target, key, node)
    local expected = References.expected(target, key)
    if not expected then
        return nil
    end
    if not node then
        return true
    end
    if type(node) == 'string' then
        if key ~= 'geometrySource' or not target:isA('Collider3D') then
            return false
        end
        local world = target._world or target._sceneWorld
        return world
                and pcall(
                    require('source.engine.physics.3d.modelSource').path,
                    node,
                    world.resources
                )
            or false
    end
    if not node._node or node.destroyed or not node:isA(expected) then
        return false
    end
    local plane = target:isA('World2D') and target or target._plane
    if plane then
        return node._plane == plane
    end
    local world = target._world or target._sceneWorld
    return not world or (node._world or node._sceneWorld) == world
end

return References
