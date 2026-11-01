local Managed = require('source.engine.math.managedValue')

local Color = {}
local names = {
    r = 1,
    g = 2,
    b = 3,
    a = 4,
    R = 1,
    G = 2,
    B = 3,
    A = 4,
    x = 1,
    y = 2,
    z = 3,
    w = 4,
    X = 1,
    Y = 2,
    Z = 3,
    W = 4,
}

function Color.new(r, g, b, a)
    return Managed.create(Color, { r or 0, g or 0, b or 0, a }, names, a ~= nil and 4 or 3, true)
end

function Color.fromArray(value)
    assert(#value == 3 or #value == 4, 'Color requires three or four components')
    return Color.new(value[1], value[2], value[3], value[4])
end
Color.toArray, Color.clone = Managed.toArray, Managed.clone
return Color
