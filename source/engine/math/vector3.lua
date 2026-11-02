local Managed = require('./managedValue')

local Vector3 = {}
local components = { X = 1, Y = 2, Z = 3, x = 1, y = 2, z = 3 }

function Vector3.new(x, y, z)
    return Managed.create(Vector3, { x or 0, y or 0, z or 0 }, components, 3, true)
end

function Vector3.fromArray(v)
    return Vector3.new(v[1], v[2], v[3])
end

function Vector3:dot(v)
    return self[1] * v[1] + self[2] * v[2] + self[3] * v[3]
end

function Vector3:cross(v)
    return Vector3.new(
        self[2] * v[3] - self[3] * v[2],
        self[3] * v[1] - self[1] * v[3],
        self[1] * v[2] - self[2] * v[1]
    )
end

function Vector3:magnitude()
    return math.sqrt(self:dot(self))
end

function Vector3:unit()
    local n = self:magnitude()
    return n > 1e-12 and self / n or Vector3.new()
end

function Vector3:lerp(v, t)
    return self + (v - self) * t
end
Vector3.toArray, Vector3.clone = Managed.toArray, Managed.clone

function Vector3.__add(a, b)
    return Vector3.new(a[1] + b[1], a[2] + b[2], a[3] + b[3])
end

function Vector3.__sub(a, b)
    return Vector3.new(a[1] - b[1], a[2] - b[2], a[3] - b[3])
end

function Vector3.__unm(a)
    return Vector3.new(-a[1], -a[2], -a[3])
end

function Vector3.__mul(a, b)
    if type(a) == 'number' then
        a, b = b, a
    end
    assert(type(b) == 'number', 'Vector3 multiplication requires a scalar; use dot or cross')
    return Vector3.new(a[1] * b, a[2] * b, a[3] * b)
end

function Vector3.__div(a, b)
    assert(type(b) == 'number' and b ~= 0, 'Invalid vector divisor')
    return a * (1 / b)
end

function Vector3.__tostring(v)
    return string.format('Vector3(%.6g, %.6g, %.6g)', v[1], v[2], v[3])
end

return Vector3
