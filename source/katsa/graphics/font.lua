-- Fonts (stb_truetype through katsa_native), glyph atlases, measuring, wrapping and Text objects.
local ffi = require('ffi')
local Core = require('source.katsa.graphics.core')
local Texture = require('source.katsa.graphics.texture')
local ImageModule = require('source.katsa.image')
local nativeLib = require('source.katsa.core.nativeLib')

local Font = {}
local Methods = {}
Methods.__index = Methods

local ATLAS = 512
local defaultData

local function defaultFontData()
    if not defaultData then
        local FS = require('source.katsa.core.filesystem')
        local host = rawget(_G, 'katsa_host')
        local relative = 'source/katsa/graphics/fonts/DejaVuSans.ttf'
        defaultData = host and host.read and host.read(relative)
        if not defaultData then
            local source = debug.getinfo(1, 'S').source:gsub('^@', '')
            local directory = source:match('^(.*)[/\\][^/\\]*$') or '.'
            local file = io.open(directory .. '/fonts/DejaVuSans.ttf', 'rb')
            if file then
                defaultData = file:read('*a')
                file:close()
            end
        end
        defaultData = defaultData or (FS.getInfo(relative, 'file') and FS.read(relative))
        assert(defaultData, 'The default font is missing from the katsa runtime')
    end
    return defaultData
end

-- UTF-8 decoding ------------------------------------------------------------------------------

local function decode(text)
    local list, n, i, length = {}, 0, 1, #text
    while i <= length do
        local c = text:byte(i)
        local cp, size
        if c < 0x80 then
            cp, size = c, 1
        elseif c >= 0xF0 then
            cp, size = ((c % 8) * 262144) + ((text:byte(i + 1) or 128) % 64) * 4096 + ((text:byte(i + 2) or 128) % 64) * 64 + ((text:byte(i + 3) or 128) % 64), 4
        elseif c >= 0xE0 then
            cp, size = ((c % 16) * 4096) + ((text:byte(i + 1) or 128) % 64) * 64 + ((text:byte(i + 2) or 128) % 64), 3
        elseif c >= 0xC0 then
            cp, size = ((c % 32) * 64) + ((text:byte(i + 1) or 128) % 64), 2
        else
            cp, size = 0xFFFD, 1
        end
        n = n + 1
        list[n] = cp
        i = i + size
    end
    return list
end
Font.decode = decode

local function encode(cp)
    return utf8 and utf8.char(cp) or (cp < 128 and string.char(cp) or '?')
end

-- Construction --------------------------------------------------------------------------------

local function build(data, size, hinting, dpiscale)
    local face, message = nativeLib.fontLoad(data)
    if not face then
        error(message, 3)
    end
    size = size or 12
    assert(size > 0, 'Invalid font size: ' .. tostring(size))
    dpiscale = dpiscale or Texture.windowDPIScale()
    local pixelSize = size * dpiscale
    local scale = nativeLib.fontScale(face, pixelSize)
    local ascent, descent, gap = nativeLib.fontVMetrics(face)
    local self = setmetatable({
        _face = face, _data = data, _size = size, _dpi = dpiscale, _pixelSize = pixelSize, _scale = scale,
        _ascent = math.ceil(ascent * scale - 0.001), _descent = math.floor(descent * scale + 0.001),
        _height = math.floor((ascent - descent + gap) * scale + 0.5),
        _lineHeight = 1, _glyphs = {}, _atlases = {}, _filter = { 'linear', 'linear', 1 }, _kernCache = {},
    }, Methods)
    Core.track(self, { fontLifetime = true })
    return self
end

function Font.new(a, b, c, d)
    if type(a) == 'number' or a == nil then
        return build(defaultFontData(), a, b, c)
    end
    local data
    if type(a) == 'string' and not a:find('\0', 1, true) and #a < 1024 then
        data = assert(require('source.katsa.core.filesystem').read(a))
    else
        data = a:getString()
    end
    return build(data, b, c, d)
end

-- Atlas ---------------------------------------------------------------------------------------

local function newAtlas(self)
    local blank = ImageModule.newImageData(ATLAS, ATLAS, 'rgba8')
    local texture = Texture.newImage(blank)
    texture:setFilter(self._filter[1], self._filter[2])
    local atlas = { texture = texture, x = 1, y = 1, rowHeight = 0 }
    self._atlases[#self._atlases + 1] = atlas
    return atlas
end

local function allocate(self, w, h)
    local atlas = self._atlases[#self._atlases] or newAtlas(self)
    if atlas.x + w + 1 > ATLAS then
        atlas.x, atlas.y, atlas.rowHeight = 1, atlas.y + atlas.rowHeight + 1, 0
    end
    if atlas.y + h + 1 > ATLAS then
        atlas = newAtlas(self)
    end
    local x, y = atlas.x, atlas.y
    atlas.x = atlas.x + w + 1
    atlas.rowHeight = math.max(atlas.rowHeight, h)
    return atlas, x, y
end

local rgbaScratch
local function glyph(self, cp)
    local cached = self._glyphs[cp]
    if cached then
        return cached
    end
    local pixels, w, h, xoff, yoff = nativeLib.fontBitmap(self._face, cp, self._scale)
    local advance = nativeLib.fontHMetrics(self._face, cp)
    local record = { advance = math.floor(advance * self._scale + 0.5), w = 0, h = 0, xoff = 0, yoff = 0 }
    if not nativeLib.fontHasGlyph(self._face, cp) and cp ~= 32 then
        if cp ~= 0xFFFD and nativeLib.fontHasGlyph(self._face, 0xFFFD) then
            local fallback = glyph(self, 0xFFFD)
            self._glyphs[cp] = fallback
            return fallback
        end
    end
    if pixels then
        local atlas, x, y = allocate(self, w, h)
        local rgba = ffi.new('uint8_t[?]', w * h * 4)
        for i = 0, w * h - 1 do
            rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2], rgba[i * 4 + 3] = 255, 255, 255, pixels[i]
        end
        local gl, E = Core.gl, Core.enum
        Core.bindForEdit(atlas.texture._res.texture)
        gl.glPixelStorei(E.UNPACK_ALIGNMENT, 1)
        gl.glTexSubImage2D(E.TEXTURE_2D, 0, x, y, w, h, E.RGBA, E.UNSIGNED_BYTE, rgba)
        record.atlas = atlas.texture
        record.w, record.h, record.xoff, record.yoff = w, h, xoff, yoff
        record.u0, record.v0 = x / ATLAS, y / ATLAS
        record.u1, record.v1 = (x + w) / ATLAS, (y + h) / ATLAS
    end
    self._glyphs[cp] = record
    return record
end

local function kerning(self, a, b)
    local key = a * 1114112 + b
    local value = self._kernCache[key]
    if value == nil then
        value = math.floor(nativeLib.fontKern(self._face, a, b) * self._scale + 0.5)
        self._kernCache[key] = value
    end
    return value
end

-- Measuring -----------------------------------------------------------------------------------

local function lineWidth(self, cps)
    local width, previous = 0, nil
    for i = 1, #cps do
        local cp = cps[i]
        if previous then
            width = width + kerning(self, previous, cp)
        end
        width = width + glyph(self, cp).advance
        previous = cp
    end
    return width
end

local function plain(text)
    if type(text) == 'table' then
        local parts = {}
        for i = 1, #text do
            if type(text[i]) == 'string' then
                parts[#parts + 1] = text[i]
            end
        end
        return table.concat(parts)
    end
    return tostring(text)
end
Font.plain = plain

function Methods:getWidth(text)
    local widest = 0
    for line in (plain(text) .. '\n'):gmatch('(.-)\n') do
        widest = math.max(widest, lineWidth(self, decode(line)))
    end
    return widest / self._dpi
end

function Methods:getHeight()
    return
    self._height / self._dpi
end

function Methods:getAscent()
    return
    self._ascent / self._dpi
end

function Methods:getDescent()
    return
    self._descent / self._dpi
end

function Methods:getBaseline()
    return
    self._ascent / self._dpi
end

function Methods:getLineHeight()
    return
    self._lineHeight
end

function Methods:setLineHeight(value)
    self._lineHeight = value
end

function Methods:getDPIScale()
    return
    self._dpi
end

function Methods:getFilter()
    return
    self._filter[1], self._filter[2], self._filter[3]
end

function Methods:setFilter(min, mag, anisotropy)
    self._filter = { min, mag or min, anisotropy or 1 }
    for _, atlas in ipairs(self._atlases) do
        atlas.texture:setFilter(min, mag or min, anisotropy)
    end
end

function Methods:hasGlyphs(...)
    for _, item in ipairs({ ... }) do
        for _, cp in ipairs(type(item) == 'number' and { item } or decode(item)) do
            if cp ~= 10 and not nativeLib.fontHasGlyph(self._face, cp) then
                return false
            end
        end
    end
    return true
end

function Methods:getKerning(a, b)
    a = type(a) == 'string' and decode(a)[1] or a
    b = type(b) == 'string' and decode(b)[1] or b
    return kerning(self, a, b) / self._dpi
end

function Methods:setFallbacks() end

-- Splits `text` into lines no wider than `limit` (logical units).
function Methods:getWrap(text, limit)
    local pixelLimit = limit * self._dpi
    local lines, widest = {}, 0
    local function push(cps)
        local width = lineWidth(self, cps)
        widest = math.max(widest, width)
        local parts = {}
        for i = 1, #cps do
            parts[i] = encode(cps[i])
        end
        lines[#lines + 1] = table.concat(parts)
    end
    for paragraph in (plain(text) .. '\n'):gmatch('(.-)\n') do
        local cps = decode(paragraph)
        local current, count = {}, 0
        local i, n = 1, #cps
        while i <= n do
            -- gather spaces then a word
            local spaces, word = {}, {}
            while i <= n and cps[i] == 32 do
                spaces[#spaces + 1] = cps[i]
                i = i + 1
            end
            while i <= n and cps[i] ~= 32 do
                word[#word + 1] = cps[i]
                i = i + 1
            end
            local candidate = {}
            for _, cp in ipairs(current) do candidate[#candidate + 1] = cp end
            for _, cp in ipairs(spaces) do candidate[#candidate + 1] = cp end
            for _, cp in ipairs(word) do candidate[#candidate + 1] = cp end
            if lineWidth(self, candidate) <= pixelLimit or (#current == 0 and #word == 0) then
                current = candidate
            elseif #current > 0 then
                push(current)
                current = {}
                -- retry the word alone on a fresh line
                if lineWidth(self, word) <= pixelLimit then
                    current = word
                else
                    for _, cp in ipairs(word) do
                        local try = { unpack(current) }
                        try[#try + 1] = cp
                        if lineWidth(self, try) > pixelLimit and #current > 0 then
                            push(current)
                            current = { cp }
                        else
                            current = try
                        end
                    end
                end
            else
                -- a single word wider than the limit: break between characters
                for _, cp in ipairs(candidate) do
                    local try = { unpack(current) }
                    try[#try + 1] = cp
                    if lineWidth(self, try) > pixelLimit and #current > 0 then
                        push(current)
                        current = { cp }
                    else
                        current = try
                    end
                end
            end
        end
        push(current)
    end
    return widest / self._dpi, lines
end

-- Emits glyph quads. `emit(texture, x, y, w, h, u0, v0, u1, v1)` receives pixel-space offsets.
function Methods:_layout(cps, emit)
    local x, previous = 0, nil
    local baseline = self._ascent
    for i = 1, #cps do
        local cp = cps[i]
        if previous then
            x = x + kerning(self, previous, cp)
        end
        local g = glyph(self, cp)
        if g.atlas then
            emit(g.atlas, x + g.xoff, baseline + g.yoff, g.w, g.h, g.u0, g.v0, g.u1, g.v1)
        end
        x = x + g.advance
        previous = cp
    end
    return x
end

function Methods:release()
    return true
end

function Methods:type()
    return 'Font'
end

function Methods:typeOf(name)
    return name == 'Font' or name == 'Object'
end

-- Text objects ----------------------------------------------------------------------------------

local TextMethods = {}
TextMethods.__index = TextMethods

function Font.newText(font, text)
    local self = setmetatable({ _font = font, _entries = {}, _width = 0, _height = 0 }, TextMethods)
    if text ~= nil then
        self:set(text)
    end
    return self
end

local function recompute(self)
    local width, height = 0, 0
    for _, e in ipairs(self._entries) do
        width = math.max(width, e.x + e.width)
        height = math.max(height, e.y + e.height)
    end
    self._width, self._height = width, height
end

local function measure(font, text, limit)
    if limit then
        local width, lines = font:getWrap(text, limit)
        return math.max(width, 0), #lines * font:getHeight() * font:getLineHeight()
    end
    local lines = 1
    for _ in plain(text):gmatch('\n') do
        lines = lines + 1
    end
    return font:getWidth(text), lines * font:getHeight() * font:getLineHeight()
end

function TextMethods:set(text)
    self._entries = {}
    if text ~= nil and text ~= '' then
        self:add(text, 0, 0)
    else
        recompute(self)
    end
end

function TextMethods:setf(text, limit, align)
    self._entries = {}
    if text ~= nil then
        self:addf(text, limit, align, 0, 0)
    end
end

function TextMethods:add(text, x, y, angle, sx, sy, ox, oy, kx, ky)
    local width, height = measure(self._font, text)
    self._entries[#self._entries + 1] = {
        text = text, x = x or 0, y = y or 0, args = { x or 0, y or 0, angle, sx, sy, ox, oy, kx, ky },
        width = width, height = height,
    }
    recompute(self)
    return #self._entries
end

function TextMethods:addf(text, limit, align, x, y, angle, sx, sy, ox, oy, kx, ky)
    local width, height = measure(self._font, text, limit)
    self._entries[#self._entries + 1] = {
        text = text, x = x or 0, y = y or 0, limit = limit, align = align or 'left',
        args = { x or 0, y or 0, angle, sx, sy, ox, oy, kx, ky }, width = limit, height = height,
    }
    recompute(self)
    return #self._entries
end

function TextMethods:clear()
    self._entries = {}
    recompute(self)
end

function TextMethods:setFont(font)
    self._font = font
end

function TextMethods:getFont()
    return
    self._font
end

function TextMethods:getWidth()
    return
    self._width
end

function TextMethods:getHeight()
    return
    self._height
end

function TextMethods:getDimensions()
    return
    self._width, self._height
end

function TextMethods:release()
    return true
end

function TextMethods:type()
    return 'Text'
end

function TextMethods:typeOf(name)
    return name == 'Text' or name == 'Drawable' or name == 'Object'
end

function TextMethods:_draw2D(graphics, matrix)
    local state = graphics._state
    local savedTransform = { unpack(state.transform) }
    for i = 1, 6 do
        state.transform[i] = matrix[i]
    end
    local savedFont = state.font
    state.font = self._font
    for _, e in ipairs(self._entries) do
        local a = e.args
        if e.limit then
            graphics.printf(e.text, a[1], a[2], e.limit, e.align, a[3], a[4], a[5], a[6], a[7],
                a[8], a[9])
        else
            graphics.print(e.text, a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9])
        end
    end
    state.font = savedFont
    for i = 1, 6 do
        state.transform[i] = savedTransform[i]
    end
end

return Font
