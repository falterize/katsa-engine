-- G.711 μ-law: 16-bit PCM <-> 8-bit companded bytes (2:1, speech-grade). Used by voice chat.
--
--   local bytes = MuLaw.encode(pcm, count)        -- pcm: int16 cdata/table (1-based for tables), -> string
--   local pcm = MuLaw.decode(bytes)               -- -> int16[n] cdata (0-based) and the sample count
local ffi = require('ffi')

local MuLaw = {}

local BIAS, CLIP = 0x84, 32635
local decodeTable = ffi.new('int16_t[256]')
for byte = 0, 255 do
    local value = bit.bxor(byte, 0xFF)
    local sign = bit.band(value, 0x80)
    local exponent = bit.band(bit.rshift(value, 4), 0x07)
    local mantissa = bit.band(value, 0x0F)
    local sample = bit.lshift(bit.bor(bit.lshift(mantissa, 3), 0x84), exponent) - BIAS
    decodeTable[byte] = sign ~= 0 and -sample or sample
end

local function encodeSample(sample)
    local sign = 0
    if sample < 0 then
        sample, sign = -sample, 0x80
    end
    if sample > CLIP then
        sample = CLIP
    end
    sample = sample + BIAS
    local exponent = 7
    local mask = 0x4000
    while exponent > 0 and bit.band(sample, mask) == 0 do
        exponent, mask = exponent - 1, bit.rshift(mask, 1)
    end
    local mantissa = bit.band(bit.rshift(sample, exponent + 3), 0x0F)
    return bit.bxor(bit.bor(sign, bit.lshift(exponent, 4), mantissa), 0xFF)
end

function MuLaw.encodeSample(sample)
    return encodeSample(sample)
end

function MuLaw.decodeSample(byte)
    return decodeTable[byte]
end

-- `samples` is a 0-based int16 cdata array or a 1-based Lua table; returns a byte string.
function MuLaw.encode(samples, count)
    local out = ffi.new('uint8_t[?]', count)
    if type(samples) == 'table' then
        for index = 1, count do
            out[index - 1] = encodeSample(samples[index])
        end
    else
        for index = 0, count - 1 do
            out[index] = encodeSample(samples[index])
        end
    end
    return ffi.string(out, count)
end

-- Returns an int16 cdata array and its length.
function MuLaw.decode(bytes)
    local count = #bytes
    local out = ffi.new('int16_t[?]', count)
    for index = 0, count - 1 do
        out[index] = decodeTable[bytes:byte(index + 1)]
    end
    return out, count
end

return MuLaw
