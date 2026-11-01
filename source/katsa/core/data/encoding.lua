-- Hex and base64 encoding plus zlib/gzip/deflate decompression.

local Inflate = require('source.katsa.core.inflate')
local char, byte, format = string.char, string.byte, string.format

local Input = require('source.katsa.core.data.input')

local M = {}

local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local decodeMap = {}
for i = 1, #alphabet do
    decodeMap[byte(alphabet, i)] = i - 1
end

local function base64encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = byte(data, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = alphabet:sub(c1 + 1, c1 + 1) .. alphabet:sub(c2 + 1, c2 + 1)
            .. (b and alphabet:sub(c3 + 1,
                c3 + 1) or '=') .. (c and alphabet:sub(c4 + 1, c4 + 1) or '=')
    end
    return table.concat(out)
end

local function base64decode(text)
    text = text:gsub('[^%w%+/=]', '')
    local out = {}
    for i = 1, #text, 4 do
        local a, b, c, d = byte(text, i, i + 3)
        local n = decodeMap[a] * 262144 + decodeMap[b] * 4096
            + (c ~= 61 and decodeMap[c] or 0) * 64 + (d ~= 61 and decodeMap[d] or 0)
        local piece = char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
        if d == 61 then
            piece = piece:sub(1, c == 61 and 1 or 2)
        end
        out[#out + 1] = piece
    end
    return table.concat(out)
end

-- container is accepted for love.data compatibility; only 'string' is produced.
function M.encode(container, format_, data)
    data = Input.toString(data)
    assert(container == 'string' or container == 'data', 'Unknown container')
    if format_ == 'hex' then
        return (data:gsub('.', function(c)
            return format('%02x', byte(c))
        end))
    elseif format_ == 'base64' then
        return base64encode(data)
    end
    error('Unknown encoding format: ' .. tostring(format_))
end

function M.decode(container, format_, text)
    text = Input.toString(text)
    assert(container == 'string' or container == 'data', 'Unknown container')
    if format_ == 'hex' then
        return (text:gsub('%x%x', function(pair)
            return char(tonumber(pair, 16))
        end))
    elseif format_ == 'base64' then
        return base64decode(text)
    end
    error('Unknown encoding format: ' .. tostring(format_))
end

function M.decompress(container, format_, data)
    data = Input.toString(data)
    if format_ == 'zlib' then
        return Inflate.zlib(data)
    elseif format_ == 'gzip' then
        return Inflate.gzip(data)
    elseif format_ == 'deflate' then
        return (Inflate.raw(data, 1))
    end
    error('Unsupported compression format: ' .. tostring(format_))
end

return M
