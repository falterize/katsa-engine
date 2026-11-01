local Transform = {}
local zero, one = { 0, 0 }, { 1, 1 }

local function rounded(value)
    -- Rotation cancellation must not rebuild static geometry from floating error.
    return math.floor(value * 1e9 + 0.5) / 1e9
end

function Transform.descriptors(body, descriptors)
    local object = body.object
    if not object.getWorldTransform then
        return descriptors
    end
    local a, b, c, d, x, y, rotation = object:getWorldTransform()
    local co, si = math.cos(math.rad(-rotation)), math.sin(math.rad(-rotation))
    local result = body._scaledDescriptors or {}
    body._scaledDescriptors = result
    for i, descriptor in ipairs(descriptors) do
        local copy = result[i] or {}
        result[i] = copy
        for key in pairs(copy) do
            if key ~= '_transform' then
                copy[key] = nil
            end
        end
        for key, value in pairs(descriptor) do
            copy[key] = value
        end
        local ca, cb, cc, cd, cx, cy
        if descriptor._nodeOwner then
            ca, cb, cc, cd, cx, cy = descriptor._nodeOwner:getWorldTransform()
        else
            local angle = math.rad(descriptor.rotation or 0)
            local cosine, sine = math.cos(angle), math.sin(angle)
            local offset, scale = descriptor.offset or zero, descriptor.scale or one
            ca, cb = (a * cosine + c * sine) * scale[1], (b * cosine + d * sine) * scale[1]
            cc, cd = (-a * sine + c * cosine) * scale[2], (-b * sine + d * cosine) * scale[2]
            cx, cy = x + a * offset[1] + c * offset[2], y + b * offset[1] + d * offset[2]
        end
        local matrix = copy._transform or {}
        copy._transform = matrix
        matrix[1], matrix[2] = rounded(co * ca - si * cb), rounded(si * ca + co * cb)
        matrix[3], matrix[4] = rounded(co * cc - si * cd), rounded(si * cc + co * cd)
        matrix[5], matrix[6] =
            rounded(co * (cx - x) - si * (cy - y)), rounded(si * (cx - x) + co * (cy - y))
    end
    for i = #result, #descriptors + 1, -1 do
        result[i] = nil
    end
    return result
end

return Transform
