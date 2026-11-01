local Array = require('source.engine.math.array')
-- Rigid transforms: row-major matrices, column vectors, positive Z forward.
-- Scale belongs to Node3D.scale, never to a CFrame. Angles in this API are radians.
local Math = require('source.engine.math.math3d')
local V = require('source.engine.math.vector3')

local CFrame = {}
CFrame.__index = CFrame

local function wrap(m)
    return setmetatable({ matrix = m }, CFrame)
end

function CFrame.new(x, y, z)
    local m = Math.identity()
    if Array.is(x) then
        x, y, z = x[1], x[2], x[3]
    end
    m[4], m[8], m[12] = x or 0, y or 0, z or 0
    return wrap(m)
end

function CFrame.fromMatrix(position, right, up, forward)
    right, up = V.fromArray(right):unit(), V.fromArray(up)
    up = (up - right * right:dot(up)):unit()
    assert(right:magnitude() > 0 and up:magnitude() > 0, 'CFrame basis must be non-degenerate')
    local f = right:cross(up)
    if forward then
        assert(f:dot(V.fromArray(forward):unit()) > 0.999, 'CFrame basis must be right-handed')
    end
    return wrap({
        right[1],
        up[1],
        f[1],
        position[1],
        right[2],
        up[2],
        f[2],
        position[2],
        right[3],
        up[3],
        f[3],
        position[3],
        0,
        0,
        0,
        1,
    })
end

function CFrame.fromEulerAngles(x, y, z)
    return wrap(Math.compose({ 0, 0, 0 }, { math.deg(x), math.deg(y), math.deg(z) }, { 1, 1, 1 }))
end

function CFrame.fromAxisAngle(axis, angle)
    local a = V.fromArray(axis):unit()
    assert(a:magnitude() > 0, 'Rotation axis must be nonzero')
    local s = math.sin(angle / 2)
    return wrap(
        Math.trs({ 0, 0, 0 }, { a[1] * s, a[2] * s, a[3] * s, math.cos(angle / 2) }, { 1, 1, 1 })
    )
end

function CFrame.lookAt(position, target, up)
    local f = (V.fromArray(target) - V.fromArray(position)):unit()
    assert(f:magnitude() > 0, 'lookAt needs distinct positions')
    local u = V.fromArray(up or { 0, 1, 0 }):unit()
    if math.abs(u:dot(f)) > 0.999 then
        u = V.new(1, 0, 0)
    end
    local r = u:cross(f):unit()
    return CFrame.fromMatrix(position, r, f:cross(r), f)
end

function CFrame:position()
    local m = self.matrix
    return V.new(m[4], m[8], m[12])
end

function CFrame:rightVector()
    local m = self.matrix
    return V.new(m[1], m[5], m[9])
end

function CFrame:upVector()
    local m = self.matrix
    return V.new(m[2], m[6], m[10])
end

function CFrame:lookVector()
    local m = self.matrix
    return V.new(m[3], m[7], m[11])
end

function CFrame:pointToWorldSpace(v)
    return V.new(Math.transform(self.matrix, v[1], v[2], v[3]))
end

function CFrame:vectorToWorldSpace(v)
    return V.new(Math.transform(self.matrix, v[1], v[2], v[3], 0))
end

function CFrame:inverse()
    local m = self.matrix
    return wrap({
        m[1],
        m[5],
        m[9],
        -(m[1] * m[4] + m[5] * m[8] + m[9] * m[12]),
        m[2],
        m[6],
        m[10],
        -(m[2] * m[4] + m[6] * m[8] + m[10] * m[12]),
        m[3],
        m[7],
        m[11],
        -(m[3] * m[4] + m[7] * m[8] + m[11] * m[12]),
        0,
        0,
        0,
        1,
    })
end

function CFrame:pointToObjectSpace(v)
    return self:inverse():pointToWorldSpace(v)
end

function CFrame:vectorToObjectSpace(v)
    return self:inverse():vectorToWorldSpace(v)
end

function CFrame:toWorldSpace(other)
    return self * other
end

function CFrame:toObjectSpace(other)
    return self:inverse() * other
end

function CFrame:toEulerAngles()
    local m = self.matrix
    local y = math.asin(math.max(-1, math.min(1, m[9])))
    if math.abs(math.cos(y)) > 1e-7 then
        return math.atan2(m[10], m[11]), y, math.atan2(m[5], m[1])
    end
    return math.atan2(-m[7], m[6]), y, 0
end

local function quaternion(m)
    local q = {}
    local trace = m[1] + m[6] + m[11]
    if trace > 0 then
        local s = math.sqrt(trace + 1) * 2
        q = { (m[10] - m[7]) / s, (m[3] - m[9]) / s, (m[5] - m[2]) / s, s / 4 }
    elseif m[1] > m[6] and m[1] > m[11] then
        local s = math.sqrt(1 + m[1] - m[6] - m[11]) * 2
        q = { s / 4, (m[2] + m[5]) / s, (m[3] + m[9]) / s, (m[10] - m[7]) / s }
    elseif m[6] > m[11] then
        local s = math.sqrt(1 + m[6] - m[1] - m[11]) * 2
        q = { (m[2] + m[5]) / s, s / 4, (m[7] + m[10]) / s, (m[3] - m[9]) / s }
    else
        local s = math.sqrt(1 + m[11] - m[1] - m[6]) * 2
        q = { (m[3] + m[9]) / s, (m[7] + m[10]) / s, s / 4, (m[5] - m[2]) / s }
    end
    return q
end

function CFrame:lerp(other, t)
    local a, b = quaternion(self.matrix), quaternion(other.matrix)
    local dot = 0
    for i = 1, 4 do
        dot = dot + a[i] * b[i]
    end
    if dot < 0 then
        dot = -dot
        for i = 1, 4 do
            b[i] = -b[i]
        end
    end
    local wa, wb = 1 - t, t
    if dot < 0.9995 then
        local angle = math.acos(math.min(1, dot))
        local s = math.sin(angle)
        wa, wb = math.sin((1 - t) * angle) / s, math.sin(t * angle) / s
    end
    local q, n = {}, 0
    for i = 1, 4 do
        q[i] = a[i] * wa + b[i] * wb
        n = n + q[i] ^ 2
    end
    n = math.sqrt(n)
    assert(n > 1e-12, 'Degenerate interpolation')
    for i = 1, 4 do
        q[i] = q[i] / n
    end
    return wrap(Math.trs(self:position():lerp(other:position(), t), q, { 1, 1, 1 }))
end

function CFrame:toMatrix()
    local m = {}
    for i = 1, 16 do
        m[i] = self.matrix[i]
    end
    return m
end

function CFrame.__mul(a, b)
    if getmetatable(b) == CFrame then
        return wrap(Math.multiply(a.matrix, b.matrix))
    end
    return a:pointToWorldSpace(b)
end

return CFrame
