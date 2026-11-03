-- Centre-line sources for ribbons: a Beam3D curve between two attachments and a Trail3D history of
-- positions. Both fill `node._points` (see geometry.lua) once per rendered frame from the render
-- (interpolated) pose, so motion stays smooth between physics steps.
local Geometry = require('./geometry')
local Lifetime = require('./lifetime')
local M = require('../math.math3d')

local sqrt = math.sqrt

local Source = {}

local normalize = function(x, y, z)
    local ux, uy, uz = M.unit(x, y, z)
    return ux, uy, uz
end

local function usable(node)
    return node ~= nil and not node.destroyed and node.getRenderWorldMatrix ~= nil
end

local function opacity(node)
    return node:getEffectiveOpacity()
end

-- Writes colour / width / opacity of one point from the lifetime ramp at ramp coordinate t.
local function style(node, point, t, widthScale)
    local color = Lifetime.sample(node, 'color', t, point.color)
    point.color = color
    local alpha = 1 - Lifetime.sample(node, 'transparency', t)
    local tint = node.color
    point.r, point.g, point.b = color[1] * tint[1], color[2] * tint[2], color[3] * tint[3]
    point.a = math.max(0, math.min(1, alpha)) * opacity(node)
    point.width = point.width * math.max(0, Lifetime.sample(node, 'width', t)) * widthScale
end

-- Beam3D ----------------------------------------------------------------------------------------

local scratch = { {}, {}, {}, {} }

function Source.beam(node)
    local a0, a1 = node.attachment0, node.attachment1
    if not usable(a0) or not usable(a1) then
        return 0
    end
    local m0, m1 = a0:getRenderWorldMatrix(), a1:getRenderWorldMatrix()
    local p0, c0, c1, p1 = scratch[1], scratch[2], scratch[3], scratch[4]
    p0[1], p0[2], p0[3] = m0[4], m0[8], m0[12]
    p1[1], p1[2], p1[3] = m1[4], m1[8], m1[12]
    local x0, y0, z0 = normalize(m0[1], m0[5], m0[9])
    local x1, y1, z1 = normalize(m1[1], m1[5], m1[9])
    c0[1], c0[2], c0[3] = p0[1] + x0 * node.curveSize0, p0[2] + y0 * node.curveSize0, p0[3] + z0 * node.curveSize0
    c1[1], c1[2], c1[3] = p1[1] + x1 * node.curveSize1, p1[2] + y1 * node.curveSize1, p1[3] + z1 * node.curveSize1
    local segments = math.max(1, math.min(128, math.floor(node.segments * (node._detail or 1))))
    local points = node._points
    local length = Geometry.curve(points, p0, c0, c1, p1, segments, node.width0, node.width1)
    local n = segments + 1
    node._length = length
    node._normal = node._normal or {}
    -- The face normal of a flat (non camera facing) beam is the first attachment's up axis.
    node._normal[1], node._normal[2], node._normal[3] = normalize(m0[2], m0[6], m0[10])
    local dx, dy, dz = normalize(p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3])
    for i = 1, n do
        local point = points[i]
        point.u = nil
        point.staticU = (point.x * dx + point.y * dy + point.z * dz)
        style(node, point, point.t, 1)
    end
    return n
end

-- Trail3D ---------------------------------------------------------------------------------------

local function state(node)
    local trail = node._trail
    if not trail then
        trail = { ring = {}, head = 1, size = 0, capacity = 0, travel = 0, time = nil }
        node._trail = trail
    end
    return trail
end

function Source.clear(node)
    local trail = node._trail
    if trail then
        trail.head, trail.size, trail.travel, trail.live = 1, 0, 0, nil
    end
end

local function record(trail, index)
    return trail.ring[(trail.head + index - 2) % trail.capacity + 1]
end

local function push(trail, capacity)
    if trail.capacity ~= capacity then
        -- The cap changed: rebuild the ring so indices stay consistent.
        local old, size = trail.ring, trail.size
        local oldCapacity, head = trail.capacity, trail.head
        trail.ring, trail.capacity, trail.head = {}, capacity, 1
        local keep = math.min(size, capacity)
        for i = 1, keep do
            trail.ring[i] = old[(head + size - keep + i - 2) % oldCapacity + 1]
        end
        trail.size = keep
    end
    if trail.size == capacity then
        trail.head = trail.head % capacity + 1
        trail.size = trail.size - 1
    end
    local slot = (trail.head + trail.size - 1) % capacity + 1
    local item = trail.ring[slot] or {}
    trail.ring[slot] = item
    trail.size = trail.size + 1
    return item
end

-- Reads the current head pose into `live` (centre, side vector and base width). Returns false when
-- the node cannot be drawn. Single mode follows one node (attachment0, or the Trail3D itself) and
-- always turns toward the camera; Dual mode needs both nodes, which mark the two edges.
local function readHead(node, live)
    local a0, a1 = node.attachment0, node.attachment1
    if node.trailMode == 'Dual' then
        if not (usable(a0) and usable(a1)) then
            return false
        end
        local m0, m1 = a0:getRenderWorldMatrix(), a1:getRenderWorldMatrix()
        live.x, live.y, live.z = (m0[4] + m1[4]) * 0.5, (m0[8] + m1[8]) * 0.5, (m0[12] + m1[12]) * 0.5
        live.sx, live.sy, live.sz = m0[4] - m1[4], m0[8] - m1[8], m0[12] - m1[12]
        live.width = sqrt(live.sx ^ 2 + live.sy ^ 2 + live.sz ^ 2)
        live.paired = true
        return true
    end
    local source = usable(a0) and a0 or node
    local m = source:getRenderWorldMatrix()
    live.x, live.y, live.z = m[4], m[8], m[12]
    live.sx, live.sy, live.sz = 0, 0, 0
    live.width = node.width
    live.paired = false
    return true
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return sqrt(dx * dx + dy * dy + dz * dz)
end

function Source.sampleTrail(node, time)
    local trail = state(node)
    local live = trail.live or {}
    trail.live = live
    if not readHead(node, live) then
        Source.clear(node)
        return
    end
    if node.enabled == false then
        return
    end
    local capacity = math.max(2, math.min(1024, math.floor(node.maxPoints * (node._detail or 1))))
    local newest = trail.size > 0 and record(trail, trail.size)
    if newest and node.breakDistance > 0 and distance(live, newest) > node.breakDistance then
        Source.clear(node)
        trail.live = live
        newest = nil
    end
    if trail.time == nil or time > trail.time then
        trail.time = time
        while trail.size > 0 and time - record(trail, 1).time > node.lifetime do
            trail.head = trail.head % trail.capacity + 1
            trail.size = trail.size - 1
        end
        newest = trail.size > 0 and record(trail, trail.size)
    end
    if not newest or distance(live, newest) >= node.minLength / (node._detail or 1) then
        if newest then
            trail.travel = trail.travel + distance(live, newest)
        end
        local item = push(trail, capacity)
        item.x, item.y, item.z = live.x, live.y, live.z
        item.sx, item.sy, item.sz, item.width = live.sx, live.sy, live.sz, live.width
        item.paired, item.time, item.travel = live.paired, time, trail.travel
        if node.maxLength > 0 then
            -- Drop the oldest points once the path from the head exceeds maxLength.
            local total = 0
            local previous = item
            for i = trail.size - 1, 1, -1 do
                local current = record(trail, i)
                total = total + distance(previous, current)
                if total > node.maxLength then
                    trail.head = (trail.head + i - 1) % trail.capacity + 1
                    trail.size = trail.size - i
                    break
                end
                previous = current
            end
        end
    end
end

-- Fills node._points head first (live pose, then newest to oldest). Returns the point count.
function Source.trail(node, time)
    local trail = node._trail
    if not trail or not trail.live then
        return 0
    end
    local points = node._points
    local live = trail.live
    local n = 0
    local travel = trail.size > 0 and (record(trail, trail.size).travel + distance(live, record(trail, trail.size)))
        or 0
    local distanceFromHead = 0
    local previous
    local lifetime = math.max(1e-4, node.lifetime)
    local function add(source, age, pointTravel)
        n = n + 1
        local point = points[n] or {}
        points[n] = point
        point.x, point.y, point.z = source.x, source.y, source.z
        if previous then
            distanceFromHead = distanceFromHead + distance(previous, point)
        end
        point.distance = distanceFromHead
        point.width = source.width
        point.fixed = source.paired and not node.faceCamera
        if point.fixed then
            point.sx, point.sy, point.sz = source.sx, source.sy, source.sz
        end
        point.u = nil
        point.staticU = pointTravel
        point.t = math.min(1, math.max(0, age / lifetime))
        style(node, point, point.t, 1)
        previous = point
    end
    add(live, 0, travel)
    for i = trail.size, 1, -1 do
        local item = record(trail, i)
        add(item, time - item.time, item.travel)
    end
    for i = #points, n + 1, -1 do
        points[i] = nil
    end
    node._length = distanceFromHead
    return n
end

return Source
