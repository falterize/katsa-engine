local Polygon = {}

function Polygon.flatten(values)
    assert(type(values) == 'table', 'Expected a table of 2D points')
    local result = {}
    if type(values[1]) == 'table' or type(values[1]) == 'userdata' then
        for _, point in ipairs(values) do
            result[#result + 1], result[#result + 2] = point[1], point[2]
        end
    else
        for i = 1, #values do
            result[i] = values[i]
        end
    end
    assert(#result >= 6 and #result % 2 == 0, 'A polygon requires at least three 2D points')
    for _, value in ipairs(result) do
        assert(
            type(value) == 'number' and value == value and math.abs(value) < math.huge,
            'Polygon points must be finite numbers'
        )
    end
    return result
end

function Polygon.parts(values)
    local flat = Polygon.flatten(values)
    local sign, convex = 0, true
    for i = 1, #flat, 2 do
        local j, k = (i + 1) % #flat + 1, (i + 3) % #flat + 1
        local cross = (flat[j] - flat[i]) * (flat[k + 1] - flat[j + 1])
            - (flat[j + 1] - flat[i + 1]) * (flat[k] - flat[j])
        if math.abs(cross) > 0.000001 then
            local current = cross > 0 and 1 or -1
            if sign ~= 0 and sign ~= current then
                convex = false
            end
            sign = current
        end
    end
    assert(sign ~= 0, 'Polygon points are collinear')
    if convex and #flat <= 16 then
        return { flat }
    end
    return katsa.math.triangulate(flat)
end

return Polygon
