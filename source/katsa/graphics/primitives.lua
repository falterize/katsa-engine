-- Lines, polygons, circles and points.

local State = require('source.katsa.graphics.state')
local Batch = require('source.katsa.graphics.batch')
local S = State.S
local G = State.G

local function triangle(x1, y1, x2, y2, x3, y3)
    Batch.reserve(3, nil)
    local r, g, b, a = Batch.packColor()
    local t = S.transform
    -- Inlined transform: a local closure here was allocated for every triangle (thousands per
    -- frame with rounded UI corners) and made the collector run every few frames.
    local t1, t2, t3, t4, t5, t6 = t[1], t[2], t[3], t[4], t[5], t[6]
    Batch.push(t1 * x1 + t3 * y1 + t5, t2 * x1 + t4 * y1 + t6, 0, 0, r, g, b, a)
    Batch.push(t1 * x2 + t3 * y2 + t5, t2 * x2 + t4 * y2 + t6, 0, 0, r, g, b, a)
    Batch.push(t1 * x3 + t3 * y3 + t5, t2 * x3 + t4 * y3 + t6, 0, 0, r, g, b, a)
end

local function fillPolygon(points)
    -- Triangle fan from the first vertex (convex shapes), like katsa's fill mode.
    for i = 3, #points / 2 do
        triangle(points[1], points[2], points[2 * i - 3], points[2 * i - 2], points[2 * i - 1],
            points[2 * i])
    end
end

local function polyline(points, closed)
    local width = S.lineWidth
    local half = width * 0.5
    local n = #points / 2
    local segments = closed and n or n - 1
    local px, py
    local normals = {}
    for i = 1, segments do
        local x1, y1 = points[2 * i - 1], points[2 * i]
        local j = i % n + 1
        local x2, y2 = points[2 * j - 1], points[2 * j]
        local dx, dy = x2 - x1, y2 - y1
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0 then
            local nx, ny = -dy / length * half, dx / length * half
            triangle(x1 + nx, y1 + ny, x1 - nx, y1 - ny, x2 + nx, y2 + ny)
            triangle(x2 + nx, y2 + ny, x1 - nx, y1 - ny, x2 - nx, y2 - ny)
            normals[i] = { nx, ny, x1, y1, x2, y2 }
        end
    end
    -- Joins: fill the wedge on the outer side with a bevel triangle.
    if S.lineJoin ~= 'none' and half > 0.5 then
        local count = closed and segments or segments - 1
        for i = 1, count do
            local a, b = normals[i], normals[i % segments + 1]
            if a and b then
                local cross = (a[5] - a[3]) * (b[6] - b[4]) - (a[6] - a[4]) * (b[5] - b[3])
                local sign = cross > 0 and -1 or 1
                triangle(a[5], a[6], a[5] + sign * a[1], a[6] + sign * a[2], a[5] + sign * b[1],
                    a[6] + sign * b[2])
            end
        end
    end
end

function G.line(...)
    State.requireReady()
    local points = { ... }
    if type(points[1]) == 'table' then
        points = points[1]
        if type(points[1]) == 'table' then
            local flat = {}
            for _, p in ipairs(points) do
                flat[#flat + 1], flat[#flat + 2] = p[1], p[2]
            end
            points = flat
        end
    end
    assert(#points >= 4, 'Need at least two vertices to draw a line')
    Batch.setBatchTexture(nil)
    polyline(points, false)
end

function G.polygon(mode, ...)
    State.requireReady()
    local points = { ... }
    if type(points[1]) == 'table' then
        points = points[1]
    end
    assert(#points >= 6, 'Need at least three vertices to draw a polygon')
    Batch.setBatchTexture(nil)
    if mode == 'fill' then
        fillPolygon(points)
    else
        polyline(points, true)
    end
end

function G.rectangle(mode, x, y, w, h, rx, ry, segments)
    State.requireReady()
    Batch.setBatchTexture(nil)
    local points
    if rx and rx > 0 then
        ry = ry or rx
        rx, ry = math.min(rx, w / 2), math.min(ry, h / 2)
        segments = segments or math.max(4, math.floor(math.sqrt(math.max(rx, ry)) * 2))
        points = {}
        local corners = {
            { x + w - rx, y + ry, -math.pi / 2 }, { x + w - rx, y + h - ry, 0 },
            { x + rx, y + h - ry, math.pi / 2 }, { x + rx, y + ry, math.pi },
        }
        for _, corner in ipairs(corners) do
            for i = 0, segments do
                local angle = corner[3] + (i / segments) * math.pi / 2
                points[#points + 1] = corner[1] + math.cos(angle) * rx
                points[#points + 1] = corner[2] + math.sin(angle) * ry
            end
        end
    else
        points = { x, y, x + w, y, x + w, y + h, x, y + h }
    end
    if mode == 'fill' then
        fillPolygon(points)
    else
        polyline(points, true)
    end
end

function G.circle(mode, x, y, radius, segments)
    State.requireReady()
    Batch.setBatchTexture(nil)
    segments = segments or math.max(8, math.floor(radius > 0 and math.sqrt(radius) * 4 or 8))
    local points = {}
    for i = 0, segments - 1 do
        local angle = i / segments * math.pi * 2
        points[#points + 1] = x + math.cos(angle) * radius
        points[#points + 1] = y + math.sin(angle) * radius
    end
    if mode == 'fill' then
        fillPolygon(points)
    else
        polyline(points, true)
    end
end

function G.points(...)
    State.requireReady()
    local pts = { ... }
    if type(pts[1]) == 'table' then
        pts = pts[1]
    end
    Batch.setBatchTexture(nil)
    local half = S.pointSize * 0.5
    for i = 1, #pts - 1, 2 do
        local x, y = pts[i], pts[i + 1]
        triangle(x - half, y - half, x + half, y - half, x - half, y + half)
        triangle(x + half, y - half, x + half, y + half, x - half, y + half)
    end
end
