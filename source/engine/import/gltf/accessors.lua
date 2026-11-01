local formats = {
    [5120] = { 'b', 1 },
    [5121] = { 'B', 1 },
    [5122] = { 'h', 2 },
    [5123] = { 'H', 2 },
    [5125] = { 'I4', 4 },
    [5126] = {
        'f',
        4,
    },
}
local components = { SCALAR = 1, VEC2 = 2, VEC3 = 3, VEC4 = 4, MAT4 = 16 }
local Accessors = {}

function Accessors.create(document, binary)
    local cache = {}

    local function accessor(index)
        if cache[index] then
            return cache[index]
        end
        local a = assert(document.accessors[index + 1], 'Missing GLB accessor')
        assert(not a.sparse, 'Sparse GLB accessors require conversion')
        local view = assert(document.bufferViews[a.bufferView + 1], 'Missing GLB bufferView')
        local format = assert(formats[a.componentType], 'Unsupported GLB component type')
        local count = assert(components[a.type], 'Unsupported GLB accessor type')
        local stride = view.byteStride or format[2] * count
        local start = (view.byteOffset or 0) + (a.byteOffset or 0) + 1
        assert(
            (a.byteOffset or 0) + (a.count - 1) * stride + count * format[2] <= view.byteLength,
            'GLB accessor exceeds bufferView'
        )
        assert(
            start + (a.count - 1) * stride + count * format[2] - 1 <= #binary,
            'GLB accessor exceeds binary buffer'
        )
        local values = {}
        for i = 0, a.count - 1 do
            local v = {}
            for j = 0, count - 1 do
                local value =
                    katsa.data.unpack('<' .. format[1], binary, start + i * stride + j * format[2])
                if a.normalized and a.componentType ~= 5126 then
                    local divisor = ({
                        [5120] = 127,
                        [5121] = 255,
                        [5122] = 32767,
                        [5123] = 65535,
                        [5125] = 4294967295,
                    })[a.componentType]
                    value = math.max(-1, value / divisor)
                end
                v[j + 1] = value
            end
            values[i + 1] = v
        end
        cache[index] = values
        return values
    end
    return accessor
end

return Accessors
