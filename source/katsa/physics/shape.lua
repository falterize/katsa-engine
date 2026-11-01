-- Shapes: circle, rectangle, polygon, edge and chain, plus distance between fixtures.

local ffi = require('ffi')
local Binding = require('source.katsa.physics.binding')
local Scale = require('source.katsa.physics.scale')
local Object = require('source.katsa.physics.object')
local B, up, down, quad, six = Binding.lib, Scale.up, Scale.down, Binding.quad, Binding.six

local M = {}
local Shape = Object.class('Shape')
local shapeNames = { [0] = 'circle', 'edge', 'polygon', 'chain' }

local function newShape(handle, owned)
    local self = setmetatable({ _h = handle }, Shape)
    if owned then
        self._h = ffi.gc(handle, B().kb2_shape_free)
    end
    return self
end

local function points(args)
    local list = args
    if type(args[1]) == 'table' then
        list = args[1]
    end
    local out = ffi.new('float[?]', math.max(#list, 2))
    for i = 1, #list do
        out[i - 1] = down(list[i])
    end
    return out, #list / 2
end

function M.newCircleShape(a, b, c)
    local x, y, r = 0, 0, a
    if c ~= nil then
        x, y, r = a, b, c
    end
    return newShape(B().kb2_shape_circle(down(x), down(y), down(r)), true)
end

function M.newRectangleShape(a, b, c, d, e)
    local x, y, w, h, angle = 0, 0, a, b, 0
    if c ~= nil then
        x, y, w, h, angle = a, b, c, d, e or 0
    end
    return newShape(B().kb2_shape_box(down(w) / 2, down(h) / 2, down(x), down(y), angle), true)
end

function M.newPolygonShape(...)
    local pts, n = points({ ... })
    local handle = B().kb2_shape_polygon(pts, n)
    if handle == nil then
        error('Physics error: polygon needs 3 to 8 vertices forming a valid convex hull', 2)
    end
    return newShape(handle, true)
end

function M.newEdgeShape(x1, y1, x2, y2)
    return newShape(B().kb2_shape_edge(down(x1), down(y1), down(x2), down(y2)), true)
end

function M.newChainShape(loop, ...)
    local pts, n = points({ ... })
    assert(n >= 2, 'Physics error: chain shapes need at least two vertices')
    return newShape(B().kb2_shape_chain(pts, n, loop and 1 or 0), true)
end

function Shape:getType()
    return shapeNames[B().kb2_shape_type(self._h)]
end

function Shape:getRadius()
    return up(B().kb2_shape_radius(self._h))
end

function Shape:setRadius(r)
    B().kb2_shape_set_radius(self._h, down(r))
end

function Shape:getChildCount()
    return
    B().kb2_shape_child_count(self._h)
end

function Shape:getPoints()
    local buffer = ffi.new('float[16]')
    local n = B().kb2_shape_points(self._h, buffer, 8)
    local out = {}
    for i = 0, n * 2 - 1 do
        out[#out + 1] = up(buffer[i])
    end
    return unpack(out)
end

function Shape:getPoint()
    local buffer = ffi.new('float[2]')
    B().kb2_shape_points(self._h, buffer, 1)
    return up(buffer[0]), up(buffer[1])
end

function Shape:getVertexCount()
    local buffer = ffi.new('float[16]')
    return B().kb2_shape_points(self._h, buffer, 8)
end

function Shape:getPoints2()
    return self:getPoints()
end

function Shape:testPoint(x, y, angle, px, py)
    return B().kb2_shape_test_point(self._h, down(x), down(y), angle, down(px), down(py)) ~= 0
end

function Shape:rayCast(x1, y1, x2, y2, maxFraction, tx, ty, angle, child)
    local hit = B().kb2_shape_raycast(self._h, down(x1), down(y1), down(x2), down(y2), maxFraction,
        down(tx), down(ty), angle, (child or 1) - 1, six)
    if hit == 0 then
        return nil
    end
    return six[0], six[1], six[2]
end

function Shape:computeAABB(x, y, angle, child)
    B().kb2_shape_aabb(self._h, down(x), down(y), angle, (child or 1) - 1, quad)
    return up(quad[0]), up(quad[1]), up(quad[2]), up(quad[3])
end

function Shape:computeMass(density)
    B().kb2_shape_mass(self._h, density, quad)
    return up(quad[0]), up(quad[1]), quad[2], up(up(quad[3]))
end

function M.getDistance(a, b)
    local ax, ay = a._body:getPosition()
    local bx, by = b._body:getPosition()
    local distance = B().kb2_distance(a:getShape()._h, 0, down(ax), down(ay), a._body:getAngle(),
        b:getShape()._h, 0, down(bx), down(by), b._body:getAngle())
    return up(distance), ax, ay, bx, by
end

function M.wrap(handle)
    return newShape(handle, false)
end

M.class = Shape

return M
