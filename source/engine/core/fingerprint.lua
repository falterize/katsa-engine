-- A fast content fingerprint for cache keys (model sidecars, extracted native libraries).
-- It reads every byte of the data but is a hundred times cheaper than the pure-Lua SHA-256 in
-- katsa.data, which spent half of a model scene's load time hashing 8 MB files. It is an integrity
-- key for our own caches, not a security hash: use katsa.data.hash for anything untrusted.
local ffi = require('ffi')
local bit = require('bit')
local bxor, tobit = bit.bxor, bit.tobit

local Fingerprint = {}

local MOD = 4294967296

-- Returns "<length>-<16 hex digits>".
function Fingerprint.of(bytes)
    local length = #bytes
    local words = math.floor(length / 4)
    local pointer = ffi.cast('const uint32_t*', bytes)
    local a, b = tobit(2166136261), 5381
    -- Products stay below 2^48, so the doubles are exact and tobit wraps them to 32 bits.
    for i = 0, words - 1 do
        local w = pointer[i]
        a = tobit(bxor(a, tobit(w)) * 40503)
        b = tobit(b + w * (i % 65521 + 1))
    end
    -- The trailing 0-3 bytes.
    for i = words * 4 + 1, length do
        local byte = bytes:byte(i)
        a = tobit(bxor(a, byte) * 40503)
        b = tobit(b + byte * 31)
    end
    return ('%d-%08x%08x'):format(length, a % MOD, b % MOD)
end

return Fingerprint
