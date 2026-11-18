-- CRC-32 (IEEE 802.3, the checksum ZIP stores). Pure Lua: no engine services.
local bit = require('bit')

local band, bxor, rshift = bit.band, bit.bxor, bit.rshift

local Crc32 = {}

local table_ = {}
for index = 0, 255 do
    local value = index
    for _ = 1, 8 do
        if band(value, 1) == 1 then
            value = bxor(rshift(value, 1), 0xEDB88320)
        else
            value = rshift(value, 1)
        end
    end
    table_[index] = value
end

-- Returns the checksum of `data` as an unsigned integer in 0..2^32-1.
function Crc32.of(data)
    local crc = 0xFFFFFFFF
    local byte = string.byte
    for index = 1, #data do
        crc = bxor(rshift(crc, 8), table_[band(bxor(crc, byte(data, index)), 0xFF)])
    end
    crc = bxor(crc, 0xFFFFFFFF)
    -- bit.* results are signed in LuaJIT; the ZIP field is unsigned.
    if crc < 0 then
        crc = crc + 4294967296
    end
    return crc
end

return Crc32
