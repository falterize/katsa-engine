local Managed = require('source.engine.math.managedValue')
-- Array-compatible value; Scale/Offset aliases are useful for scalar UI lengths.
local V = {}
local fields = { X = 1, Y = 2, x = 1, y = 2, Scale = 1, Offset = 2, scale = 1, offset = 2 }

function V.new(x, y)
    return Managed.create(V, { x or 0, y or 0 }, fields, 2, true)
end

function V.fromArray(v)
    return V.new(v[1], v[2])
end
V.toArray, V.clone = Managed.toArray, Managed.clone

function V:dot(v)
    return self[1] * v[1] + self[2] * v[2]
end

function V:magnitude()
    return math.sqrt(self:dot(self))
end

function V:unit()
    local n = self:magnitude()
    return n > 1e-12 and self / n or V.new()
end

function V:lerp(v, t)
    return self + (V.fromArray(v) - self) * t
end

function V.__add(a, b)
    return V.new(a[1] + b[1], a[2] + b[2])
end

function V.__sub(a, b)
    return V.new(a[1] - b[1], a[2] - b[2])
end

function V.__unm(a)
    return V.new(-a[1], -a[2])
end

function V.__mul(a, b)
    if type(a) == 'number' then
        a, b = b, a
    end
    assert(type(b) == 'number', 'Vector2 requires scalar multiplication')
    return V.new(a[1] * b, a[2] * b)
end

function V.__div(a, b)
    assert(type(b) == 'number' and b ~= 0, 'Invalid divisor')
    return a * (1 / b)
end

function V.__tostring(v)
    return string.format('Vector2(%g, %g)', v[1], v[2])
end

return V
