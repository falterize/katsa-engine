-- Merges the solid cells of a layer into few rectangles (runs along X, then stacked equal runs
-- along Y), so a level needs dozens of box colliders instead of thousands.
local Colliders = {}

-- Returns a list of { x, y, w, h } in cells (x, y = top-left cell, y grows downward).
function Colliders.rects(layer, tileSet)
    local rows, minY, maxY = {}, math.huge, -math.huge
    layer:each(function(x, y, id)
        if tileSet:isSolid(id) then
            rows[y] = rows[y] or {}
            rows[y][#rows[y] + 1] = x
            minY, maxY = math.min(minY, y), math.max(maxY, y)
        end
    end)
    local rects, open = {}, {}
    for y = minY, maxY do
        local xs = rows[y] or {}
        table.sort(xs)
        local runs, start, previous = {}, nil, nil
        for _, x in ipairs(xs) do
            if previous and x == previous + 1 then
                previous = x
            else
                if start then
                    runs[#runs + 1] = { start, previous }
                end
                start, previous = x, x
            end
        end
        if start then
            runs[#runs + 1] = { start, previous }
        end
        local continuing = {}
        for _, run in ipairs(runs) do
            local above = open[run[1] .. ':' .. run[2]]
            if above then
                above.h = above.h + 1
                continuing[run[1] .. ':' .. run[2]] = above
            else
                local rect = { x = run[1], y = y, w = run[2] - run[1] + 1, h = 1 }
                rects[#rects + 1] = rect
                continuing[run[1] .. ':' .. run[2]] = rect
            end
        end
        open = continuing
    end
    return rects
end

return Colliders
