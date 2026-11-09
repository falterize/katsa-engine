local Managed = require('./managedValue')
local Array = require('./array')
local pairs = require('./array').pairs

local Types = {}
local candidates = {
    canvasSize = true,
    canvasPosition = true,
    absoluteCanvasSize = true,
    absoluteWindowSize = true,
    anchorPoint = true,
    radius = true,
    thickness = true,
    tileOffset = true,
    textureSize = true,
    textureOffset = true,
    tileSize = true,
    size = true,
    position = true,
    offset = true,
    screenPosition = true,
    rotation = true,
    scale = true,
    spatialPosition = true,
    direction = true,
    gravityDirection = true,
    atlasGrid = true,
    color = true,
    emissionColor = true,
}

function Types.kind(node, key)
    if key == 'gravityDirection' and (node:isA('World2D') or node:isA('World3D')) then
        return node:isA('World2D') and 'vector2' or 'vector3'
    end
    if not candidates[key] then
        return nil
    end
    if
        (
            key == 'canvasSize'
            or key == 'canvasPosition'
            or key == 'absoluteCanvasSize'
            or key == 'absoluteWindowSize'
        ) and node:isA('ScrollFrame')
    then
        if key == 'canvasSize' then
            return 'udim2'
        elseif
            key == 'canvasPosition'
            or key == 'absoluteCanvasSize'
            or key == 'absoluteWindowSize'
        then
            return 'vector2'
        end
    end
    if node:isA('ViewportFrame') and key == 'canvasSize' then
        return 'udim2'
    end
    if node:isA('Node2D') and (key == 'position' or key == 'size' or key == 'scale') then
        return 'vector2'
    end
    if key == 'color' or key == 'emissionColor' then
        return 'color'
    end
    if key == 'atlasGrid' then
        return 'vector2'
    end
    if key == 'anchorPoint' then
        return 'vector2'
    end
    if node:isA('UICorner') and key == 'radius' or node:isA('UIStroke') and key == 'thickness' then
        return 'vector2'
    end
    if key == 'tileOffset' or key == 'textureSize' or key == 'textureOffset' then
        return 'vector2'
    end
    if
        key == 'tileSize'
        and (
            node:isA('ImageRect')
            or node:isA('Button')
            or node:isA('Decal3D')
            or node:isA('SurfaceAppearance3D')
        )
    then
        return 'udim2'
    end
    if
        node:isA('UINode') and (key == 'size' or key == 'position')
        or node:isA('Ramp') and key == 'offset'
    then
        return 'udim2'
    end
    if node:isA('BillboardUI') or node:isA('Decal3D') then
        if
            key == 'size'
            or key == 'canvasSize'
            or key == 'screenPosition'
            or key == 'position' and not (node:isA('BillboardUI') and not node:isA('SurfaceUI'))
        then
            return 'udim2'
        end
        if key == 'rotation' then
            return 'vector3'
        end
    end
    if
        node:isA('Node3D')
        and not node:isA('BillboardUI')
        and not node:isA('Decal3D')
        and (
            key == 'position'
            or key == 'rotation'
            or key == 'scale'
            or key == 'size'
            or key == 'spatialPosition'
            or key == 'direction'
        )
    then
        return 'vector3'
    end
end

function Types.convert(kind, value, preserve)
    if not kind or value == nil then
        return value
    end
    assert(Array.is(value), kind .. ' requires a numeric value or array')
    local n = kind == 'udim2' and 4 or kind == 'vector2' and 2 or kind == 'color' and #value or 3
    assert(Array.is(value) and #value == n, kind .. ' has invalid component count')
    return require('source.engine.math.' .. kind).fromArray(value)
end

function Types.preservesArray()
    return false
end

function Types.assign(node, key, value, kind)
    local values = rawget(node, '_typedValues')
    local old = values[key]
    local converted = Types.convert(kind or Types.kind(node, key), value)
    Managed.unbind(old, node)
    values[key] = Managed.bind(converted, node)
    rawset(node, '_propertyRevision', (rawget(node, '_propertyRevision') or 0) + 1)
    return converted
end

function Types.initialize(node)
    local values = {}
    rawset(node, '_typedValues', values)
    -- Conversion inserts the node revision field. Never add keys to the same
    -- table being traversed by pairs: a rehash can skip later authored values.
    for key in pairs(candidates) do
        local value = rawget(node, key)
        local kind = value ~= nil and Types.kind(node, key)
        if kind then
            Types.assign(node, key, value, kind)
            rawset(node, key, nil)
        end
    end
end

return Types
