local ImageCollider = {}

local function hull(points)
    table.sort(points, function(a, b)
        return a[1] == b[1] and a[2] < b[2] or a[1] < b[1]
    end)
    local function cross(a, b, c)
        return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
    end
    local result = {}
    for _, point in ipairs(points) do
        while #result >= 2 and cross(result[#result - 1], result[#result], point) <= 0 do
            table.remove(result)
        end
        result[#result + 1] = point
    end
    local lower = #result
    for i = #points - 1, 1, -1 do
        local point = points[i]
        while #result > lower and cross(result[#result - 1], result[#result], point) <= 0 do
            table.remove(result)
        end
        result[#result + 1] = point
    end
    table.remove(result)
    return result
end

local function build(data, options)
    local width, height = data:getDimensions()
    local resolution = options.imageResolution or 128
    local threshold = options.alphaThreshold or 0.5
    local budget = options.maxFixtures or 1024
    local level = options.collisionLevel or 'Simple'
    assert(
        resolution >= 1 and resolution <= 2048 and resolution % 1 == 0,
        'imageResolution must be an integer from 1 to 2048'
    )
    assert(threshold >= 0 and threshold <= 1, 'alphaThreshold must be between zero and one')
    assert(
        budget >= 1 and budget <= 16384 and budget % 1 == 0,
        'maxFixtures must be an integer from 1 to 16384'
    )
    assert(
        level == 'Simple' or level == 'Convex' or level == 'Detailed',
        'Invalid image collision level'
    )
    local step = math.max(1, math.ceil(math.max(width, height) / resolution))
    local columns, rows = math.ceil(width / step), math.ceil(height / step)
    local cells = {}
    local minX, minY, maxX, maxY = width, height, 0, 0
    -- Scan all source alpha once. Coarse cells conservatively retain thin features.
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local _, _, _, alpha = data:getPixel(x, y)
            if alpha > threshold then
                minX, minY, maxX, maxY =
                    math.min(minX, x),
                    math.min(minY, y),
                    math.max(maxX, x + 1),
                    math.max(maxY, y + 1)
                cells[math.floor(y / step) * columns + math.floor(x / step) + 1] = true
            end
        end
    end
    assert(
        maxX > minX and maxY > minY,
        'Image collider has no opaque pixels at this alphaThreshold'
    )
    local parts = {}
    local function rectangle(x1, y1, x2, y2)
        parts[#parts + 1] = {
            (x1 / width - 0.5),
            (y1 / height - 0.5),
            (x2 / width - 0.5),
            (y1 / height - 0.5),
            (x2 / width - 0.5),
            (y2 / height - 0.5),
            (x1 / width - 0.5),
            (y2 / height - 0.5),
        }
        assert(
            #parts <= budget,
            'Image collision exceeds maxFixtures; lower imageResolution or use Convex'
        )
    end
    if level == 'Simple' then
        rectangle(minX, minY, maxX, maxY)
    elseif level == 'Convex' then
        local points = {}
        for y = 0, rows - 1 do
            for x = 0, columns - 1 do
                if cells[y * columns + x + 1] then
                    local x1, y1, x2, y2 =
                        x * step / width - 0.5,
                        y * step / height - 0.5,
                        math.min(width, (x + 1) * step) / width - 0.5,
                        math.min(height, (y + 1) * step) / height - 0.5
                    points[#points + 1], points[#points + 2] = { x1, y1 }, { x2, y1 }
                    points[#points + 1], points[#points + 2] = { x2, y2 }, { x1, y2 }
                end
            end
        end
        local boundary, vertices = hull(points), {}
        for _, point in ipairs(boundary) do
            vertices[#vertices + 1], vertices[#vertices + 2] = point[1], point[2]
        end
        if #vertices <= 16 then
            parts[1] = vertices
        else
            -- A fan preserves the convex silhouette beyond Box2D's eight-vertex limit.
            for i = 3, #vertices - 2, 2 do
                parts[#parts + 1] = {
                    vertices[1],
                    vertices[2],
                    vertices[i],
                    vertices[i + 1],
                    vertices[i + 2],
                    vertices[i + 3],
                }
            end
            assert(#parts <= budget, 'Convex image collision exceeds maxFixtures')
        end
    else
        -- Disjoint rectangles preserve holes and disconnected islands without a concave fixture.
        for y = 0, rows - 1 do
            for x = 0, columns - 1 do
                local index = y * columns + x + 1
                if cells[index] then
                    local right = x + 1
                    while right < columns and cells[y * columns + right + 1] do
                        right = right + 1
                    end
                    local bottom = y + 1
                    while bottom < rows do
                        local complete = true
                        for column = x, right - 1 do
                            if not cells[bottom * columns + column + 1] then
                                complete = false
                                break
                            end
                        end
                        if not complete then
                            break
                        end
                        bottom = bottom + 1
                    end
                    for row = y, bottom - 1 do
                        for column = x, right - 1 do
                            cells[row * columns + column + 1] = nil
                        end
                    end
                    rectangle(
                        x * step,
                        y * step,
                        math.min(width, right * step),
                        math.min(height, bottom * step)
                    )
                end
            end
        end
    end
    return parts
end

function ImageCollider.collect(descriptor, resources)
    local image = descriptor.image or descriptor.imagePath
    assert(type(image) == 'string' and image ~= '', 'Image Collider2D requires an image path')
    local canonical = resources and resources:canonical(image) or image
    local key = table.concat({
        canonical,
        descriptor.collisionLevel or 'Simple',
        descriptor.imageResolution or 128,
        descriptor.alphaThreshold or 0.5,
        descriptor.maxFixtures or 1024,
        descriptor.imageRevision or 0,
    }, '|')
    if descriptor._imageKey ~= key then
        local data = love.image.newImageData(canonical)
        local ok, parts = pcall(build, data, descriptor)
        data:release()
        if not ok then
            error(parts, 0)
        end
        descriptor._imageParts, descriptor._imageKey = parts, key
    end
    return descriptor._imageParts
end

return ImageCollider
