local Polygon = require('source.engine.physics.2d.geometry.polygon')
local Image = require('source.engine.physics.2d.geometry.image')

local Shapes = {}

local function points(values, factor, x, y, angle, transform)
    assert(
        type(values) == 'table' and #values >= 4 and #values % 2 == 0,
        'Expected flat 2D vertices'
    )
    local result, c, s = {}, math.cos(angle), math.sin(angle)
    for i = 1, #values, 2 do
        if transform then
            result[i] = (transform[1] * values[i] + transform[3] * values[i + 1] + transform[5])
                * factor
            result[i + 1] = (transform[2] * values[i] + transform[4] * values[i + 1] + transform[6])
                * factor
        else
            result[i] = (x + values[i] * c - values[i + 1] * s) * factor
            result[i + 1] = (y + values[i] * s + values[i + 1] * c) * factor
        end
    end
    return result
end

function Shapes.create(descriptor, factor)
    local kind = descriptor.shape or 'Box'
    local size = descriptor.size or { 32, 32 }
    local offset = descriptor.offset or { 0, 0 }
    local x, y, angle = offset[1], offset[2], math.rad(descriptor.rotation or 0)
    local matrix = descriptor._transform
    if kind == 'Box' and matrix then
        local w, h = size[1] / 2, size[2] / 2
        return katsa.physics.newPolygonShape(
            unpack(points({ -w, -h, w, -h, w, h, -w, h }, factor, x, y, angle, matrix))
        )
    elseif kind == 'Box' then
        return katsa.physics.newRectangleShape(
            x * factor,
            y * factor,
            size[1] * factor,
            size[2] * factor,
            angle
        )
    elseif kind == 'Circle' then
        if matrix then
            return katsa.physics.newCircleShape(
                matrix[5] * factor,
                matrix[6] * factor,
                (descriptor.radius or size[1] / 2)
                    * math.sqrt(matrix[1] ^ 2 + matrix[2] ^ 2)
                    * factor
            )
        end
        return katsa.physics.newCircleShape(
            x * factor,
            y * factor,
            (descriptor.radius or size[1] / 2) * factor
        )
    elseif kind == 'Polygon' then
        local vertices = points(descriptor.vertices, factor, x, y, angle, matrix)
        assert(#vertices >= 6 and #vertices <= 16, 'Box2D polygons require 3 to 8 convex vertices')
        local shape = katsa.physics.newPolygonShape(unpack(vertices))
        assert(shape:validate(), 'Polygon2D must be convex and nondegenerate')
        return shape
    elseif kind == 'Edge' then
        return katsa.physics.newEdgeShape(
            unpack(
                points(
                    descriptor.vertices or { -size[1] / 2, 0, size[1] / 2, 0 },
                    factor,
                    x,
                    y,
                    angle,
                    matrix
                )
            )
        )
    elseif kind == 'Chain' then
        return katsa.physics.newChainShape(
            descriptor.loop == true,
            points(descriptor.vertices, factor, x, y, angle, matrix)
        )
    end
    error('Unsupported Collider2D shape: ' .. tostring(kind))
end

function Shapes.createAll(descriptor, factor, resources)
    local kind = descriptor.shape or 'Box'
    local matrix, ellipse = descriptor._transform, false
    if kind == 'Circle' and matrix then
        local xx, yy = matrix[1] ^ 2 + matrix[2] ^ 2, matrix[3] ^ 2 + matrix[4] ^ 2
        ellipse = math.abs(xx - yy) > 0.000001 * math.max(xx, yy)
            or math.abs(matrix[1] * matrix[3] + matrix[2] * matrix[4])
                > 0.000001 * math.max(xx, yy)
    end
    if kind ~= 'Polygon' and kind ~= 'Image' and not ellipse then
        return { Shapes.create(descriptor, factor) }
    end
    local curved
    if ellipse then
        curved = {}
        local radius = descriptor.radius or (descriptor.size or { 32, 32 })[1] / 2
        for i = 0, 63 do
            curved[#curved + 1] = math.cos(i * math.pi / 32) * radius
            curved[#curved + 1] = math.sin(i * math.pi / 32) * radius
        end
    end
    local parts = kind == 'Image' and Image.collect(descriptor, resources)
        or Polygon.parts(curved or descriptor.points or descriptor.vertices)
    assert(
        #parts <= (descriptor.maxFixtures or 1024),
        'Collider2D decomposition exceeds maxFixtures'
    )
    local shapes = {}
    local ok, message = pcall(function()
        for _, vertices in ipairs(parts) do
            local values = vertices
            if kind == 'Image' then
                values = {}
                local size = descriptor.size or { 32, 32 }
                for i = 1, #vertices, 2 do
                    values[i], values[i + 1] = vertices[i] * size[1], -vertices[i + 1] * size[2]
                end
            end
            shapes[#shapes + 1] = Shapes.create({
                shape = 'Polygon',
                vertices = values,
                offset = descriptor.offset,
                rotation = descriptor.rotation,
                _transform = descriptor._transform,
            }, factor)
        end
    end)
    if not ok then
        for _, shape in ipairs(shapes) do
            shape:release()
        end
        error(message, 0)
    end
    return shapes
end

local scalarFields = {
    'shape',
    'image',
    'imagePath',
    'collisionLevel',
    'imageResolution',
    'alphaThreshold',
    'maxFixtures',
    'imageRevision',
    'radius',
    'rotation',
    'loop',
    'enabled',
    'density',
    'friction',
    'restitution',
    'isTrigger',
}
local vectorFields = { 'size', 'offset', 'vertices', 'points', '_transform' }
local empty = {}
local function observe(values, count, changed, value)
    count = count + 1
    value = value == nil and 'default' or value
    changed = values[count] ~= value or changed
    values[count] = value
    return count, changed
end

-- Observe nested manual coordinates without allocating per-body closures each frame.
function Shapes.changed(body, descriptors)
    local values, count, changed = body._shapeInputs or {}, 0, false
    body._shapeInputs = values
    for _, descriptor in ipairs(descriptors) do
        for _, key in ipairs(scalarFields) do
            count, changed = observe(values, count, changed, descriptor[key])
        end
        for _, key in ipairs(vectorFields) do
            local components = descriptor[key] or empty
            count, changed = observe(values, count, changed, #components)
            for i = 1, #components do
                local value = components[i]
                if type(value) == 'table' or type(value) == 'userdata' then
                    count, changed = observe(values, count, changed, #value)
                    for j = 1, #value do
                        count, changed = observe(values, count, changed, value[j])
                    end
                else
                    if key == '_transform' then
                        local previous = values[count + 1]
                        -- Box2D stores angles as floats. Ignore round-trip error,
                        -- retaining the last baked value so small edits accumulate.
                        if
                            type(previous) == 'number'
                            and math.abs(previous - value)
                                <= 0.000001 * math.max(1, math.abs(previous))
                        then
                            value = previous
                        end
                    end
                    count, changed = observe(values, count, changed, value)
                end
            end
        end
    end
    changed = #values ~= count or changed
    for i = #values, count + 1, -1 do
        values[i] = nil
    end
    return changed
end

return Shapes
