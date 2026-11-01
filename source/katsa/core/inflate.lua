-- Pure Lua DEFLATE/zlib/gzip decoder (no native dependency, works inside a fused executable).
local bit = require('bit')
local band, rshift, lshift = bit.band, bit.rshift, bit.lshift
local byte, char, concat = string.byte, string.char, table.concat

local Inflate = {}

local lengthBase = {
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
    35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
}
local lengthExtra = {
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
    3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
}
local distanceBase = {
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
    257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
}
local distanceExtra = {
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
    7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
}
local order = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- Canonical Huffman table: counts per length and symbols sorted by code.
local function build(lengths, count)
    local counts, offsets, symbols = {}, {}, {}
    for i = 0, 15 do
        counts[i] = 0
    end
    for i = 0, count - 1 do
        counts[lengths[i]] = counts[lengths[i]] + 1
    end
    counts[0] = 0
    offsets[1] = 0
    for i = 1, 14 do
        offsets[i + 1] = offsets[i] + counts[i]
    end
    for i = 0, count - 1 do
        local length = lengths[i]
        if length ~= 0 then
            symbols[offsets[length]] = i
            offsets[length] = offsets[length] + 1
        end
    end
    return { counts = counts, symbols = symbols }
end

local fixedLiteral, fixedDistance
local function fixedTables()
    if not fixedLiteral then
        local lengths = {}
        for i = 0, 143 do
            lengths[i] = 8
        end
        for i = 144, 255 do
            lengths[i] = 9
        end
        for i = 256, 279 do
            lengths[i] = 7
        end
        for i = 280, 287 do
            lengths[i] = 8
        end
        fixedLiteral = build(lengths, 288)
        local distances = {}
        for i = 0, 29 do
            distances[i] = 5
        end
        fixedDistance = build(distances, 30)
    end
    return fixedLiteral, fixedDistance
end

-- Raw deflate stream starting at byte position `start` (1-based). Returns the data and the next position.
function Inflate.raw(data, start)
    local position, bitBuffer, bitCount = start or 1, 0, 0
    local length = #data
    local out, outSize = {}, 0
    local window = {} -- last 32 KiB for back references, as a flat array of byte values
    local total = 0

    local function need(n)
        while bitCount < n do
            local value = byte(data, position)
            assert(value, 'Unexpected end of deflate stream')
            position = position + 1
            bitBuffer = bitBuffer + lshift(value, bitCount)
            bitCount = bitCount + 8
        end
    end
    local function bits(n)
        if n == 0 then
            return 0
        end
        need(n)
        local value = band(bitBuffer, lshift(1, n) - 1)
        bitBuffer = rshift(bitBuffer, n)
        bitCount = bitCount - n
        return value
    end
    local function decode(table_)
        local code, first, index = 0, 0, 0
        local counts = table_.counts
        for len = 1, 15 do
            code = code + bits(1)
            local count = counts[len]
            if code - count < first then
                return table_.symbols[index + (code - first)]
            end
            index = index + count
            first = (first + count) * 2
            code = code * 2
        end
        error('Invalid Huffman code')
    end

    local pieces, pieceSize = {}, 0
    local function emit(valueList, n)
        -- valueList is a Lua array of byte values; flush in chunks to bound memory.
        for i = 1, n do
            outSize = outSize + 1
            out[outSize] = valueList[i]
        end
        if outSize >= 4096 then
            pieceSize = pieceSize + 1
            local chunks = {}
            for i = 1, outSize, 4096 do
                chunks[#chunks + 1] = char(unpack(out, i, math.min(i + 4095, outSize)))
            end
            pieces[pieceSize] = concat(chunks)
            for i = 1, outSize do
                out[i] = nil
            end
            outSize = 0
        end
    end

    -- History kept in `history` (ring) for matches.
    local history, historyPosition = {}, 0
    local function put(value)
        historyPosition = historyPosition % 32768 + 1
        history[historyPosition] = value
        outSize = outSize + 1
        out[outSize] = value
        total = total + 1
        if outSize >= 4096 then
            pieceSize = pieceSize + 1
            pieces[pieceSize] = char(unpack(out, 1, outSize))
            outSize = 0
        end
    end

    repeat
        local final = bits(1)
        local kind = bits(2)
        if kind == 0 then
            bitBuffer, bitCount = 0, 0
            local len = byte(data, position) + byte(data, position + 1) * 256
            local nlen = byte(data, position + 2) + byte(data, position + 3) * 256
            assert(band(len, 0xFFFF) == band(bit.bnot(nlen), 0xFFFF), 'Stored block length mismatch')
            position = position + 4
            for i = 0, len - 1 do
                put(byte(data, position + i))
            end
            position = position + len
        elseif kind == 1 or kind == 2 then
            local literal, distance
            if kind == 1 then
                literal, distance = fixedTables()
            else
                local nlen = bits(5) + 257
                local ndist = bits(5) + 1
                local ncode = bits(4) + 4
                local lengths = {}
                for i = 0, 18 do
                    lengths[i] = 0
                end
                for i = 1, ncode do
                    lengths[order[i]] = bits(3)
                end
                local lencode = build(lengths, 19)
                local index = 0
                local all = {}
                while index < nlen + ndist do
                    local symbol = decode(lencode)
                    if symbol < 16 then
                        all[index] = symbol
                        index = index + 1
                    else
                        local previous, repeatCount = 0, 0
                        if symbol == 16 then
                            previous = all[index - 1]
                            repeatCount = 3 + bits(2)
                        elseif symbol == 17 then
                            repeatCount = 3 + bits(3)
                        else
                            repeatCount = 11 + bits(7)
                        end
                        for _ = 1, repeatCount do
                            all[index] = previous
                            index = index + 1
                        end
                    end
                end
                local literalLengths, distanceLengths = {}, {}
                for i = 0, nlen - 1 do
                    literalLengths[i] = all[i]
                end
                for i = 0, ndist - 1 do
                    distanceLengths[i] = all[nlen + i]
                end
                literal = build(literalLengths, nlen)
                distance = build(distanceLengths, ndist)
            end
            while true do
                local symbol = decode(literal)
                if symbol < 256 then
                    put(symbol)
                elseif symbol == 256 then
                    break
                else
                    symbol = symbol - 257
                    local matchLength = lengthBase[symbol + 1] + bits(lengthExtra[symbol + 1])
                    local distanceSymbol = decode(distance)
                    local matchDistance = distanceBase[distanceSymbol + 1]
                        + bits(distanceExtra[distanceSymbol + 1])
                    assert(matchDistance <= total, 'Invalid deflate distance')
                    for _ = 1, matchLength do
                        local index = (historyPosition - matchDistance) % 32768 + 1
                        put(history[index])
                    end
                end
            end
        else
            error('Invalid deflate block type')
        end
    until final == 1
    if outSize > 0 then
        pieceSize = pieceSize + 1
        pieces[pieceSize] = char(unpack(out, 1, outSize))
    end
    return concat(pieces), position - math.floor(bitCount / 8)
end

function Inflate.zlib(data)
    assert(#data >= 6, 'zlib stream too short')
    local cmf, flg = byte(data, 1), byte(data, 2)
    assert(band(cmf, 15) == 8 and (cmf * 256 + flg) % 31 == 0, 'Invalid zlib header')
    assert(band(flg, 32) == 0, 'zlib preset dictionaries are not supported')
    return (Inflate.raw(data, 3))
end

function Inflate.gzip(data)
    assert(byte(data, 1) == 0x1f and byte(data, 2) == 0x8b, 'Invalid gzip header')
    local flags = byte(data, 4)
    local position = 11
    if band(flags, 4) ~= 0 then
        position = position + 2 + byte(data, position) + byte(data, position + 1) * 256
    end
    if band(flags, 8) ~= 0 then
        position = data:find('\0', position, true) + 1
    end
    if band(flags, 16) ~= 0 then
        position = data:find('\0', position, true) + 1
    end
    if band(flags, 2) ~= 0 then
        position = position + 2
    end
    return (Inflate.raw(data, position))
end

return Inflate
