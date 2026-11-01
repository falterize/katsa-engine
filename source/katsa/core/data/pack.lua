-- love.data.pack / unpack with the format subset used by the engine.

local ffi = require('ffi')
local char, byte, format = string.char, string.byte, string.format

local M = {}

-- love.data.pack / unpack with the format subset used by the engine:
-- endianness (< > =), b B h H i I l L j J with optional sizes, f d, s[n], z, x, and spaces.
local function parse(fmt)
    local items, little, i = {}, true, 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        i = i + 1
        local size = fmt:match('^%d+', i)
        if size then
            i = i + #size
            size = tonumber(size)
        end
        if c == '<' or c == '=' then
            little = true
        elseif c == '>' then
            little = false
        elseif c == ' ' then
            -- ignored
        elseif c == 'b' then
            items[#items + 1] = { 'int', 1, true, little }
        elseif c == 'B' then
            items[#items + 1] = { 'int', 1, false, little }
        elseif c == 'h' then
            items[#items + 1] = { 'int', 2, true, little }
        elseif c == 'H' then
            items[#items + 1] = { 'int', 2, false, little }
        elseif c == 'i' then
            items[#items + 1] = { 'int', size or 4, true, little }
        elseif c == 'I' then
            items[#items + 1] = { 'int', size or 4, false, little }
        elseif c == 'l' or c == 'j' then
            items[#items + 1] = { 'int', 8, true, little }
        elseif c == 'L' or c == 'J' then
            items[#items + 1] = { 'int', 8, false, little }
        elseif c == 'f' then
            items[#items + 1] = { 'float', 4, true, little }
        elseif c == 'd' or c == 'n' then
            items[#items + 1] = { 'float', 8, true, little }
        elseif c == 's' then
            items[#items + 1] = { 'string', size or 4, false, little }
        elseif c == 'z' then
            items[#items + 1] = { 'zero' }
        elseif c == 'x' then
            items[#items + 1] = { 'pad' }
        else
            error('Invalid pack format option: ' .. c)
        end
    end
    return items
end

local float4, float8 = ffi.new('float[1]'), ffi.new('double[1]')

function M.pack(container, fmt, ...)
    local out, args = {}, { ... }
    local index = 1
    for _, item in ipairs(parse(fmt)) do
        local kind, size, signed, little = item[1], item[2], item[3], item[4]
        if kind == 'int' then
            local value = args[index]
            index = index + 1
            assert(type(value) == 'number', 'pack expects a number')
            local bytes = {}
            local v = value
            if v < 0 then
                v = v + 2 ^ (size * 8)
            end
            for b = 0, size - 1 do
                bytes[b + 1] = char(math.floor(v / 2 ^ (8 * b)) % 256)
            end
            if not little then
                local reversed = {}
                for b = size, 1, -1 do
                    reversed[#reversed + 1] = bytes[b]
                end
                bytes = reversed
            end
            out[#out + 1] = table.concat(bytes)
        elseif kind == 'float' then
            local value = args[index]
            index = index + 1
            local cell = size == 4 and float4 or float8
            cell[0] = value
            local raw = ffi.string(cell, size)
            out[#out + 1] = little and raw or raw:reverse()
        elseif kind == 'string' then
            local value = args[index]
            index = index + 1
            local header = M.pack('string', (little and '<' or '>') .. 'I' .. size, #value)
            out[#out + 1] = header .. value
        elseif kind == 'zero' then
            out[#out + 1] = args[index] .. '\0'
            index = index + 1
        else
            out[#out + 1] = '\0'
        end
    end
    return table.concat(out)
end

-- Returns the values followed by the next position (love.data.unpack contract).
function M.unpack(fmt, data, position)
    position = position or 1
    local results = {}
    for _, item in ipairs(parse(fmt)) do
        local kind, size, signed, little = item[1], item[2], item[3], item[4]
        if kind == 'int' then
            assert(position + size - 1 <= #data, 'unpack: data string too short')
            local value = 0
            for b = 0, size - 1 do
                local byteValue = byte(data, little and position + size - 1 - b or position + b)
                value = value * 256 + byteValue
            end
            if signed and value >= 2 ^ (size * 8 - 1) then
                value = value - 2 ^ (size * 8)
            end
            results[#results + 1] = value
            position = position + size
        elseif kind == 'float' then
            assert(position + size - 1 <= #data, 'unpack: data string too short')
            local raw = data:sub(position, position + size - 1)
            if not little then
                raw = raw:reverse()
            end
            local cell = size == 4 and float4 or float8
            ffi.copy(cell, raw, size)
            results[#results + 1] = tonumber(cell[0])
            position = position + size
        elseif kind == 'string' then
            local length = M.unpack((little and '<' or '>') .. 'I' .. size, data, position)
            position = position + size
            results[#results + 1] = data:sub(position, position + length - 1)
            position = position + length
        elseif kind == 'zero' then
            local stop = data:find('\0', position, true)
            results[#results + 1] = data:sub(position, stop - 1)
            position = stop + 1
        else
            position = position + 1
        end
    end
    results[#results + 1] = position
    return unpack(results)
end

return M
