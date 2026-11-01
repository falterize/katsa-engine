-- Binary codec for network messages. A Writer appends typed values; a Reader reads them back in
-- the same order. Integers are little-endian. Generic values (`value`) carry a one-byte tag so
-- RPC arguments can be any mix of nil, booleans, numbers, strings and nested tables.
local ffi = require('ffi')
local bit = require('bit')

local Codec = {}

local scratch = ffi.new('uint8_t[8]')
local f32 = ffi.cast('float*', scratch)
local f64 = ffi.cast('double*', scratch)

local Writer = {}
Writer.__index = Writer

function Codec.writer()
    return setmetatable({ parts = {}, count = 0 }, Writer)
end

local function push(self, text)
    self.count = self.count + 1
    self.parts[self.count] = text
end

function Writer:u8(value)
    push(self, string.char(bit.band(value, 255)))
end

function Writer:u16(value)
    value = bit.band(value, 65535)
    push(self, string.char(bit.band(value, 255), bit.rshift(value, 8)))
end

function Writer:u32(value)
    push(
        self,
        string.char(
            bit.band(value, 255),
            bit.band(bit.rshift(value, 8), 255),
            bit.band(bit.rshift(value, 16), 255),
            bit.band(bit.rshift(value, 24), 255)
        )
    )
end

function Writer:i32(value)
    self:u32(value)
end

function Writer:f32(value)
    f32[0] = value
    push(self, ffi.string(scratch, 4))
end

function Writer:f64(value)
    f64[0] = value
    push(self, ffi.string(scratch, 8))
end

function Writer:bool(value)
    self:u8(value and 1 or 0)
end

function Writer:string(value)
    self:u16(#value)
    push(self, value)
end

-- Angle in degrees, quantized to 16 bits over a full turn.
function Writer:angle(value)
    self:u16(math.floor((value % 360) / 360 * 65536 + 0.5))
end

local TAGS = { nil_ = 0, false_ = 1, true_ = 2, number = 3, string = 4, array = 5, map = 6 }

local function isArray(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count == #value
end

function Writer:value(value)
    local kind = type(value)
    if value == nil then
        self:u8(TAGS.nil_)
    elseif value == false then
        self:u8(TAGS.false_)
    elseif value == true then
        self:u8(TAGS.true_)
    elseif kind == 'number' then
        self:u8(TAGS.number)
        self:f64(value)
    elseif kind == 'string' then
        self:u8(TAGS.string)
        self:string(value)
    elseif kind == 'table' then
        if isArray(value) then
            self:u8(TAGS.array)
            self:u16(#value)
            for index = 1, #value do
                self:value(value[index])
            end
        else
            self:u8(TAGS.map)
            local keys = {}
            for key in pairs(value) do
                assert(type(key) == 'string', 'Network tables may only use string keys')
                keys[#keys + 1] = key
            end
            table.sort(keys)
            self:u16(#keys)
            for _, key in ipairs(keys) do
                self:string(key)
                self:value(value[key])
            end
        end
    else
        error('Cannot send a ' .. kind .. ' over the network')
    end
end

-- A list of values with an explicit count (preserves nils).
function Writer:values(list, count)
    self:u8(count)
    for index = 1, count do
        self:value(list[index])
    end
end

function Writer:finish()
    return table.concat(self.parts)
end

local Reader = {}
Reader.__index = Reader

function Codec.reader(data)
    return setmetatable({ data = data, position = 1 }, Reader)
end

local function take(self, size)
    local position = self.position
    assert(position + size - 1 <= #self.data, 'Network message is truncated')
    self.position = position + size
    return position
end

function Reader:u8()
    return self.data:byte(take(self, 1))
end

function Reader:u16()
    local p = take(self, 2)
    local a, b = self.data:byte(p, p + 1)
    return a + b * 256
end

function Reader:u32()
    local p = take(self, 4)
    local a, b, c, d = self.data:byte(p, p + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

function Reader:i32()
    return bit.tobit(self:u32())
end

function Reader:f32()
    local p = take(self, 4)
    ffi.copy(scratch, self.data:sub(p, p + 3), 4)
    return f32[0]
end

function Reader:f64()
    local p = take(self, 8)
    ffi.copy(scratch, self.data:sub(p, p + 7), 8)
    return f64[0]
end

function Reader:bool()
    return self:u8() ~= 0
end

function Reader:string()
    local size = self:u16()
    local p = take(self, size)
    return self.data:sub(p, p + size - 1)
end

function Reader:angle()
    return self:u16() / 65536 * 360
end

function Reader:value()
    local tag = self:u8()
    if tag == TAGS.nil_ then
        return nil
    elseif tag == TAGS.false_ then
        return false
    elseif tag == TAGS.true_ then
        return true
    elseif tag == TAGS.number then
        return self:f64()
    elseif tag == TAGS.string then
        return self:string()
    elseif tag == TAGS.array then
        local list = {}
        for index = 1, self:u16() do
            list[index] = self:value()
        end
        return list
    elseif tag == TAGS.map then
        local map = {}
        for _ = 1, self:u16() do
            local key = self:string()
            map[key] = self:value()
        end
        return map
    end
    error('Unknown network value tag ' .. tostring(tag))
end

function Reader:values()
    local count = self:u8()
    local list = {}
    for index = 1, count do
        list[index] = self:value()
    end
    return list, count
end

function Reader:remaining()
    return #self.data - self.position + 1
end

return Codec
