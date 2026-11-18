-- Sorts the inspector rows of a node into named categories (Transform, Appearance, ...) so the
-- Properties panel shows collapsible groups instead of one long list. Pure Lua: rows only need
-- a `key`. A key that is not listed lands in `Other`; rarely useful engine switches such as
-- `maxDistance` (a render cutoff, 0 = unlimited) sit in the collapsed `Rendering` group.
local Groups = {}

Groups.ORDER = { 'Transform', 'Appearance', 'Light', 'Camera', 'Physics', 'Node', 'Rendering', 'Other' }

-- Groups that start collapsed.
Groups.COLLAPSED = { Node = true, Rendering = true, Other = true }

local BY_KEY = {}
local function assign(group, keys)
    for _, key in ipairs(keys) do
        BY_KEY[key] = group
    end
end

assign('Transform', { 'position', 'rotation', 'scale', 'size', 'inheritScale', 'anchor', 'pivot' })
assign('Appearance', {
    'kind', 'geometry', 'color', 'transparency', 'doubleSided', 'alphaCutoff', 'lightInfluence',
    'colorMap', 'normalMap', 'roughness', 'metallic', 'emission', 'texture', 'image', 'text',
})
assign('Light', {
    'brightness', 'range', 'radius', 'angle', 'innerAngle', 'outerAngle', 'castShadow',
    'receiveShadow', 'shadowGroup', 'shadowBoundsPadding', 'rainbow', 'fogClearing', 'priority',
})
assign('Camera', {
    'projectionMode', 'fov', 'orthoSize', 'zoom', 'orthoNear', 'near', 'far', 'drawDistance',
    'followMode', 'followTarget', 'followDistance', 'followSensitivity', 'followSmooth',
    'pitchMin', 'pitchMax',
})
assign('Physics', {
    'bodyType', 'mass', 'friction', 'restitution', 'isTrigger', 'shape', 'linearDamping',
    'angularDamping', 'rotationFactor', 'gravityScale', 'sensor', 'offset', 'layer', 'mask',
})
assign('Node', { 'visible', 'enabled', 'replicated', 'locked', 'script' })
assign('Rendering', { 'maxDistance', 'onTop', 'zIndex', 'layerGroup', 'canQuery' })

function Groups.of(key)
    return BY_KEY[key] or 'Other'
end

-- rows (in the inspector's order) -> list of { name, rows } in Groups.ORDER, empty ones left out.
function Groups.group(rows)
    local buckets = {}
    for _, row in ipairs(rows) do
        local name = Groups.of(row.key)
        buckets[name] = buckets[name] or {}
        table.insert(buckets[name], row)
    end
    local result = {}
    for _, name in ipairs(Groups.ORDER) do
        if buckets[name] then
            result[#result + 1] = { name = name, rows = buckets[name] }
        end
    end
    return result
end

return Groups
