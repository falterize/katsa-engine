-- Delaunay triangulation (Bowyer-Watson) of the points of a Blend2D, and the weights of a sample:
-- barycentric inside a triangle, along the nearest hull edge outside. Built once per node.
local Triangulate = {}

local function circle(xs, ys, a, b, c)
    local ax, ay, bx, by, cx, cy = xs[a], ys[a], xs[b], ys[b], xs[c], ys[c]
    local d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    if math.abs(d) < 1e-12 then
        return nil
    end
    local a2, b2, c2 = ax * ax + ay * ay, bx * bx + by * by, cx * cx + cy * cy
    local ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d
    local uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d
    return ux, uy, (ax - ux) ^ 2 + (ay - uy) ^ 2
end

-- points: list of { x, y }. Returns { triangles = { {i, j, k} ... }, edges = hull edges } or nil
-- when the points do not span a plane (fewer than three, or all on one line).
function Triangulate.build(points)
    local n = #points
    if n < 3 then
        return nil
    end
    local xs, ys = {}, {}
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for i, p in ipairs(points) do
        xs[i], ys[i] = p.x, p.y
        minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
        minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
    end
    local span = math.max(maxX - minX, maxY - minY, 1e-6) * 20
    local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
    xs[n + 1], ys[n + 1] = cx - span, cy - span
    xs[n + 2], ys[n + 2] = cx + span, cy - span
    xs[n + 3], ys[n + 3] = cx, cy + span
    local triangles = { { n + 1, n + 2, n + 3 } }
    triangles[1].ux, triangles[1].uy, triangles[1].r2 = circle(xs, ys, n + 1, n + 2, n + 3)
    for i = 1, n do
        local px, py = xs[i], ys[i]
        local bad, kept, edges = {}, {}, {}
        for _, t in ipairs(triangles) do
            if (px - t.ux) ^ 2 + (py - t.uy) ^ 2 < t.r2 * (1 - 1e-12) then
                bad[#bad + 1] = t
            else
                kept[#kept + 1] = t
            end
        end
        local count = {}
        for _, t in ipairs(bad) do
            for k = 1, 3 do
                local a, b = t[k], t[k % 3 + 1]
                local key = math.min(a, b) * 65536 + math.max(a, b)
                count[key] = (count[key] or 0) + 1
                edges[key] = { a, b }
            end
        end
        for key, edge in pairs(edges) do
            if count[key] == 1 then
                local t = { edge[1], edge[2], i }
                t.ux, t.uy, t.r2 = circle(xs, ys, t[1], t[2], t[3])
                if t.ux then
                    kept[#kept + 1] = t
                end
            end
        end
        triangles = kept
    end
    local result, edgeCount, hull = {}, {}, {}
    for _, t in ipairs(triangles) do
        if t[1] <= n and t[2] <= n and t[3] <= n then
            result[#result + 1] = { t[1], t[2], t[3] }
            for k = 1, 3 do
                local a, b = t[k], t[k % 3 + 1]
                local key = math.min(a, b) * 65536 + math.max(a, b)
                edgeCount[key] = (edgeCount[key] or 0) + 1
                hull[key] = { a, b }
            end
        end
    end
    if #result == 0 then
        return nil
    end
    local boundary = {}
    for key, edge in pairs(hull) do
        if edgeCount[key] == 1 then
            boundary[#boundary + 1] = edge
        end
    end
    table.sort(boundary, function(a, b)
        return a[1] * 65536 + a[2] < b[1] * 65536 + b[2]
    end)
    return { triangles = result, edges = boundary }
end

-- Fills `weights` (one per point) for the sample (px, py).
function Triangulate.solve(mesh, points, px, py, weights)
    for i = 1, #points do
        weights[i] = 0
    end
    for _, t in ipairs(mesh.triangles) do
        local a, b, c = points[t[1]], points[t[2]], points[t[3]]
        local d = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        if math.abs(d) > 1e-12 then
            local wa = ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / d
            local wb = ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / d
            local wc = 1 - wa - wb
            if wa >= -1e-9 and wb >= -1e-9 and wc >= -1e-9 then
                weights[t[1]], weights[t[2]], weights[t[3]] = math.max(0, wa), math.max(0, wb), math.max(0, wc)
                return weights
            end
        end
    end
    local best, bestEdge, bestT = math.huge, nil, 0
    for _, edge in ipairs(mesh.edges) do
        local a, b = points[edge[1]], points[edge[2]]
        local vx, vy = b.x - a.x, b.y - a.y
        local square = vx * vx + vy * vy
        local t = square > 1e-12 and math.max(0, math.min(1, ((px - a.x) * vx + (py - a.y) * vy) / square)) or 0
        local dx, dy = px - (a.x + vx * t), py - (a.y + vy * t)
        local distance = dx * dx + dy * dy
        if distance < best then
            best, bestEdge, bestT = distance, edge, t
        end
    end
    weights[bestEdge[1]], weights[bestEdge[2]] = 1 - bestT, bestT
    return weights
end

return Triangulate
