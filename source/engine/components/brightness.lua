-- Colour multiplier applied after lighting (decals, billboards, particles, ribbons) and the
-- intensity of lights. One definition of the rule: a finite, non-negative number.
local Brightness = {}

local hint = 'Colour multiplier applied after lighting. 1 keeps the colour, 0 is black, values '
    .. 'above 1 brighten.'

function Brightness.check(value, name)
    assert(
        type(value) == 'number' and value >= 0 and value < math.huge,
        name .. '.brightness must be finite and nonnegative'
    )
    return value
end

-- Fills the default when the field is absent, then validates it.
function Brightness.normalize(node, default, name)
    if node.brightness == nil then
        node.brightness = default or 1
    end
    Brightness.check(node.brightness, name or 'Node')
end

function Brightness.describe(class, text)
    local schema = rawget(class, 'propertySchema') or {}
    class.propertySchema = schema
    schema.brightness = schema.brightness or {}
    schema.brightness.min = 0
    schema.brightness.hint = schema.brightness.hint or text or hint
end

return Brightness
