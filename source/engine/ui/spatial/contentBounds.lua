local ipairs = require('source.engine.math.array').ipairs

local ContentBounds = {}

function ContentBounds.measure(list, x, y, bounds)
    for _, node in ipairs(list) do
        if node.visible then
            local nx, ny = node._x or x + node.x, node._y or y + node.y
            local width, height = node._width or node.width, node._height or node.height
            local right, bottom = nx + width, ny + height
            if node._clip then
                nx = math.max(nx, node._clip[1])
                ny = math.max(ny, node._clip[2])
                right = math.min(right, node._clip[3])
                bottom = math.min(bottom, node._clip[4])
            end
            bounds[1], bounds[2] = math.min(bounds[1], nx), math.min(bounds[2], ny)
            bounds[3], bounds[4] = math.max(bounds[3], right), math.max(bounds[4], bottom)
            ContentBounds.measure(node.children, nx, ny, bounds)
        end
    end
end

return ContentBounds
