-- LZMA and LZMA2 decoders (the compression used by 7z archives). Written from the public format
-- description; the decoder output buffer doubles as the dictionary because 7z always supplies the
-- unpacked size.
local ffi = require('ffi')
local bit = require('bit')
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local floor, min = math.floor, math.min

local PROB_INIT = 1024
local MATCH_MIN = 2

local Lzma = {}

-- Probability model ------------------------------------------------------------------------------

local function newProbs(count)
    local probs = ffi.new('uint16_t[?]', count)
    for i = 0, count - 1 do
        probs[i] = PROB_INIT
    end
    return probs
end

local function newLengthCoder()
    return {
        choice = newProbs(2),
        low = newProbs(16 * 8),
        mid = newProbs(16 * 8),
        high = newProbs(256),
    }
end

local Decoder = {}
Decoder.__index = Decoder

function Decoder:resetState()
    local lc, lp = self.lc, self.lp
    self.isMatch = newProbs(12 * 16)
    self.isRep = newProbs(12)
    self.isRepG0 = newProbs(12)
    self.isRepG1 = newProbs(12)
    self.isRepG2 = newProbs(12)
    self.isRep0Long = newProbs(12 * 16)
    self.posSlot = newProbs(4 * 64)
    self.posSpecial = newProbs(128)
    self.align = newProbs(16)
    self.lengths = newLengthCoder()
    self.repLengths = newLengthCoder()
    self.literal = newProbs(0x300 * lshift(1, lc + lp))
    self.state = 0
    self.rep0, self.rep1, self.rep2, self.rep3 = 0, 0, 0, 0
end

function Decoder:setProperties(byte)
    assert(byte < 9 * 5 * 5, 'Invalid LZMA properties')
    self.lc = byte % 9
    self.lp = floor(byte / 9) % 5
    self.pb = floor(byte / 45)
    self:resetState()
end

-- Range decoder
-- ------------------------------------------------------------------------------------

-- Starts a new range-coded stream at input position `position` (1-based, string index).
function Decoder:startRange(input, position)
    assert(input:byte(position) == 0, 'Corrupt LZMA stream')
    local code = 0
    for i = 1, 4 do
        code = code * 256 + input:byte(position + i)
    end
    self.input, self.cursor = input, position + 5
    self.range, self.code = 4294967295, code
end

local function decodeBit(self, probs, index)
    local p = probs[index]
    local range = self.range
    local bound = floor(range / 2048) * p
    local result
    if self.code < bound then
        range = bound
        probs[index] = p + rshift(2048 - p, 5)
        result = 0
    else
        range = range - bound
        self.code = self.code - bound
        probs[index] = p - rshift(p, 5)
        result = 1
    end
    if range < 16777216 then
        range = range * 256
        self.code = self.code * 256 + (self.input:byte(self.cursor) or 0)
        self.cursor = self.cursor + 1
    end
    self.range = range
    return result
end

local function decodeDirect(self, count)
    local value = 0
    for _ = 1, count do
        local range = floor(self.range / 2)
        local bitValue = 0
        if self.code >= range then
            self.code = self.code - range
            bitValue = 1
        end
        if range < 16777216 then
            range = range * 256
            self.code = self.code * 256 + (self.input:byte(self.cursor) or 0)
            self.cursor = self.cursor + 1
        end
        self.range = range
        value = value * 2 + bitValue
    end
    return value
end

local function bitTree(self, probs, base, bits)
    local m = 1
    for _ = 1, bits do
        m = m * 2 + decodeBit(self, probs, base + m)
    end
    return m - lshift(1, bits)
end

local function reverseBitTree(self, probs, base, bits)
    local m, symbol = 1, 0
    for i = 0, bits - 1 do
        local b = decodeBit(self, probs, base + m)
        m = m * 2 + b
        symbol = symbol + lshift(b, i)
    end
    return symbol
end

local function decodeLength(self, coder, posState)
    if decodeBit(self, coder.choice, 0) == 0 then
        return bitTree(self, coder.low, posState * 8, 3)
    elseif decodeBit(self, coder.choice, 1) == 0 then
        return 8 + bitTree(self, coder.mid, posState * 8, 3)
    end
    return 16 + bitTree(self, coder.high, 0, 8)
end

local function decodeDistance(self, length)
    local slot = bitTree(self, self.posSlot, min(length, 3) * 64, 6)
    if slot < 4 then
        return slot
    end
    local direct = rshift(slot, 1) - 1
    local distance = (2 + band(slot, 1)) * 2 ^ direct
    if slot < 14 then
        return distance + reverseBitTree(self, self.posSpecial, distance - slot - 1, direct)
    end
    distance = distance + decodeDirect(self, direct - 4) * 16
    return distance + reverseBitTree(self, self.align, 0, 4)
end

-- Literal and match decoding ----------------------------------------------------------------------

local function decodeLiteral(self, out, pos)
    local previous = pos > 0 and out[pos - 1] or 0
    local lcShift = 8 - self.lc
    local context = lshift(band(pos, lshift(1, self.lp) - 1), self.lc) + rshift(previous, lcShift)
    local base = context * 0x300
    local probs = self.literal
    local symbol = 1
    if self.state >= 7 then
        local matchByte = out[pos - self.rep0 - 1]
        repeat
            local matchBit = band(rshift(matchByte, 7), 1)
            matchByte = band(lshift(matchByte, 1), 255)
            local b = decodeBit(self, probs, base + lshift(1 + matchBit, 8) + symbol)
            symbol = symbol * 2 + b
            if matchBit ~= b then
                break
            end
        until symbol >= 0x100
    end
    while symbol < 0x100 do
        symbol = symbol * 2 + decodeBit(self, probs, base + symbol)
    end
    out[pos] = symbol - 0x100
end

-- Decodes until `limit` bytes of output exist (or the end marker). Returns the new position.
function Decoder:run(out, pos, limit)
    local pbMask = lshift(1, self.pb) - 1
    while pos < limit do
        local posState = band(pos, pbMask)
        local state = self.state
        if decodeBit(self, self.isMatch, state * 16 + posState) == 0 then
            decodeLiteral(self, out, pos)
            pos = pos + 1
            self.state = state < 4 and 0 or (state < 10 and state - 3 or state - 6)
        else
            local length
            if decodeBit(self, self.isRep, state) == 0 then
                self.rep3, self.rep2, self.rep1 = self.rep2, self.rep1, self.rep0
                length = decodeLength(self, self.lengths, posState)
                self.state = state < 7 and 7 or 10
                self.rep0 = decodeDistance(self, length)
                if self.rep0 == 4294967295 then
                    return pos, true
                end
            else
                assert(pos > 0, 'Corrupt LZMA stream')
                if decodeBit(self, self.isRepG0, state) == 0 then
                    if decodeBit(self, self.isRep0Long, state * 16 + posState) == 0 then
                        self.state = state < 7 and 9 or 11
                        out[pos] = out[pos - self.rep0 - 1]
                        pos = pos + 1
                        goto continue
                    end
                else
                    local distance
                    if decodeBit(self, self.isRepG1, state) == 0 then
                        distance = self.rep1
                    else
                        if decodeBit(self, self.isRepG2, state) == 0 then
                            distance = self.rep2
                        else
                            distance = self.rep3
                            self.rep3 = self.rep2
                        end
                        self.rep2 = self.rep1
                    end
                    self.rep1 = self.rep0
                    self.rep0 = distance
                end
                length = decodeLength(self, self.repLengths, posState)
                self.state = state < 7 and 8 or 11
            end
            assert(self.rep0 < pos, 'Corrupt LZMA stream (distance out of range)')
            local count = min(length + MATCH_MIN, limit - pos)
            local from = pos - self.rep0 - 1
            for i = 0, count - 1 do
                out[pos + i] = out[from + i]
            end
            pos = pos + count
        end
        ::continue::
    end
    return pos, false
end

-- Public API
-- ------------------------------------------------------------------------------------------

local function newDecoder()
    return setmetatable({}, Decoder)
end

-- properties: the 5-byte coder properties of a 7z LZMA coder (lc/lp/pb byte + dictionary size).
function Lzma.decode(properties, input, unpackSize)
    local decoder = newDecoder()
    decoder:setProperties(properties:byte(1))
    local out = ffi.new('uint8_t[?]', math.max(unpackSize, 1))
    decoder:startRange(input, 1)
    local written = decoder:run(out, 0, unpackSize)
    assert(written == unpackSize, 'LZMA stream ended early')
    return ffi.string(out, unpackSize)
end

-- LZMA2: a sequence of chunks, each either stored or LZMA-coded with its own range coder.
function Lzma.decode2(input, unpackSize)
    local decoder = newDecoder()
    local out = ffi.new('uint8_t[?]', math.max(unpackSize, 1))
    local pos, cursor = 0, 1
    local needProperties = true
    while true do
        local control = input:byte(cursor)
        assert(control, 'Truncated LZMA2 stream')
        if control == 0 then
            break
        end
        if control < 0x80 then
            assert(control <= 2, 'Corrupt LZMA2 stream')
            local size = input:byte(cursor + 1) * 256 + input:byte(cursor + 2) + 1
            ffi.copy(out + pos, input:sub(cursor + 3, cursor + 2 + size), size)
            pos = pos + size
            cursor = cursor + 3 + size
        else
            local size = (band(control, 0x1F) * 65536) + input:byte(cursor + 1) * 256
                + input:byte(cursor + 2) + 1
            local packed = input:byte(cursor + 3) * 256 + input:byte(cursor + 4) + 1
            local mode = band(rshift(control, 5), 3)
            cursor = cursor + 5
            if mode >= 2 then
                decoder:setProperties(input:byte(cursor))
                needProperties = false
                cursor = cursor + 1
            elseif mode == 1 then
                assert(not needProperties, 'LZMA2 chunk without properties')
                decoder:resetState()
            end
            assert(not needProperties, 'LZMA2 chunk without properties')
            decoder:startRange(input, cursor)
            local reached = decoder:run(out, pos, pos + size)
            assert(reached == pos + size, 'LZMA2 chunk ended early')
            pos = reached
            cursor = cursor + packed
        end
    end
    assert(pos == unpackSize, 'LZMA2 size mismatch')
    return ffi.string(out, unpackSize)
end

return Lzma
