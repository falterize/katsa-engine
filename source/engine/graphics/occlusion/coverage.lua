local ipairs = require('../../math.array').ipairs
-- Conservative convex coverage, shared by object and triangle rejection.
local Coverage = {}

function Coverage.describe(polygon)
    local edges = {}
    polygon.edges = edges
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, #polygon do
        local a, b = polygon[i], polygon[i % #polygon + 1]
        x1, y1, x2, y2 =
            math.min(x1, a[1]), math.min(y1, a[2]), math.max(x2, a[1]), math.max(y2, a[2])
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local sign = polygon.sign
        local c = sign * (dy * a[1] - dx * a[2])
        edges[i] = { -dy * sign, dx * sign, c - math.sqrt(dx * dx + dy * dy) * 1.00001, c }
    end
    polygon.x1, polygon.y1, polygon.x2, polygon.y2 = x1, y1, x2, y2
end

local function behind(depth, polygon)
    return depth > polygon.depth + math.max(0.001, polygon.depth * 0.00001)
end

function Coverage.inside(points, polygon)
    if not polygon.edges then
        Coverage.describe(polygon)
    end
    for _, edge in ipairs(polygon.edges) do
        for j = 1, #points, 2 do
            if edge[1] * points[j] + edge[2] * points[j + 1] + edge[3] <= 0 then
                return false
            end
        end
    end
    return true
end

function Coverage.single(points, depth, polygon)
    return behind(depth, polygon) and Coverage.inside(points, polygon)
end

local function hasArea(points)
    if #points < 6 then
        return false
    end
    local ax, ay = points[1], points[2]
    for i = 3, #points - 2, 2 do
        if
            (points[i] - ax) * (points[i + 3] - ay)
                - (points[i + 1] - ay) * (points[i + 2] - ax)
            ~= 0
        then
            return true
        end
    end
    return false
end

local function split(points, edge, pool, used)
    local inside, outside = pool[used + 1], pool[used + 2]
    if not inside then
        inside = {}
        pool[used + 1] = inside
    end
    if not outside then
        outside = {}
        pool[used + 2] = outside
    end
    local insideCount, outsideCount = 0, 0
    local px, py = points[#points - 1], points[#points]
    local pd = edge[1] * px + edge[2] * py + edge[4]
    for i = 1, #points, 2 do
        local x, y = points[i], points[i + 1]
        local d = edge[1] * x + edge[2] * y + edge[4]
        if (pd > 0) ~= (d > 0) then
            local t = pd / (pd - d)
            local ix, iy = px + (x - px) * t, py + (y - py) * t
            inside[insideCount + 1], inside[insideCount + 2] = ix, iy
            outside[outsideCount + 1], outside[outsideCount + 2] = ix, iy
            insideCount, outsideCount = insideCount + 2, outsideCount + 2
        end
        if d > 0 then
            inside[insideCount + 1], inside[insideCount + 2] = x, y
            insideCount = insideCount + 2
        else
            outside[outsideCount + 1], outside[outsideCount + 2] = x, y
            outsideCount = outsideCount + 2
        end
        px, py, pd = x, y, d
    end
    for i = #inside, insideCount + 1, -1 do
        inside[i] = nil
    end
    for i = #outside, outsideCount + 1, -1 do
        outside[i] = nil
    end
    return inside, outside, used + 2
end

function Coverage.union(points, depth, polygons, object, state)
    -- A bounded exact polygon subtraction joins coverage without filling holes.
    -- Expand the target, rather than shrinking each occluder: shared seams stay closed.
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, #points, 2 do
        x1, y1, x2, y2 =
            math.min(x1, points[i]),
            math.min(y1, points[i + 1]),
            math.max(x2, points[i]),
            math.max(y2, points[i + 1])
    end
    x1, y1, x2, y2 = x1 - 1.00001, y1 - 1.00001, x2 + 1.00001, y2 + 1.00001
    -- Scratch arrays are unique within this subtraction and reused only by the
    -- next query. At most 192 edge splits bound the retained numeric storage.
    local scratch = state.coverageScratch
    if not scratch then
        scratch = { points = {}, lists = {} }
        state.coverageScratch = scratch
    end
    local pool, lists = scratch.points, scratch.lists
    local rectangle = pool[1]
    if not rectangle then
        rectangle = {}
        pool[1] = rectangle
    end
    rectangle[1], rectangle[2], rectangle[3], rectangle[4] = x1, y1, x2, y1
    rectangle[5], rectangle[6], rectangle[7], rectangle[8] = x2, y2, x1, y2
    local pieces = lists[1]
    if not pieces then
        pieces = {}
        lists[1] = pieces
    end
    pieces[1] = rectangle
    for i = #pieces, 2, -1 do
        pieces[i] = nil
    end
    local work, used, listCount = 0, 1, 1
    for _, polygon in ipairs(polygons) do
        if
            (not object or polygon.object ~= object)
            and behind(depth, polygon)
            and x1 < polygon.x2
            and x2 > polygon.x1
            and y1 < polygon.y2
            and y2 > polygon.y1
        then
            listCount = listCount + 1
            local remaining = lists[listCount]
            if not remaining then
                remaining = {}
                lists[listCount] = remaining
            end
            local remainingCount = 0
            for _, piece in ipairs(pieces) do
                local inside = piece
                for i = 1, #polygon do
                    work = work + 1
                    if work > 192 or remainingCount > 32 or state.unionBudget <= 0 then
                        return false
                    end
                    state.unionBudget = state.unionBudget - 1
                    local outside
                    inside, outside, used = split(inside, polygon.edges[i], pool, used)
                    if hasArea(outside) then
                        remainingCount = remainingCount + 1
                        remaining[remainingCount] = outside
                    end
                    if not hasArea(inside) then
                        break
                    end
                end
            end
            for i = #remaining, remainingCount + 1, -1 do
                remaining[i] = nil
            end
            pieces = remaining
            if remainingCount == 0 then
                return true
            end
        end
    end
    return false
end

function Coverage.test(points, depth, polygons, object, state)
    local eligible = 0
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, #points, 2 do
        x1, y1, x2, y2 =
            math.min(x1, points[i]),
            math.min(y1, points[i + 1]),
            math.max(x2, points[i]),
            math.max(y2, points[i + 1])
    end
    for _, polygon in ipairs(polygons) do
        if not polygon.edges then
            Coverage.describe(polygon)
        end
        if
            (not object or polygon.object ~= object)
            and behind(depth, polygon)
            and x1 < polygon.x2
            and x2 > polygon.x1
            and y1 < polygon.y2
            and y2 > polygon.y1
        then
            eligible = eligible + 1
            if
                x1 > polygon.x1
                and x2 < polygon.x2
                and y1 > polygon.y1
                and y2 < polygon.y2
                and Coverage.inside(points, polygon)
            then
                return true
            end
        end
    end
    if eligible > 1 and state and state.unionBudget > 0 then
        return Coverage.union(points, depth, polygons, object, state)
    end
    return false
end

return Coverage
