local ffi = require('ffi')
local types = {
    [5120] = 'int8_t',
    [5121] = 'uint8_t',
    [5122] = 'int16_t',
    [5123] = 'uint16_t',
    [5125] = 'uint32_t',
    [5126] = 'float',
}
local divisors = { [5120] = 127, [5121] = 255, [5122] = 32767, [5123] = 65535, [5125] = 4294967295 }
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
        local format = assert(formats[a.componentType], 'Unsupported GLB component type')
        local count = assert(components[a.type], 'Unsupported GLB accessor type')
        local ctype = types[a.componentType]
        local size = format[2]
        local row = count * size
        local total = a.count * count
        local data = ffi.new(ctype .. '[?]', total)
        -- A sparse accessor without a bufferView starts as all zeros (Blender exports shape keys
        -- this way); with one, the sparse items replace entries of the dense data.
        if a.bufferView then
            local view = assert(document.bufferViews[a.bufferView + 1], 'Missing GLB bufferView')
            local stride = view.byteStride or row
            local start = (view.byteOffset or 0) + (a.byteOffset or 0) + 1
            assert(
                (a.byteOffset or 0) + (a.count - 1) * stride + row <= view.byteLength,
                'GLB accessor exceeds bufferView'
            )
            assert(
                start + (a.count - 1) * stride + row - 1 <= #binary,
                'GLB accessor exceeds binary buffer'
            )
            -- Components are copied into an aligned typed array (one memcpy when the view is
            -- tightly packed, else per element) instead of unpacking every number from the string.
            local source = ffi.cast('const uint8_t*', binary) + (start - 1)
            if stride == row then
                ffi.copy(data, source, a.count * row)
            else
                for i = 0, a.count - 1 do
                    ffi.copy(data + i * count, source + i * stride, row)
                end
            end
        end
        if a.sparse then
            local sparse = a.sparse
            local indexType = types[sparse.indices.componentType]
            local indexSize = assert(formats[sparse.indices.componentType], 'Bad sparse index type')[2]
            local indexView = assert(document.bufferViews[sparse.indices.bufferView + 1])
            local valueView = assert(document.bufferViews[sparse.values.bufferView + 1])
            local indexStart = (indexView.byteOffset or 0) + (sparse.indices.byteOffset or 0)
            local valueStart = (valueView.byteOffset or 0) + (sparse.values.byteOffset or 0)
            assert(indexStart + sparse.count * indexSize <= #binary, 'GLB sparse indices exceed buffer')
            assert(valueStart + sparse.count * row <= #binary, 'GLB sparse values exceed buffer')
            local indices = ffi.cast(indexType .. '*', ffi.cast('const uint8_t*', binary) + indexStart)
            local values = ffi.cast('const uint8_t*', binary) + valueStart
            for i = 0, sparse.count - 1 do
                local target = tonumber(indices[i])
                assert(target < a.count, 'GLB sparse index exceeds accessor')
                ffi.copy(data + target * count, values + i * row, row)
            end
        end
        local divisor = a.normalized and divisors[a.componentType] or nil
        local values = {}
        for i = 0, a.count - 1 do
            local v = {}
            for j = 0, count - 1 do
                local value = data[i * count + j]
                if divisor then
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
