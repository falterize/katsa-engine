local Managed = require('./managedValue')
-- Two Scale/Offset pairs, compatible with existing four-number layout arrays.
local U = {}
local names = {
    ScaleX = 1,
    OffsetX = 2,
    ScaleY = 3,
    OffsetY = 4,
    scaleX = 1,
    offsetX = 2,
    scaleY = 3,
    offsetY = 4,
}

function U.new(sx, ox, sy, oy)
    return Managed.create(U, { sx or 0, ox or 0, sy or 0, oy or 0 }, names, 4, true)
end

function U.fromArray(v)
    assert(#v == 4, 'UDim2 requires four components')
    return U.new(v[1], v[2], v[3], v[4])
end

function U.fromScale(x, y)
    return U.new(x, 0, y, 0)
end

function U.fromOffset(x, y)
    return U.new(0, x, 0, y)
end

function U:resolve(w, h, mode)
    return require('../ui.layout.metrics').resolve(self, w, h, mode)
end
U.toArray, U.clone = Managed.toArray, Managed.clone

function U.__add(a, b)
    return U.new(a[1] + b[1], a[2] + b[2], a[3] + b[3], a[4] + b[4])
end

function U.__sub(a, b)
    return U.new(a[1] - b[1], a[2] - b[2], a[3] - b[3], a[4] - b[4])
end

function U.__mul(a, b)
    if type(a) == 'number' then
        a, b = b, a
    end
    assert(type(b) == 'number', 'UDim2 requires scalar multiplication')
    return U.new(a[1] * b, a[2] * b, a[3] * b, a[4] * b)
end

function U.__div(a, b)
    assert(type(b) == 'number' and b ~= 0, 'Invalid divisor')
    return a * (1 / b)
end

function U:lerp(v, t)
    return self + (U.fromArray(v) - self) * t
end

return U
