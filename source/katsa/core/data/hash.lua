-- Hash functions (md5, sha1, sha224, sha256). sha384/sha512 are not provided.

local bit = require('bit')
local band = bit.band
local bor = bit.bor
local bxor = bit.bxor
local bnot = bit.bnot
local rol = bit.rol
local ror = bit.ror
local rshift = bit.rshift
local lshift = bit.lshift
local tobit = bit.tobit
local char, byte, rep = string.char, string.byte, string.rep

local M = {}

local function bigEndian32(value)
    return char(band(rshift(value, 24), 255), band(rshift(value, 16), 255),
        band(rshift(value, 8), 255), band(value, 255))
end

local function padMessage(message, blockSize, lengthBytes, littleEndian)
    local length = #message
    local padding = blockSize - ((length + 1 + lengthBytes) % blockSize)
    if padding == blockSize then
        padding = 0
    end
    local bits = length * 8
    local tail = {}
    if littleEndian then
        for i = 0, 7 do
            tail[#tail + 1] = char(math.floor(bits / 2 ^ (8 * i)) % 256)
        end
    else
        for i = lengthBytes - 1, 0, -1 do
            tail[#tail + 1] = char(math.floor(bits / 2 ^ (8 * i)) % 256)
        end
    end
    return message .. '\128' .. rep('\0', padding) .. table.concat(tail)
end

local k256 = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function sha256(message, initial, outputWords)
    local h = {}
    for i = 1, 8 do
        h[i] = tobit(initial[i])
    end
    message = padMessage(message, 64, 8)
    local w = {}
    for chunk = 1, #message, 64 do
        for i = 0, 15 do
            local p = chunk + i * 4
            w[i] = bor(lshift(byte(message, p), 24), lshift(byte(message, p + 1), 16),
                lshift(byte(message, p + 2), 8), byte(message, p + 3))
        end
        for i = 16, 63 do
            local s0 = bxor(ror(w[i - 15], 7), ror(w[i - 15], 18), rshift(w[i - 15], 3))
            local s1 = bxor(ror(w[i - 2], 17), ror(w[i - 2], 19), rshift(w[i - 2], 10))
            w[i] = tobit(w[i - 16] + s0 + w[i - 7] + s1)
        end
        local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
        for i = 0, 63 do
            local S1 = bxor(ror(e, 6), ror(e, 11), ror(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local t1 = hh + S1 + ch + k256[i + 1] + w[i]
            local S0 = bxor(ror(a, 2), ror(a, 13), ror(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            local t2 = S0 + maj
            hh, g, f, e, d, c, b, a = g, f, e, tobit(d + t1), c, b, a, tobit(t1 + t2)
        end
        h[1], h[2], h[3], h[4] = tobit(h[1] + a), tobit(h[2] + b), tobit(h[3] + c), tobit(h[4] + d)
        h[5], h[6], h[7], h[8] = tobit(h[5] + e), tobit(h[6] + f), tobit(h[7] + g), tobit(h[8] + hh)
    end
    local out = {}
    for i = 1, outputWords do
        out[i] = bigEndian32(h[i])
    end
    return table.concat(out)
end

local function sha1(message)
    local h0 = 0x67452301
    local h1 = tobit(0xEFCDAB89)
    local h2 = tobit(0x98BADCFE)
    local h3 = 0x10325476
    local h4 = tobit(0xC3D2E1F0)
    message = padMessage(message, 64, 8)
    local w = {}
    for chunk = 1, #message, 64 do
        for i = 0, 15 do
            local p = chunk + i * 4
            w[i] = bor(lshift(byte(message, p), 24), lshift(byte(message, p + 1), 16),
                lshift(byte(message, p + 2), 8), byte(message, p + 3))
        end
        for i = 16, 79 do
            w[i] = rol(bxor(w[i - 3], w[i - 8], w[i - 14], w[i - 16]), 1)
        end
        local a, b, c, d, e = h0, h1, h2, h3, h4
        for i = 0, 79 do
            local f, k
            if i < 20 then
                f, k = bor(band(b, c), band(bnot(b), d)), 0x5A827999
            elseif i < 40 then
                f, k = bxor(b, c, d), 0x6ED9EBA1
            elseif i < 60 then
                f, k = bor(band(b, c), band(b, d), band(c, d)), tobit(0x8F1BBCDC)
            else
                f, k = bxor(b, c, d), tobit(0xCA62C1D6)
            end
            local temp = rol(a, 5) + f + e + k + w[i]
            e, d, c, b, a = d, c, rol(b, 30), a, tobit(temp)
        end
        h0 = tobit(h0 + a)
        h1 = tobit(h1 + b)
        h2 = tobit(h2 + c)
        h3 = tobit(h3 + d)
        h4 = tobit(h4 + e)
    end
    return bigEndian32(h0) .. bigEndian32(h1) .. bigEndian32(h2) .. bigEndian32(h3)
        .. bigEndian32(h4)
end

local md5S = {
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
}
local md5K = {}
for i = 0, 63 do
    md5K[i] = tobit(math.floor(math.abs(math.sin(i + 1)) * 2 ^ 32))
end

local function littleEndian32(value)
    return char(band(value, 255), band(rshift(value, 8), 255), band(rshift(value, 16), 255),
        band(rshift(value, 24), 255))
end

local function md5(message)
    local a0, b0, c0, d0 = 0x67452301, tobit(0xefcdab89), tobit(0x98badcfe), 0x10325476
    message = padMessage(message, 64, 8, true)
    local m = {}
    for chunk = 1, #message, 64 do
        for i = 0, 15 do
            local p = chunk + i * 4
            m[i] = bor(byte(message, p), lshift(byte(message, p + 1), 8),
                lshift(byte(message, p + 2), 16), lshift(byte(message, p + 3), 24))
        end
        local a, b, c, d = a0, b0, c0, d0
        for i = 0, 63 do
            local f, g
            if i < 16 then
                f, g = bor(band(b, c), band(bnot(b), d)), i
            elseif i < 32 then
                f, g = bor(band(d, b), band(bnot(d), c)), (5 * i + 1) % 16
            elseif i < 48 then
                f, g = bxor(b, c, d), (3 * i + 5) % 16
            else
                f, g = bxor(c, bor(b, bnot(d))), (7 * i) % 16
            end
            f = f + a + md5K[i] + m[g]
            a, d, c = d, c, b
            b = tobit(b + rol(tobit(f), md5S[i + 1]))
        end
        a0, b0, c0, d0 = tobit(a0 + a), tobit(b0 + b), tobit(c0 + c), tobit(d0 + d)
    end
    return littleEndian32(a0) .. littleEndian32(b0) .. littleEndian32(c0) .. littleEndian32(d0)
end

local initial256 = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}
local initial224 = {
    0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939, 0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4,
}

local hashes = {
    md5 = md5,
    sha1 = sha1,
    sha256 = function(m)
        return sha256(m, initial256, 8)
    end,
    sha224 = function(m)
        return sha256(m, initial224, 7)
    end,
}

-- Returns the binary digest. sha384/sha512 are not provided.
function M.hash(algorithm, message)
    local implementation = hashes[algorithm]
    assert(implementation, 'Unsupported hash algorithm: ' .. tostring(algorithm))
    assert(type(message) == 'string', 'hash expects a string')
    return implementation(message)
end

return M
