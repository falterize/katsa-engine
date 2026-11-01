-- katsa.image: ImageData backed by a plain FFI byte buffer.
local ffi = require('ffi')
local bit = require('bit')
local nativeLib = require('source.katsa.core.nativeLib')
local Data = require('source.katsa.core.data')

local Image = {}

-- name -> { channels, bytes per channel, kind }
local formats = {
    r8 = { 1, 1, 'u8' }, rg8 = { 2, 1, 'u8' }, rgba8 = { 4, 1, 'u8' },
    r16 = { 1, 2, 'u16' }, rg16 = { 2, 2, 'u16' }, rgba16 = { 4, 2, 'u16' },
    r16f = { 1, 2, 'f16' }, rg16f = { 2, 2, 'f16' }, rgba16f = { 4, 2, 'f16' },
    r32f = { 1, 4, 'f32' }, rg32f = { 2, 4, 'f32' }, rgba32f = { 4, 4, 'f32' },
}
Image.formats = formats

local function halfToFloat(h)
    local sign = bit.band(h, 0x8000) ~= 0 and -1 or 1
    local exponent, fraction = bit.band(bit.rshift(h, 10), 0x1F), bit.band(h, 0x3FF)
    if exponent == 0 then
        return sign * fraction * 2 ^ -24
    elseif exponent == 31 then
        return fraction == 0 and sign * math.huge or 0 / 0
    end
    return sign * (1 + fraction / 1024) * 2 ^ (exponent - 15)
end

local function floatToHalf(value)
    if value ~= value then
        return 0x7E00
    end
    local sign = 0
    if value < 0 or 1 / value < 0 then
        sign, value = 0x8000, -value
    end
    if value >= 65520 then
        return sign + 0x7C00
    end
    if value < 2 ^ -14 then
        return sign + math.floor(value * 2 ^ 24 + 0.5)
    end
    local exponent = math.floor(math.log(value) / math.log(2))
    if 2 ^ exponent > value then
        exponent = exponent - 1
    end
    local fraction = math.floor((value / 2 ^ exponent - 1) * 1024 + 0.5)
    if fraction == 1024 then
        fraction, exponent = 0, exponent + 1
    end
    return sign + bit.lshift(exponent + 15, 10) + fraction
end

local ImageData = {}
ImageData.__index = ImageData
ImageData.type = 'ImageData'

local viewTypes = { u8 = 'uint8_t*', u16 = 'uint16_t*', f16 = 'uint16_t*', f32 = 'float*' }

local function make(width, height, format, buffer)
    local info = formats[format]
    local pixelBytes = info[1] * info[2]
    return setmetatable({
        _w = width, _h = height, _format = format, _info = info, _pixel = pixelBytes,
        _bytes = width * height * pixelBytes, _buffer = buffer,
        _view = ffi.cast(viewTypes[info[3]], buffer),
    }, ImageData)
end

local function dataString(source)
    if type(source) == 'string' then
        return source
    end
    return source:getString()
end

function Image.newImageData(a, b, c, d)
    if type(a) == 'number' then
        local width, height = a, b
        assert(width >= 1 and height >= 1, 'Invalid image size')
        local format, source = 'rgba8', nil
        if type(c) == 'string' then
            format, source = c, d
        else
            source = c
        end
        assert(formats[format], 'Invalid image format: ' .. tostring(format))
        local size = width * height * formats[format][1] * formats[format][2]
        local buffer = ffi.new('uint8_t[?]', size)
        if source then
            local text = dataString(source)
            assert(#text >= size, 'Data is too small for the image size')
            ffi.copy(buffer, text, size)
        end
        return make(width, height, format, buffer)
    end
    local text
    if type(a) == 'string' and not a:find('\0', 1, true) and #a < 1024 then
        local FS = require('source.katsa.core.filesystem')
        text = assert(FS.read(a))
    else
        text = dataString(a)
    end
    local pixels, width, height = nativeLib.decodeImage(text)
    if not pixels then
        error('Could not decode image data: ' .. tostring(width), 2)
    end
    return make(width, height, 'rgba8', pixels)
end

function ImageData:getWidth()
    return
    self._w
end

function ImageData:getHeight()
    return
    self._h
end

function ImageData:getDimensions()
    return
    self._w, self._h
end

function ImageData:getFormat()
    return
    self._format
end

function ImageData:getSize()
    return
    self._bytes
end

function ImageData:getPointer()
    return
    self._buffer
end

function ImageData:getFFIPointer()
    return
    self._buffer
end

function ImageData:getString()
    return
    ffi.string(self._buffer, self._bytes)
end

function ImageData:release()
    self._released = true
    return true
end

function ImageData:type()
    return 'ImageData'
end

function ImageData:typeOf(name)
    return name == 'ImageData' or name == 'Data' or name == 'Object'
end

local function check(self, x, y)
    if x < 0 or y < 0 or x >= self._w or y >= self._h then
        error(('Attempt to get out-of-range pixel (%d, %d)!'):format(x, y), 3)
    end
end

function ImageData:getPixel(x, y)
    x, y = math.floor(x), math.floor(y)
    check(self, x, y)
    local info, view = self._info, self._view
    local channels, kind = info[1], info[3]
    local base = (y * self._w + x) * channels
    local r, g, b, a = 0, 0, 0, 1
    local out = { 0, 0, 0, 1 }
    for i = 1, channels do
        local raw = view[base + i - 1]
        local value
        if kind == 'u8' then
            value = raw / 255
        elseif kind == 'u16' then
            value = raw / 65535
        elseif kind == 'f16' then
            value = halfToFloat(raw)
        else value = raw end
        out[i] = value
    end
    if channels == 1 then
        out[2], out[3], out[4] = 0, 0, 1
    elseif channels == 2 then
        out[3], out[4] = 0, 1
    end
    return out[1], out[2], out[3], out[4]
end

function ImageData:setPixel(x, y, r, g, b, a)
    x, y = math.floor(x), math.floor(y)
    check(self, x, y)
    if type(r) == 'table' then
        r, g, b, a = r[1], r[2], r[3], r[4]
    end
    local values = { r, g, b, a == nil and 1 or a }
    local info, view = self._info, self._view
    local channels, kind = info[1], info[3]
    local base = (y * self._w + x) * channels
    for i = 1, channels do
        local value = values[i] or 0
        if kind == 'u8' then
            view[base + i - 1] = math.floor(math.max(0, math.min(1, value)) * 255 + 0.5)
        elseif kind == 'u16' then
            view[base + i - 1] = math.floor(math.max(0, math.min(1, value)) * 65535 + 0.5)
        elseif kind == 'f16' then
            view[base + i - 1] = floatToHalf(value)
        else
            view[base + i - 1] = value
        end
    end
end

function ImageData:mapPixel(fn, x, y, w, h)
    x, y, w, h = x or 0, y or 0, w or self._w - (x or 0), h or self._h - (y or 0)
    for py = y, y + h - 1 do
        for px = x, x + w - 1 do
            local r, g, b, a = self:getPixel(px, py)
            local nr, ng, nb, na = fn(px, py, r, g, b, a)
            self:setPixel(px, py, nr, ng, nb, na)
        end
    end
end

function ImageData:paste(source, dx, dy, sx, sy, sw, sh)
    assert(source._format == self._format, 'ImageData formats must match')
    sx, sy = sx or 0, sy or 0
    sw, sh = sw or source._w - sx, sh or source._h - sy
    local rowBytes = self._pixel
    for row = 0, sh - 1 do
        local y = dy + row
        if y >= 0 and y < self._h and sy + row < source._h then
            local from, to = sx, dx
            local count = sw
            if to < 0 then
                from, count, to = from - to, count + to, 0
            end
            if to + count > self._w then
                count = self._w - to
            end
            if count > 0 then
                ffi.copy(self._buffer + (y * self._w + to) * rowBytes,
                    source._buffer + ((sy + row) * source._w + from) * rowBytes, count * rowBytes)
            end
        end
    end
end

function ImageData:clone()
    local buffer = ffi.new('uint8_t[?]', self._bytes)
    ffi.copy(buffer, self._buffer, self._bytes)
    return make(self._w, self._h, self._format, buffer)
end

-- encode(format[, filename]) -> FileData-like (getString) ; only PNG is supported.
function ImageData:encode(format, filename)
    assert(format == 'png', 'Unsupported image encoding: ' .. tostring(format))
    assert(self._format == 'rgba8', 'Only rgba8 image data can be encoded')
    local png = assert(nativeLib.encodePng(self._buffer, self._w, self._h))
    local FS = require('source.katsa.core.filesystem')
    if filename then
        assert(FS.write(filename, png))
    end
    return FS.newFileData(png, filename or ('image.' .. format))
end

Image.ImageData = ImageData
return Image
