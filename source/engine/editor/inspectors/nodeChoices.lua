local ipairs = require('../../math.array').ipairs

-- The nodes a node-reference field can point at, as rows { node, label }. The first row is the
-- "none" entry (node = nil). Shared by the legacy popup and the ImGui Properties window.
local NodeChoices = {}

function NodeChoices.list(scene, target, field)
    local support = require('source.engine.world.surfaces.support')
    local references = require('source.engine.editor.inspectors.nodeReferences')
    local Properties = require('source.engine.editor.inspectors.properties')
    local modelSource = field.key == 'geometrySource' and target:isA('Collider3D')
    local rows = {
        { label = modelSource and 'None (no geometry source)' or 'None (use spatial Parent)' },
    }
    local world = target._world or target._sceneWorld or scene.world
    local key = field.key
    for _, node in ipairs(world._node:getDescendants()) do
        local sameWorld = (node._world or node._sceneWorld) == world
        local valid = field.attribute and node ~= target and sameWorld
            or references.accepts(target, key, node)
            or key == 'currentCamera' and node:isA('Camera3D') and node._world == world
            or key == 'positionSource' and node:isA('Node3D') and sameWorld
            or key == 'adornee' and target:isA('Ramp') and node ~= target and sameWorld
            or key == 'adornee'
                and not target:isA('Ramp')
                and support.valid(target, node)
                and (not target:isA('Button3D') or node:isA('Mesh3D'))
        if valid then
            rows[#rows + 1] = {
                node = node,
                label = node.name .. ' [' .. node.className .. '] / ' .. Properties.parentPath(node),
            }
        end
    end
    return rows
end

return NodeChoices
