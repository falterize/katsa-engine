-- Replicated property types: how a value is written, compared, copied and interpolated.
-- Vectors are arrays ({ x, y } / { x, y, z }), as everywhere in the engine.
local Types = {}

local function scalar(name)
    return {
        write = function(writer, value)
            writer[name](writer, value)
        end,
        read = function(reader)
            return reader[name](reader)
        end,
        equals = function(a, b)
            return a == b
        end,
        copy = function(value)
            return value
        end,
        lerp = function(a, b, t)
            return a + (b - a) * t
        end,
    }
end

local function vector(size)
    return {
        write = function(writer, value)
            for index = 1, size do
                writer:f32(value[index] or 0)
            end
        end,
        read = function(reader)
            local value = {}
            for index = 1, size do
                value[index] = reader:f32()
            end
            return value
        end,
        equals = function(a, b)
            for index = 1, size do
                if math.abs((a[index] or 0) - (b[index] or 0)) > 1e-4 then
                    return false
                end
            end
            return true
        end,
        copy = function(value)
            local result = {}
            for index = 1, size do
                result[index] = value[index] or 0
            end
            return result
        end,
        lerp = function(a, b, t)
            local result = {}
            for index = 1, size do
                result[index] = (a[index] or 0) + ((b[index] or 0) - (a[index] or 0)) * t
            end
            return result
        end,
    }
end

local function discrete(name)
    local type_ = scalar(name)
    type_.lerp = function(a, b, t)
        return t < 1 and a or b
    end
    return type_
end

Types.f32 = scalar('f32')
Types.f64 = scalar('f64')
Types.u8 = discrete('u8')
Types.u16 = discrete('u16')
Types.i32 = discrete('i32')
Types.bool = discrete('bool')
Types.string = discrete('string')
Types.vec2 = vector(2)
Types.vec3 = vector(3)

-- Degrees, 16-bit quantized; interpolation takes the shortest way around.
Types.angle = scalar('angle')
Types.angle.equals = function(a, b)
    local difference = math.abs((a - b + 180) % 360 - 180)
    return difference < 0.01
end
Types.angle.lerp = function(a, b, t)
    return a + ((b - a + 180) % 360 - 180) * t
end

function Types.get(name)
    return assert(Types[name], 'Unknown replicated type: ' .. tostring(name))
end

return Types
