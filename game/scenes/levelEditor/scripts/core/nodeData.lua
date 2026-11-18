-- Plain-data snapshots of nodes (class, name, public properties, children). Properties are
-- collected through the engine's own inspector property list (`Clone.collect`), so a snapshot
-- holds exactly what the Workspace can edit. Used to undo a delete, to copy/paste and, later,
-- to write a `.katsa` location.
local Clone = require('source.engine.nodes.core.clone')

local NodeData = {}

-- Runtime-only keys that Clone.collect may return but a rebuilt node must not receive.
-- `geometry` and `material` are runtime resources: primitives are rebuilt from `kind`, editor
-- shapes from the EditorShape attribute and models from EditorModel.
local SKIPPED = { name = true, geometry = true, material = true }
local Shapes = require('../builders.shapes')

function NodeData.capture(node)
    local properties = Clone.collect(node)
    local data = {
        class = node.className,
        name = node.name,
        properties = {},
        attributes = {},
        children = {},
    }
    for key, value in pairs(properties) do
        if not SKIPPED[key] then
            data.properties[key] = value
        end
    end
    for _, name in ipairs(node:getAttributeNames()) do
        if not node:isAttributeReference(name) then
            data.attributes[name] = node:getAttribute(name)
        end
    end
    -- A loaded model is rebuilt by loading the file again, so its meshes are not captured.
    if node:getAttribute('EditorModel') then
        data.model = node:getAttribute('EditorModel')
        return data
    end
    for _, child in ipairs(node.children) do
        if not child.destroyed and not child._transientClone then
            data.children[#data.children + 1] = NodeData.capture(child)
        end
    end
    return data
end

local function copy(value)
    if type(value) ~= 'table' then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = copy(item)
    end
    return result
end

-- A deep copy of a snapshot, so a clipboard entry can be built any number of times.
function NodeData.clone(data)
    return copy(data)
end

-- Rebuilds a snapshot under `parent`; returns the new node. The snapshot is not consumed.
function NodeData.build(world, data, parent)
    local properties = copy(data.properties)
    properties.name = data.name
    local node
    if data.model then
        local root = world:loadModel(data.model)
        root:setParent(parent)
        root.name = data.name
        for key, value in pairs(properties) do
            if key ~= 'parent' then
                root[key] = value
            end
        end
        node = root
    else
        local shape = data.attributes and data.attributes.EditorShape
        if shape then
            properties.geometry = Shapes.geometry(world, shape)
        end
        node = world:create(data.class, properties, parent)
    end
    for name, value in pairs(data.attributes or {}) do
        node:setAttribute(name, copy(value))
    end
    for _, child in ipairs(data.children) do
        NodeData.build(world, child, node)
    end
    return node
end

return NodeData
