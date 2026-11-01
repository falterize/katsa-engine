-- Image and Canvas objects (both are 2D textures with a shared method set).
local ffi = require('ffi')
local bit = require('bit')
local Core = require('source.katsa.graphics.core')
local ImageModule = require('source.katsa.image')

local Texture = {}
Texture.defaultFilter = { min = 'linear', mag = 'linear', anisotropy = 1 }

local function formatTable()
    local E = Core.enum
    local ubyte, float = E.UNSIGNED_BYTE, E.FLOAT
    return {
        rgba8 = { E.RGBA8, E.RGBA, ubyte }, normal = { E.RGBA8, E.RGBA, ubyte },
        srgb = { E.SRGB8_ALPHA8, E.RGBA, ubyte },
        r8 = { E.R8, E.RED, ubyte }, rg8 = { E.RG8, E.RG, ubyte },
        rgba16f = { E.RGBA16F, E.RGBA, E.HALF_FLOAT }, rgba32f = { E.RGBA32F, E.RGBA, float },
        r16f = { E.R16F, E.RED, E.HALF_FLOAT }, r32f = { E.R32F, E.RED, float },
        rg16f = { E.RG16F, E.RG, E.HALF_FLOAT },
        rgb10a2 = { E.RGB10_A2, E.RGBA, E.UNSIGNED_INT_2_10_10_10_REV },
        depth16 = { E.DEPTH_COMPONENT16, E.DEPTH_COMPONENT, E.UNSIGNED_SHORT, depth = true },
        depth24 = { E.DEPTH_COMPONENT24, E.DEPTH_COMPONENT, E.UNSIGNED_INT, depth = true },
        depth32f = { E.DEPTH_COMPONENT32F, E.DEPTH_COMPONENT, float, depth = true },
        depth24stencil8 = {
            E.DEPTH24_STENCIL8, E.DEPTH_STENCIL, E.UNSIGNED_INT_24_8, depth = true, stencil = true,
        },
        depth32fstencil8 = {
            E.DEPTH32F_STENCIL8, E.DEPTH_STENCIL, 0x8DAD, depth = true, stencil = true,
        },
        stencil8 = { E.STENCIL_INDEX8, 0x1901, ubyte, stencil = true, renderbufferOnly = true },
    }
end

local formats
local function lookup(name)
    formats = formats or formatTable()
    return formats[name]
end
Texture.lookupFormat = lookup

local Methods = {}
Methods.__index = Methods

-- Texture statistics -------------------------------------------------------------------------

local bytesPerPixel = {
    r8 = 1, rg8 = 2, rgba16f = 8, rgba32f = 16, r16f = 2, r32f = 4, rg16f = 4, depth16 = 2,
    stencil8 = 1,
}

-- Counts the texture in getStats(); the matching decrement runs when its GL objects are deleted.
local function account(self, res, counter)
    local counters = Texture.counters
    local samples = math.max(self._msaa, 1)
    res.counter = counter
    res.bytes = self._pw * self._ph * (bytesPerPixel[self._formatName] or 4) * samples
    counters[counter] = counters[counter] + 1
    counters.texturememory = counters.texturememory + res.bytes
end

function Texture.release(res)
    local counter = res.counter
    if counter then
        local counters = Texture.counters
        counters[counter] = counters[counter] - 1
        counters.texturememory = counters.texturememory - (res.bytes or 0)
        res.counter = nil
    end
end

local function glMin(filter)
    local E = Core.enum
    local linear = filter.min == 'linear'
    if not filter.mipmap then
        return linear and E.LINEAR or E.NEAREST
    elseif filter.mipmap == 'nearest' then
        return linear and E.LINEAR_MIPMAP_NEAREST or E.NEAREST_MIPMAP_NEAREST
    end
    return linear and E.LINEAR_MIPMAP_LINEAR or E.NEAREST_MIPMAP_LINEAR
end

local wrapModes
local function glWrap(mode)
    local E = Core.enum
    wrapModes = wrapModes
        or { clamp = E.CLAMP_TO_EDGE, repeat_ = E.REPEAT, mirroredrepeat = E.MIRRORED_REPEAT }
    return wrapModes[mode == 'repeat' and 'repeat_' or mode] or E.CLAMP_TO_EDGE
end

function Methods:_applySampler()
    local gl, E = Core.gl, Core.enum
    if self._res.renderbufferOnly then
        return
    end
    Core.bindForEdit(self._res.texture)
    local filter = self._filter
    if self._depth then
        gl.glTexParameteri(E.TEXTURE_2D, E.TEXTURE_MIN_FILTER,
            filter.min == 'linear' and E.LINEAR or E.NEAREST)
        gl.glTexParameteri(E.TEXTURE_2D, E.TEXTURE_MAG_FILTER,
            filter.mag == 'linear' and E.LINEAR or E.NEAREST)
    else
        gl.glTexParameteri(E.TEXTURE_2D, E.TEXTURE_MIN_FILTER, glMin(filter))
        gl.glTexParameteri(E.TEXTURE_2D, E.TEXTURE_MAG_FILTER,
            filter.mag == 'linear' and E.LINEAR or E.NEAREST)
    end
    gl.glTexParameteri(E.TEXTURE_2D, E.TEXTURE_WRAP_S, glWrap(self._wrap[1]))
    gl.glTexParameteri(E.TEXTURE_2D, E.TEXTURE_WRAP_T, glWrap(self._wrap[2]))
    if Core.limits.textureanisotropy > 1 and not self._depth then
        gl.glTexParameterf(E.TEXTURE_2D, E.TEXTURE_MAX_ANISOTROPY,
            math.min(filter.anisotropy or 1, Core.limits.textureanisotropy))
    end
end

local function newTextureObject(kind, width, height, dpiscale, formatName, msaa)
    local info = assert(lookup(formatName), 'Invalid texture format: ' .. tostring(formatName))
    local self = setmetatable({
        _kind = kind, _pw = width, _ph = height, _dpi = dpiscale, _formatName = formatName,
        _info = info,
        _depth = info.depth or false, _msaa = msaa or 0, _mipmaps = 1,
        _filter = {
            min = Texture.defaultFilter.min, mag = Texture.defaultFilter.mag,
            anisotropy = Texture.defaultFilter.anisotropy, mipmap = nil,
        },
        _wrap = { 'clamp', 'clamp' },
    }, Methods)
    return self
end

local function createStorage(self, pixels, imageFormat)
    local gl, E = Core.gl, Core.enum
    local info = self._info
    local res = { renderbuffers = {} }
    self._res = res
    local id = ffi.new('GLuint[1]')
    gl.glGenTextures(1, id)
    res.texture = id[0]
    Core.bindForEdit(res.texture)
    gl.glPixelStorei(E.UNPACK_ALIGNMENT, 1)
    gl.glTexImage2D(E.TEXTURE_2D, 0, info[1], self._pw, self._ph, 0, info[2], info[3], pixels)
    if self._depth then
        gl.glTexParameteri(E.TEXTURE_2D, E.TEXTURE_COMPARE_MODE, 0)
    end
    self._filter.mipmap = nil
    self:_applySampler()
    Core.track(self, res)
    account(self, res, 'images')
end

-- Images -------------------------------------------------------------------------------------

local function dataFrom(source)
    if type(source) == 'table' and source._buffer and source.getPixel then
        return source
    end
    return ImageModule.newImageData(source)
end

function Texture.newImage(source, settings)
    settings = settings or {}
    local data = dataFrom(source)
    local formatName = data:getFormat()
    assert(lookup(formatName), 'Unsupported image format: ' .. formatName)
    local self = newTextureObject('image', data:getWidth(), data:getHeight(),
        settings.dpiscale or 1, formatName, 0)
    createStorage(self, data:getPointer())
    self._mipmapsEnabled = settings.mipmaps and true or false
    if settings.mipmaps then
        local count = math.floor(math.log(math.max(self._pw, self._ph)) / math.log(2)) + 1
        Core.gl.glGenerateMipmap(Core.enum.TEXTURE_2D)
        self._mipmaps = count
        self._filter.mipmap = 'linear'
        self:_applySampler()
        -- A full mip chain adds a third of the base level.
        local extra = math.floor(self._res.bytes / 3)
        Texture.counters.texturememory = Texture.counters.texturememory + extra
        self._res.bytes = self._res.bytes + extra
    end
    return self
end

function Methods:replacePixels(data, slice, mip, x, y)
    assert(self._kind == 'image', 'replacePixels is only valid for Images')
    local gl, E = Core.gl, Core.enum
    x, y = x or 0, y or 0
    assert(data:getFormat() == self._formatName, 'ImageData format must match the Image format')
    local inside = x >= 0 and y >= 0 and x + data:getWidth() <= self._pw
        and y + data:getHeight() <= self._ph
    assert(inside, 'Region is outside the Image')
    Core.bindForEdit(self._res.texture)
    gl.glPixelStorei(E.UNPACK_ALIGNMENT, 1)
    gl.glTexSubImage2D(E.TEXTURE_2D, 0, x, y, data:getWidth(), data:getHeight(), self._info[2],
        self._info[3], data:getPointer())
    if self._mipmapsEnabled then
        gl.glGenerateMipmap(E.TEXTURE_2D)
    end
end

-- Canvases -----------------------------------------------------------------------------------

function Texture.newCanvas(width, height, settings)
    settings = settings or {}
    local density = settings.dpiscale or Texture.windowDPIScale()
    local pw, ph = math.floor(width * density + 0.5), math.floor(height * density + 0.5)
    if type(width) == 'table' then
        error('Canvas array and volume types are not supported')
    end
    local limit = Core.limits.texturesize
    assert(pw >= 1 and ph >= 1, 'Canvas size must be positive')
    assert(pw <= limit and ph <= limit,
        ('Cannot create canvas: size exceeds the maximum texture size (%d)'):format(limit))
    local formatName = settings.format or 'normal'
    local msaa = math.min(settings.msaa or 0, Core.limits.canvasmsaa)
    if msaa < 2 then
        msaa = 0
    end
    local self = newTextureObject('canvas', pw, ph, density, formatName, msaa)
    assert(settings.readable ~= nil or not self._info.renderbufferOnly or true)
    self._readable = settings.readable
    if self._readable == nil then
        self._readable = not self._info.depth
    end
    assert(not (self._info.depth and self._info.renderbufferOnly and self._readable),
        'stencil8 canvases cannot be readable')
    local gl, E = Core.gl, Core.enum
    local res = { renderbuffers = {}, fbos = {} }
    self._res = res
    self._dirty = false
    local id = ffi.new('GLuint[1]')
    if self._readable and not self._info.renderbufferOnly then
        gl.glGenTextures(1, id)
        res.texture = id[0]
        Core.bindForEdit(res.texture)
        gl.glTexImage2D(E.TEXTURE_2D, 0, self._info[1], pw, ph, 0, self._info[2], self._info[3],
            nil)
        if self._depth then
            gl.glTexParameteri(E.TEXTURE_2D, E.TEXTURE_COMPARE_MODE, 0)
        end
        self:_applySampler()
    end
    if msaa > 0 or not res.texture then
        gl.glGenRenderbuffers(1, id)
        local rb = id[0]
        res.renderbuffers[1] = rb
        res.msaaRenderbuffer = rb
        gl.glBindRenderbuffer(E.RENDERBUFFER, rb)
        if msaa > 0 then
            gl.glRenderbufferStorageMultisample(E.RENDERBUFFER, msaa, self._info[1], pw, ph)
        else
            gl.glRenderbufferStorage(E.RENDERBUFFER, self._info[1], pw, ph)
        end
    end
    Core.track(self, res)
    account(self, res, 'canvases')
    return self
end

function Texture.windowDPIScale()
    return Texture.getWindowDPIScale and Texture.getWindowDPIScale() or 1
end

-- What an FBO attaches for rendering: kind ('texture' | 'renderbuffer') and id.
function Methods:_renderAttachment()
    local res = self._res
    if res.msaaRenderbuffer then
        return 'renderbuffer', res.msaaRenderbuffer
    end
    return 'texture', res.texture
end

function Methods:_attachTo(attachmentPoint, fbo)
    local gl, E = Core.gl, Core.enum
    local kind, id = self:_renderAttachment()
    if kind == 'texture' then
        gl.glFramebufferTexture2D(E.FRAMEBUFFER, attachmentPoint, E.TEXTURE_2D, id, 0)
    else
        gl.glFramebufferRenderbuffer(E.FRAMEBUFFER, attachmentPoint, E.RENDERBUFFER, id)
    end
end

local function makeFbo(self, attach)
    local gl, E = Core.gl, Core.enum
    local id = ffi.new('GLuint[1]')
    gl.glGenFramebuffers(1, id)
    gl.glBindFramebuffer(E.FRAMEBUFFER, id[0])
    attach()
    return id[0]
end

-- Resolves multisampled contents into the sampleable texture.
function Methods:_resolve()
    local res = self._res
    if not self._dirty or not res.msaaRenderbuffer or not res.texture then
        self._dirty = false
        return
    end
    local gl, E = Core.gl, Core.enum
    local depth = self._depth
    local point = E.COLOR_ATTACHMENT0
    if depth then
        point = self._info.stencil and E.DEPTH_STENCIL_ATTACHMENT or E.DEPTH_ATTACHMENT
    end
    if not res.msaaFbo then
        res.msaaFbo = makeFbo(self, function()
            gl.glFramebufferRenderbuffer(E.FRAMEBUFFER, point, E.RENDERBUFFER, res.msaaRenderbuffer)
        end)
        res.resolveFbo = makeFbo(self, function()
            gl.glFramebufferTexture2D(E.FRAMEBUFFER, point, E.TEXTURE_2D, res.texture, 0)
        end)
        res.fbos[#res.fbos + 1] = res.msaaFbo
        res.fbos[#res.fbos + 1] = res.resolveFbo
    end
    gl.glBindFramebuffer(E.READ_FRAMEBUFFER, res.msaaFbo)
    gl.glBindFramebuffer(E.DRAW_FRAMEBUFFER, res.resolveFbo)
    local mask = depth and (self._info.stencil and bit.bor(E.DEPTH_BUFFER_BIT,
        E.STENCIL_BUFFER_BIT) or E.DEPTH_BUFFER_BIT) or E.COLOR_BUFFER_BIT
    gl.glBlitFramebuffer(0, 0, self._pw, self._ph, 0, 0, self._pw, self._ph, mask, E.NEAREST)
    self._dirty = false
    Core.framebufferChanged()
end

function Methods:_markDirty()
    self._dirty = true
end

function Methods:_sampleId()
    self:_resolve()
    return self._res.texture
end

-- Reads the canvas into an ImageData (no row flip: canvas rows already run top to bottom).
function Methods:newImageData(slice, mip, x, y, w, h)
    assert(self._kind == 'canvas', 'newImageData is only valid for Canvases')
    assert(not self._depth, 'Depth canvases cannot be read into ImageData')
    assert(self._readable, 'Canvas is not readable')
    x, y = x or 0, y or 0
    w, h = w or self._pw - x, h or self._ph - y
    self:_resolve()
    local gl, E = Core.gl, Core.enum
    local res = self._res
    if not res.readFbo then
        res.readFbo = makeFbo(self, function()
            gl.glFramebufferTexture2D(E.FRAMEBUFFER, E.COLOR_ATTACHMENT0, E.TEXTURE_2D, res.texture,
                0)
        end)
        res.fbos[#res.fbos + 1] = res.readFbo
    end
    gl.glBindFramebuffer(E.READ_FRAMEBUFFER, res.readFbo)
    local name = self._formatName
    local floatFormats = { rgba16f = true, rgba32f = true, r16f = true, r32f = true, rg16f = true }
    local isFloat = floatFormats[name] == true
    local data
    gl.glPixelStorei(E.PACK_ALIGNMENT, 1)
    if isFloat then
        data = ImageModule.newImageData(w, h, 'rgba32f')
        gl.glReadPixels(x, y, w, h, E.RGBA, E.FLOAT, data:getPointer())
    else
        data = ImageModule.newImageData(w, h, 'rgba8')
        gl.glReadPixels(x, y, w, h, E.RGBA, E.UNSIGNED_BYTE, data:getPointer())
    end
    Core.framebufferChanged()
    return data
end

-- Shared methods -----------------------------------------------------------------------------

function Methods:getWidth()
    return self._pw / self._dpi
end

function Methods:getHeight()
    return self._ph / self._dpi
end

function Methods:getDimensions()
    return self._pw / self._dpi, self._ph / self._dpi
end

function Methods:getPixelWidth()
    return self._pw
end

function Methods:getPixelHeight()
    return self._ph
end

function Methods:getPixelDimensions()
    return self._pw, self._ph
end

function Methods:getDPIScale()
    return self._dpi
end

function Methods:getFormat()
    return self._formatName
end

function Methods:getMSAA()
    return self._msaa
end

function Methods:getMipmapCount()
    return self._mipmaps
end

function Methods:getTextureType()
    return '2d'
end

function Methods:isReadable()
    return self._readable ~= false
end

function Methods:isCanvasType()
    return self._kind == 'canvas'
end

function Methods:getDepthSampleMode()
    return self._depthSample
end

function Methods:setDepthSampleMode(mode)
    self._depthSample = mode
    if self._res.texture and self._depth then
        local gl, E = Core.gl, Core.enum
        Core.bindForEdit(self._res.texture)
        gl.glTexParameteri(E.TEXTURE_2D, E.TEXTURE_COMPARE_MODE, mode and 0x884E or 0)
        if mode then
            local funcs = {
                less = E.LESS, lequal = E.LEQUAL, greater = E.GREATER, gequal = E.GEQUAL,
                equal = E.EQUAL, notequal = E.NOTEQUAL, always = E.ALWAYS, never = E.NEVER,
            }
            gl.glTexParameteri(E.TEXTURE_2D, 0x884D, funcs[mode] or E.LEQUAL)
        end
    end
end

function Methods:getFilter()
    return self._filter.min, self._filter.mag, self._filter.anisotropy
end

function Methods:setFilter(min, mag, anisotropy)
    assert(min == 'linear' or min == 'nearest', 'Invalid filter mode: ' .. tostring(min))
    self._filter.min, self._filter.mag = min, mag or min
    self._filter.anisotropy = anisotropy or 1
    self:_applySampler()
end

function Methods:getMipmapFilter()
    return self._filter.mipmap, 0
end

function Methods:setMipmapFilter(mode)
    if mode ~= nil and mode ~= 'nearest' and mode ~= 'linear' then
        error('Invalid filter mode: ' .. tostring(mode))
    end
    if mode and self._mipmaps <= 1 then
        error('Mipmap filtering requires a texture created with mipmaps', 2)
    end
    self._filter.mipmap = mode
    self:_applySampler()
end

function Methods:getWrap()
    return self._wrap[1], self._wrap[2]
end

function Methods:setWrap(s, t)
    self._wrap[1], self._wrap[2] = s, t or s
    self:_applySampler()
end

function Methods:generateMipmaps()
    assert(self._res.texture and not self._depth, 'Cannot generate mipmaps for this texture')
    local gl = Core.gl
    self:_resolve()
    Core.bindForEdit(self._res.texture)
    gl.glGenerateMipmap(Core.enum.TEXTURE_2D)
end

function Methods:release()
    return Core.release(self)
end

function Methods:type()
    return self._kind == 'canvas' and 'Canvas' or 'Image'
end

function Methods:typeOf(name)
    return name == self:type() or name == 'Texture' or name == 'Drawable' or name == 'Object'
end

Core.releaseStatistics = Texture.release

return Texture
