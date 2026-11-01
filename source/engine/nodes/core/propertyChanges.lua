local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Scalar property writes carry a revision; mutable arrays retain component observation.
local Policy = require('source.engine.nodes.core.propertyPolicy')

local Changes = {}
local masks = setmetatable({}, { __mode = 'k' })

function Changes.initialize(node)
    local class = node._class
    local types = class._types
    if not types.Node3D and not types.SurfaceAppearance3D then
        return
    end
    local fields = masks[class]
    if not fields then
        fields = {}

        local function add(keys)
            for _, key in ipairs(keys) do
                if key:sub(1, 1) ~= '_' then
                    fields[key] = true
                end
            end
        end
        if types.Node3D then
            add(Policy.nodeKeys)
            fields.poseMatrix, fields.physicsMatrix, fields.localMatrix = true, true, true
        end
        if types.Mesh3D then
            add(Policy.meshKeys)
        end
        if types.SurfaceAppearance3D then
            add(Policy.surfaceKeys)
        end
        if types.PointLight3D or types.SpotLight3D or types.DirectionalLight3D then
            add(Policy.lightKeys)
        end
        if types.Camera3D then
            add(Policy.cameraKeys)
        end
        if class.getEnabled or class.setEnabled then
            fields.enabled = nil
        end
        masks[class] = fields
    end
    local values = {}
    for key in pairs(fields) do
        if key ~= 'parent' then
            values[key] = rawget(node, key)
            rawset(node, key, nil)
        end
    end
    rawset(node, '_observedFields', fields)
    rawset(node, '_observedValues', values)
    rawset(node, '_propertyRevision', 1)
end

function Changes.touch(node)
    if rawget(node, '_observedFields') then
        rawset(node, '_propertyRevision', (rawget(node, '_propertyRevision') or 0) + 1)
    end
end

function Changes.set(node, key, value)
    local values = rawget(node, '_observedValues')
    if values[key] ~= value then
        values[key] = value
        Changes.touch(node)
    end
end

return Changes
