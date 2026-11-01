-- utf8 library (Lua 5.3 API) for LuaJIT: char, charpattern, codepoint, len, offset and codes.
local utf8 = {}

utf8.charpattern = '[\0-\x7F\xC2-\xF4][\x80-\xBF]*'

local function encode(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    elseif code < 0x10000 then
        return string.char(
            0xE0 + math.floor(code / 0x1000),
            0x80 + math.floor(code / 0x40) % 0x40,
            0x80 + code % 0x40
        )
    end
    return string.char(
        0xF0 + math.floor(code / 0x40000),
        0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40,
        0x80 + code % 0x40
    )
end

function utf8.char(...)
    local parts = {}
    for index, code in ipairs({ ... }) do
        assert(code >= 0 and code <= 0x10FFFF, 'bad argument #' .. index .. ' (value out of range)')
        parts[index] = encode(code)
    end
    return table.concat(parts)
end

local function isContinuation(byte)
    return byte and byte >= 0x80 and byte < 0xC0
end

-- Decodes the character starting at byte `i`; returns the code point and its length, or nil.
local function decode(text, i)
    local lead = text:byte(i)
    if not lead then
        return nil
    elseif lead < 0x80 then
        return lead, 1
    end
    local length = (lead >= 0xF0 and lead <= 0xF4 and 4) or (lead >= 0xE0 and 3) or (lead >= 0xC2 and lead < 0xE0 and 2)
    if not length then
        return nil
    end
    local code = lead % (2 ^ (7 - length))
    for offset = 1, length - 1 do
        local byte = text:byte(i + offset)
        if not isContinuation(byte) then
            return nil
        end
        code = code * 0x40 + byte % 0x40
    end
    return code, length
end

local function bytePosition(text, position)
    if position < 0 then
        return #text + position + 1
    end
    return position
end

function utf8.len(text, first, last)
    local i = bytePosition(text, first or 1)
    local stop = bytePosition(text, last or -1)
    local count = 0
    while i <= stop do
        local code, length = decode(text, i)
        if not code then
            return nil, i
        end
        i = i + length
        count = count + 1
    end
    return count
end

function utf8.codepoint(text, first, last)
    first = bytePosition(text, first or 1)
    last = bytePosition(text, last or first)
    local codes, i = {}, first
    while i <= last do
        local code, length = decode(text, i)
        if not code then
            error('invalid UTF-8 code', 2)
        end
        codes[#codes + 1] = code
        i = i + length
    end
    return unpack(codes)
end

-- Byte position of the n-th character counted from `start` (negative n counts backwards).
function utf8.offset(text, n, start)
    local i = bytePosition(text, start or (n > 0 and 1 or #text + 1))
    if n == 0 then
        while i > 1 and isContinuation(text:byte(i)) do
            i = i - 1
        end
        return i
    end
    if isContinuation(text:byte(i)) then
        error('initial position is a continuation byte', 2)
    end
    if n < 0 then
        while n < 0 and i > 1 do
            repeat
                i = i - 1
            until i <= 1 or not isContinuation(text:byte(i))
            n = n + 1
        end
        return n == 0 and i or nil
    end
    n = n - 1
    while n > 0 and i <= #text do
        repeat
            i = i + 1
        until not isContinuation(text:byte(i))
        n = n - 1
    end
    return n == 0 and i or nil
end

function utf8.codes(text)
    return function(_, position)
        local i = position
        if i > 0 then
            local _, length = decode(text, i)
            i = i + (length or 1)
        else
            i = 1
        end
        if i > #text then
            return nil
        end
        local code = decode(text, i)
        if not code then
            error('invalid UTF-8 code', 2)
        end
        return i, code
    end, text, 0
end

return utf8
