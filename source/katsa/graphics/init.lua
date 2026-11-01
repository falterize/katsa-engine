-- katsa.graphics: LÖVE-compatible 2D renderer on OpenGL 3.3 core / GLES 3.0.
--
-- Coordinates are in logical units (pixels / dpi scale), y points down. Rendering into a canvas flips
-- the projection so canvas rows run top to bottom; raw clip-space output from custom vertex shaders is
-- left untouched, so canvas contents of 3D passes keep their GL orientation.
local ffi = require('ffi')
local bit = require('bit')
local Core = require('source.katsa.graphics.core')
local Texture = require('source.katsa.graphics.texture')
local Shader = require('source.katsa.graphics.shader')
local Mesh = require('source.katsa.graphics.mesh')
local Translator = require('source.katsa.graphics.shaderTranslator')
local FontModule = require('source.katsa.graphics.font')

local G = {}

ffi.cdef([[
typedef struct { float x, y, u, v; uint8_t r, g, b, a; } KatsaVertex;
]])

local VERTEX_CAPACITY = 12288
local E -- enum table, set at setup
local gl

-- State ----------------------------------------------------------------------------------------

local S = {
    color = { 1, 1, 1, 1 },
    background = { 0, 0, 0, 1 },
    blend = 'alpha',
    alphaMode = 'alphamultiply',
    colorMask = { true, true, true, true },
    scissor = nil,
    stencilTest = nil,
    depthCompare = 'always',
    depthWrite = false,
    cull = 'none',
    winding = 'ccw',
    wireframe = false,
    lineWidth = 1,
    lineJoin = 'miter',
    lineStyle = 'smooth',
    shader = nil,
    font = nil,
    canvases = nil, -- list of canvases, nil = backbuffer
    canvasOptions = nil,
    transform = { 1, 0, 0, 1, 0, 0 },
    stack = {},
    pointSize = 1,
}
G._state = S

local batch = { count = 0, texture = nil, vertices = nil }
local stats = { drawcalls = 0, drawcallsbatched = 0, canvasswitches = 0, shaderswitches = 0 }
local counters = { images = 0, canvases = 0, fonts = 0, texturememory = 0 }
local screenshots = {}
local target = { w = 1, h = 1, dpi = 1, isCanvas = false }
local ready = false
local defaultShader, whiteTexture

local function flush()
    if batch.count > 0 then
        G._flushBatch()
    end
end

-- Setup ----------------------------------------------------------------------------------------

local function windowDPI()
    return Core.platform and Core.platform:getDPIScale() or 1
end
Texture.getWindowDPIScale = windowDPI

local function refreshBackbuffer()
    local pw, ph = Core.platform:getDrawableSize()
    target.pw, target.ph = pw, ph
    target.dpi = windowDPI()
end

local function applyViewport()
    if S.canvases then
        local first = S.canvases[1]
        target.pw, target.ph, target.dpi, target.isCanvas = first._pw, first._ph, first._dpi, true
    else
        refreshBackbuffer()
        target.isCanvas = false
    end
    target.w, target.h = target.pw / target.dpi, target.ph / target.dpi
    gl.glViewport(0, 0, target.pw, target.ph)
end

function G.setup(platform)
    if ready then
        applyViewport()
        return true
    end
    local ok, message = Core.init(platform)
    if not ok then
        error('Cannot initialise graphics: ' .. tostring(message))
    end
    gl, E = Core.gl, Core.enum
    local vao = ffi.new('GLuint[1]')
    gl.glGenVertexArrays(1, vao)
    gl.glBindVertexArray(vao[0])
    local id = ffi.new('GLuint[1]')
    gl.glGenBuffers(1, id)
    batch.vbo = id[0]
    batch.vertices = ffi.new('KatsaVertex[?]', VERTEX_CAPACITY)
    -- 1x1 white texture used when nothing is bound.
    local white = ffi.new('uint8_t[4]', 255, 255, 255, 255)
    whiteTexture = Texture.newImage(require('source.katsa.image').newImageData(1, 1, 'rgba8', string.char(255, 255, 255, 255)))
    Core.defaultTextureId = whiteTexture._res.texture
    Core.defaultTextureObject = whiteTexture
    ready = true
    defaultShader = Shader.new([[
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    return Texel(tex, uv) * color;
}]])
    S.shader = nil
    Core.onFramebufferDeleted = function() end
    gl.glEnable(E.BLEND)
    gl.glDisable(E.DEPTH_TEST)
    refreshBackbuffer()
    applyViewport()
    G.setBlendMode('alpha')
    return true
end

local function requireReady()
    if not ready then
        error('Graphics is not initialised: create a window first (katsa.window.setMode)', 3)
    end
end

-- Transform ------------------------------------------------------------------------------------

function G.origin()
    local t = S.transform
    t[1], t[2], t[3], t[4], t[5], t[6] = 1, 0, 0, 1, 0, 0
end

local function multiply(a, b, c, d, tx, ty)
    local t = S.transform
    local t1, t2, t3, t4, t5, t6 = t[1], t[2], t[3], t[4], t[5], t[6]
    t[1] = t1 * a + t3 * b
    t[2] = t2 * a + t4 * b
    t[3] = t1 * c + t3 * d
    t[4] = t2 * c + t4 * d
    t[5] = t1 * tx + t3 * ty + t5
    t[6] = t2 * tx + t4 * ty + t6
end

function G.translate(x, y) multiply(1, 0, 0, 1, x, y) end
function G.scale(sx, sy) multiply(sx, 0, 0, sy or sx, 0, 0) end
function G.rotate(angle)
    local c, s = math.cos(angle), math.sin(angle)
    multiply(c, s, -s, c, 0, 0)
end
function G.shear(kx, ky) multiply(1, ky, kx, 1, 0, 0) end

function G.transformPoint(x, y)
    local t = S.transform
    return t[1] * x + t[3] * y + t[5], t[2] * x + t[4] * y + t[6]
end

function G.inverseTransformPoint(x, y)
    local t = S.transform
    local det = t[1] * t[4] - t[2] * t[3]
    if det == 0 then
        return 0, 0
    end
    local px, py = x - t[5], y - t[6]
    return (t[4] * px - t[3] * py) / det, (-t[2] * px + t[1] * py) / det
end

local function snapshot()
    local copy = {}
    for key, value in pairs(S) do
        if key ~= 'stack' then
            if type(value) == 'table' and key ~= 'canvases' and key ~= 'canvasOptions' then
                local c = {}
                for k, v in pairs(value) do
                    c[k] = v
                end
                copy[key] = c
            else
                copy[key] = value
            end
        end
    end
    return copy
end

function G.push(kind)
    kind = kind or 'transform'
    assert(kind == 'transform' or kind == 'all', 'Invalid stack type: ' .. tostring(kind))
    assert(#S.stack < 128, 'Maximum stack depth reached (more pushes than pops?)')
    local t = S.transform
    local entry = { transform = { t[1], t[2], t[3], t[4], t[5], t[6] } }
    if kind == 'all' then
        entry.all = snapshot()
    end
    S.stack[#S.stack + 1] = entry
end

function G.pop()
    local entry = table.remove(S.stack)
    assert(entry, 'Minimum stack depth reached (more pops than pushes?)')
    local t = S.transform
    for i = 1, 6 do
        t[i] = entry.transform[i]
    end
    local all = entry.all
    if all then
        G.setCanvasInternal(all.canvases, all.canvasOptions)
        G.setColor(all.color)
        G.setBlendMode(all.blend, all.alphaMode)
        G.setColorMask(unpack(all.colorMask))
        if all.scissor then
            G.setScissor(unpack(all.scissor))
        else
            G.setScissor()
        end
        if all.stencilTest then
            G.setStencilTest(all.stencilTest[1], all.stencilTest[2])
        else
            G.setStencilTest()
        end
        G.setDepthMode(all.depthCompare, all.depthWrite)
        G.setMeshCullMode(all.cull)
        G.setFrontFaceWinding(all.winding)
        G.setWireframe(all.wireframe)
        G.setLineWidth(all.lineWidth)
        G.setLineJoin(all.lineJoin)
        G.setLineStyle(all.lineStyle)
        G.setShader(all.shader)
        S.font = all.font
        S.pointSize = all.pointSize
    end
end

-- Color, blend, mask ---------------------------------------------------------------------------

local function colorArgs(r, g, b, a)
    if type(r) == 'table' then
        return r[1], r[2], r[3], r[4] == nil and 1 or r[4]
    end
    return r, g, b, a == nil and 1 or a
end

function G.setColor(r, g, b, a)
    r, g, b, a = colorArgs(r, g, b, a)
    local c = S.color
    c[1], c[2], c[3], c[4] = r, g, b, a
end
function G.getColor() local c = S.color return c[1], c[2], c[3], c[4] end
function G.setBackgroundColor(r, g, b, a)
    r, g, b, a = colorArgs(r, g, b, a)
    S.background = { r, g, b, a }
end
function G.getBackgroundColor() local c = S.background return c[1], c[2], c[3], c[4] end

local blendFactors
local function blendTable()
    local O, Z, SA, ISA = E.ONE, E.ZERO, E.SRC_ALPHA, E.ONE_MINUS_SRC_ALPHA
    return {
        alpha = { E.FUNC_ADD, SA, O, ISA, ISA },
        replace = { E.FUNC_ADD, O, O, Z, Z, exact = true },
        screen = { E.FUNC_ADD, SA, O, E.ONE_MINUS_SRC_COLOR, ISA },
        add = { E.FUNC_ADD, SA, Z, O, O },
        subtract = { E.FUNC_REVERSE_SUBTRACT, SA, Z, O, O },
        multiply = { E.FUNC_ADD, E.DST_COLOR, E.DST_COLOR, Z, Z, exact = true },
        lighten = { E.MAX, O, O, O, O, exact = true },
        darken = { E.MIN, O, O, O, O, exact = true },
    }
end

local function applyBlend()
    blendFactors = blendFactors or blendTable()
    local spec = blendFactors[S.blend] or blendFactors.alpha
    local fn, srcRGB, srcA, dstRGB, dstA = spec[1], spec[2], spec[3], spec[4], spec[5]
    if not spec.exact and S.alphaMode == 'premultiplied' and srcRGB == E.SRC_ALPHA then
        srcRGB = E.ONE
    end
    gl.glBlendEquationSeparate(fn, fn)
    gl.glBlendFuncSeparate(srcRGB, dstRGB, srcA, dstA)
end

function G.setBlendMode(mode, alphamode)
    requireReady()
    flush()
    blendFactors = blendFactors or blendTable()
    assert(blendFactors[mode], 'Invalid blend mode: ' .. tostring(mode))
    S.blend, S.alphaMode = mode, alphamode or 'alphamultiply'
    applyBlend()
end
function G.getBlendMode() return S.blend, S.alphaMode end

local function applyColorMask()
    local m = S.colorMask
    gl.glColorMask(m[1], m[2], m[3], m[4])
end
function G.setColorMask(r, g, b, a)
    flush()
    if r == nil then
        r, g, b, a = true, true, true, true
    end
    S.colorMask = { not not r, not not g, not not b, not not a }
    applyColorMask()
end
function G.getColorMask() local m = S.colorMask return m[1], m[2], m[3], m[4] end

-- Scissor, stencil, depth, cull ------------------------------------------------------------------

local function applyScissor()
    local s = S.scissor
    if not s then
        gl.glDisable(E.SCISSOR_TEST)
        return
    end
    local dpi = target.dpi
    local x, y, w, h = s[1] * dpi, s[2] * dpi, s[3] * dpi, s[4] * dpi
    local glY = target.isCanvas and y or (target.ph - (y + h))
    gl.glEnable(E.SCISSOR_TEST)
    gl.glScissor(math.floor(x + 0.5), math.floor(glY + 0.5), math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5)))
end

function G.setScissor(x, y, w, h)
    requireReady()
    flush()
    if x == nil then
        S.scissor = nil
    else
        assert(w >= 0 and h >= 0, 'Scissor width and height must be non-negative')
        S.scissor = { x, y, w, h }
    end
    applyScissor()
end
function G.getScissor()
    local s = S.scissor
    if s then
        return s[1], s[2], s[3], s[4]
    end
end
function G.intersectScissor(x, y, w, h)
    local s = S.scissor
    if not s then
        return G.setScissor(x, y, w, h)
    end
    local x1, y1 = math.max(s[1], x), math.max(s[2], y)
    local x2, y2 = math.min(s[1] + s[3], x + w), math.min(s[2] + s[4], y + h)
    G.setScissor(x1, y1, math.max(0, x2 - x1), math.max(0, y2 - y1))
end

local compareFunctions
local function compareTable()
    return {
        never = E.NEVER, less = E.LESS, equal = E.EQUAL, lequal = E.LEQUAL, greater = E.GREATER,
        notequal = E.NOTEQUAL, gequal = E.GEQUAL, always = E.ALWAYS,
    }
end
-- The stencil test reads "pixel passes when stencil <compare> value", GL tests "value <func> stencil".
local reversed = { less = 'greater', greater = 'less', lequal = 'gequal', gequal = 'lequal' }

local function applyStencilTest()
    compareFunctions = compareFunctions or compareTable()
    local t = S.stencilTest
    if not t then
        gl.glDisable(E.STENCIL_TEST)
        return
    end
    gl.glEnable(E.STENCIL_TEST)
    gl.glStencilFunc(compareFunctions[reversed[t[1]] or t[1]], t[2], 0xFF)
    gl.glStencilOp(E.KEEP, E.KEEP, E.KEEP)
    gl.glStencilMask(0)
end

function G.setStencilTest(compare, value)
    requireReady()
    flush()
    compareFunctions = compareFunctions or compareTable()
    if compare == nil then
        S.stencilTest = nil
    else
        assert(compareFunctions[compare], 'Invalid compare mode: ' .. tostring(compare))
        S.stencilTest = { compare, value or 0 }
    end
    applyStencilTest()
end
function G.getStencilTest()
    local t = S.stencilTest
    if t then
        return t[1], t[2]
    end
    return 'always', 0
end

function G.stencil(fn, action, value, keepvalues)
    requireReady()
    flush()
    action = action or 'replace'
    value = value or 1
    local ops = {
        replace = E.REPLACE, increment = E.INCR, decrement = E.DECR,
        incrementwrap = E.INCR_WRAP, decrementwrap = E.DECR_WRAP, invert = E.INVERT,
    }
    assert(ops[action], 'Invalid stencil action: ' .. tostring(action))
    if not keepvalues then
        gl.glStencilMask(0xFF)
        gl.glClearStencil(0)
        gl.glClear(E.STENCIL_BUFFER_BIT)
    end
    gl.glEnable(E.STENCIL_TEST)
    gl.glStencilFunc(E.ALWAYS, value, 0xFF)
    gl.glStencilOp(E.KEEP, E.KEEP, ops[action])
    gl.glStencilMask(0xFF)
    gl.glColorMask(false, false, false, false)
    fn()
    flush()
    applyColorMask()
    applyStencilTest()
end

function G.setDepthMode(compare, write)
    requireReady()
    flush()
    compareFunctions = compareFunctions or compareTable()
    S.depthCompare, S.depthWrite = compare or 'always', write and true or false
    assert(compareFunctions[S.depthCompare], 'Invalid compare mode: ' .. tostring(compare))
    gl.glEnable(E.DEPTH_TEST)
    gl.glDepthFunc(compareFunctions[S.depthCompare])
    gl.glDepthMask(S.depthWrite)
end
function G.getDepthMode() return S.depthCompare, S.depthWrite end

local function applyCull()
    if S.cull == 'none' then
        gl.glDisable(E.CULL_FACE)
        return
    end
    gl.glEnable(E.CULL_FACE)
    gl.glCullFace(S.cull == 'back' and E.BACK or E.FRONT)
    -- Rendering into a canvas flips the 2D projection, so front faces flip as well.
    local ccw = (S.winding == 'ccw') ~= target.isCanvas
    gl.glFrontFace(ccw and E.CCW or E.CW)
end
function G.setMeshCullMode(mode)
    requireReady()
    flush()
    assert(mode == 'none' or mode == 'back' or mode == 'front', 'Invalid cull mode: ' .. tostring(mode))
    S.cull = mode
    applyCull()
end
function G.getMeshCullMode() return S.cull end
function G.setFrontFaceWinding(winding)
    flush()
    assert(winding == 'cw' or winding == 'ccw', 'Invalid winding: ' .. tostring(winding))
    S.winding = winding
    applyCull()
end
function G.getFrontFaceWinding() return S.winding end

function G.setWireframe(enabled)
    flush()
    S.wireframe = not not enabled
    if gl and gl.glPolygonMode then
        gl.glPolygonMode(0x408, S.wireframe and 0x1B01 or 0x1B02)
    end
end
function G.isWireframe() return S.wireframe end

function G.setLineWidth(width) S.lineWidth = width end
function G.getLineWidth() return S.lineWidth end
function G.setLineJoin(join) S.lineJoin = join end
function G.getLineJoin() return S.lineJoin end
function G.setLineStyle(style) S.lineStyle = style end
function G.getLineStyle() return S.lineStyle end
function G.setPointSize(size) S.pointSize = size end
function G.getPointSize() return S.pointSize end

function G.setDefaultFilter(min, mag, anisotropy)
    Texture.defaultFilter.min, Texture.defaultFilter.mag = min, mag or min
    Texture.defaultFilter.anisotropy = anisotropy or 1
end
function G.getDefaultFilter()
    local f = Texture.defaultFilter
    return f.min, f.mag, f.anisotropy
end

-- Shaders ----------------------------------------------------------------------------------------

function G.setShader(shader)
    requireReady()
    if S.shader ~= shader then
        flush()
        stats.shaderswitches = stats.shaderswitches + 1
    end
    S.shader = shader
end
function G.getShader() return S.shader end

function G.newShader(...)
    requireReady()
    return Shader.new(...)
end

function G.validateShader(gles, code, vertex)
    if type(gles) ~= 'boolean' then
        gles, code, vertex = false, gles, code
    end
    local source = code or vertex
    if gles then
        local FS = require('source.katsa.core.filesystem')
        if type(source) == 'string' and not source:find('\n', 1, true) and FS.getInfo(source, 'file') then
            source = FS.read(source)
        end
        local translated, message = Translator.translate(source, { target = 'es' })
        if not translated then
            return false, message
        end
        return true, ''
    end
    return Shader.validate(source)
end

-- Canvas targets ---------------------------------------------------------------------------------

local fboCache = {}
local currentFbo = 0
-- Helper code (resolves, readbacks, probes) rebinds framebuffers; put the active target back.
Core.restoreFramebuffer = function()
    Core.boundFramebuffer = nil
    Core.bindFramebuffer(currentFbo)
end
local sharedDepth = {}

local function sharedDepthStencil(w, h, msaa)
    local key = w .. 'x' .. h .. ':' .. msaa
    local entry = sharedDepth[key]
    if not entry then
        local id = ffi.new('GLuint[1]')
        gl.glGenRenderbuffers(1, id)
        gl.glBindRenderbuffer(E.RENDERBUFFER, id[0])
        if msaa > 0 then
            gl.glRenderbufferStorageMultisample(E.RENDERBUFFER, msaa, E.DEPTH24_STENCIL8, w, h)
        else
            gl.glRenderbufferStorage(E.RENDERBUFFER, E.DEPTH24_STENCIL8, w, h)
        end
        entry = id[0]
        sharedDepth[key] = entry
    end
    return entry
end

local function dropFbo(id)
    for key, value in pairs(fboCache) do
        if value == id then
            fboCache[key] = nil
        end
    end
end

local function fboFor(canvases, options)
    local first = canvases[1]
    local keys = {}
    for i, c in ipairs(canvases) do
        local kind, id = c:_renderAttachment()
        keys[i] = kind:sub(1, 1) .. id
    end
    local depth = options.depthstencil
    if depth then
        local kind, id = depth:_renderAttachment()
        keys[#keys + 1] = 'd' .. kind:sub(1, 1) .. id
    elseif options.stencil or options.depth then
        keys[#keys + 1] = 's' .. first._pw .. 'x' .. first._ph .. ':' .. first._msaa
    end
    local key = table.concat(keys, ',')
    local fbo = fboCache[key]
    if fbo then
        return fbo
    end
    local id = ffi.new('GLuint[1]')
    gl.glGenFramebuffers(1, id)
    fbo = id[0]
    Core.bindFramebuffer(fbo)
    local drawBuffers = ffi.new('GLenum[?]', #canvases)
    for i, c in ipairs(canvases) do
        c:_attachTo(E.COLOR_ATTACHMENT0 + i - 1)
        drawBuffers[i - 1] = E.COLOR_ATTACHMENT0 + i - 1
    end
    gl.glDrawBuffers(#canvases, drawBuffers)
    if depth then
        local point = depth._info.stencil and E.DEPTH_STENCIL_ATTACHMENT or E.DEPTH_ATTACHMENT
        depth:_attachTo(point)
    elseif options.stencil or options.depth then
        gl.glFramebufferRenderbuffer(E.FRAMEBUFFER, E.DEPTH_STENCIL_ATTACHMENT, E.RENDERBUFFER,
            sharedDepthStencil(first._pw, first._ph, first._msaa))
    end
    local status = gl.glCheckFramebufferStatus(E.FRAMEBUFFER)
    if status ~= E.FRAMEBUFFER_COMPLETE then
        local one = ffi.new('GLuint[1]', fbo)
        Core.framebufferChanged()
        gl.glDeleteFramebuffers(1, one)
        return nil, status
    end
    fboCache[key] = fbo
    return fbo
end
Core.onFramebufferDeleted = dropFbo

local function markTargetsDirty()
    if S.canvases then
        for _, c in ipairs(S.canvases) do
            c._dirty = true
        end
        if S.canvasOptions and S.canvasOptions.depthstencil then
            S.canvasOptions.depthstencil._dirty = true
        end
    end
end

-- Parses setCanvas arguments into a list of canvases and options.
local function parseCanvasArgs(...)
    local first = ...
    if first == nil then
        return nil, nil
    end
    local list, options = {}, {}
    if first.typeOf and first:typeOf('Texture') then
        for _, c in ipairs({ ... }) do
            list[#list + 1] = c
        end
    else
        for _, c in ipairs(first) do
            list[#list + 1] = c
        end
        options.stencil = first.stencil
        options.depth = first.depth
        options.depthstencil = first.depthstencil
        if first.depthstencil and type(first.depthstencil) == 'table' and first.depthstencil.canvas then
            options.depthstencil = first.depthstencil.canvas
        end
    end
    if #list == 0 then
        return nil, nil
    end
    return list, options
end

function G.setCanvasInternal(canvases, options)
    requireReady()
    flush()
    options = options or {}
    if canvases == nil then
        S.canvases, S.canvasOptions = nil, nil
        currentFbo = 0
        Core.bindFramebuffer(0)
        stats.canvasswitches = stats.canvasswitches + 1
    else
        local first = canvases[1]
        for _, c in ipairs(canvases) do
            assert(c._kind == 'canvas', 'setCanvas expects Canvas objects')
            assert(not c._depth, 'Depth canvases can only be used as the depthstencil target')
            assert(c._pw == first._pw and c._ph == first._ph, 'All canvases must have the same pixel dimensions')
            assert(c._msaa == first._msaa, 'All canvases must have the same MSAA value')
        end
        assert(#canvases <= Core.limits.multicanvas, 'This system can\'t simultaneously render to that many canvases')
        local depth = options.depthstencil
        if depth then
            assert(depth._pw == first._pw and depth._ph == first._ph, 'The depthstencil canvas must match the canvas size')
            assert(depth._msaa == first._msaa, 'The depthstencil canvas must have the same MSAA value as the color canvas')
        end
        local fbo, status = fboFor(canvases, options)
        if not fbo then
            error(('Canvas cannot be used as a render target (framebuffer status 0x%X)'):format(status), 3)
        end
        S.canvases, S.canvasOptions = canvases, options
        currentFbo = fbo
        Core.bindFramebuffer(fbo)
        stats.canvasswitches = stats.canvasswitches + 1
        markTargetsDirty()
    end
    applyViewport()
    applyScissor()
    applyCull()
end

function G.setCanvas(...)
    local list, options = parseCanvasArgs(...)
    local oldCanvases, oldOptions = S.canvases, S.canvasOptions
    local ok, err = pcall(G.setCanvasInternal, list, options)
    if not ok then
        pcall(G.setCanvasInternal, oldCanvases, oldOptions)
        error(err, 2)
    end
end

function G.getCanvas()
    if S.canvases then
        return unpack(S.canvases)
    end
    return nil
end

function G.newCanvas(width, height, settings)
    requireReady()
    if type(width) ~= 'number' then
        width, height, settings = G.getWidth(), G.getHeight(), width
    end
    if type(height) == 'table' or height == nil then
        settings, height = height, width
    end
    local canvas = Texture.newCanvas(width, height, settings)
    return canvas
end

function G.newImage(source, settings)
    requireReady()
    return Texture.newImage(source, settings)
end

function G.newMesh(...)
    requireReady()
    return Mesh.new(...)
end

local formatProbe = {}
function G.getCanvasFormats(readable)
    requireReady()
    local names = { 'normal', 'rgba8', 'srgb', 'r8', 'rg8', 'rgba16f', 'rgba32f', 'r16f', 'r32f', 'rg16f', 'rgb10a2',
        'depth16', 'depth24', 'depth32f', 'depth24stencil8', 'depth32fstencil8', 'stencil8' }
    local out = {}
    for _, name in ipairs(names) do
        if formatProbe[name] == nil then
            local ok = pcall(function()
                local c = Texture.newCanvas(2, 2, { format = name, dpiscale = 1 })
                local info = c._info
                local id = ffi.new('GLuint[1]')
                gl.glGenFramebuffers(1, id)
                Core.bindFramebuffer(id[0])
                local point = info.depth and (info.stencil and E.DEPTH_STENCIL_ATTACHMENT or E.DEPTH_ATTACHMENT) or E.COLOR_ATTACHMENT0
                c:_attachTo(point)
                local status = gl.glCheckFramebufferStatus(E.FRAMEBUFFER)
                Core.framebufferChanged()
                local fb = ffi.new('GLuint[1]', id[0])
                gl.glDeleteFramebuffers(1, fb)
                c:release()
                assert(status == E.FRAMEBUFFER_COMPLETE)
            end)
            gl.glGetError()
            formatProbe[name] = ok
            -- restore the real target after probing
            Core.restoreFramebuffer()
        end
        out[name] = formatProbe[name]
    end
    return out
end

-- Clear ------------------------------------------------------------------------------------------

function G.clear(...)
    requireReady()
    flush()
    local args = { ... }
    local colors, rest = {}, 1
    if type(args[1]) == 'table' then
        local count = 0
        while type(args[rest]) == 'table' or args[rest] == false do
            count = count + 1
            colors[count] = args[rest]
            rest = rest + 1
        end
    elseif type(args[1]) == 'number' then
        colors[1] = { args[1], args[2], args[3], args[4] == nil and 1 or args[4] }
        rest = 5
    else
        colors[1] = { 0, 0, 0, 0 }
        rest = 1
    end
    local clearStencil, clearDepth = args[rest], args[rest + 1]
    local stencilValue, depthValue
    if clearStencil == nil or clearStencil == true then
        stencilValue = 0
    elseif type(clearStencil) == 'number' then
        stencilValue = clearStencil
    end
    if clearDepth == nil or clearDepth == true then
        depthValue = 1
    elseif type(clearDepth) == 'number' then
        depthValue = clearDepth
    end
    -- glClear is affected by the scissor box and write masks; clearing ignores both.
    local hadScissor = S.scissor ~= nil
    if hadScissor then
        gl.glDisable(E.SCISSOR_TEST)
    end
    gl.glColorMask(true, true, true, true)
    local mask = 0
    local multi = S.canvases and #S.canvases > 1
    if multi then
        local zero = ffi.new('GLfloat[4]')
        for i = 1, #S.canvases do
            local c = colors[i]
            if c then
                gl.glClearColor(c[1], c[2], c[3], c[4] == nil and 1 or c[4])
                local single = ffi.new('GLenum[1]', E.COLOR_ATTACHMENT0 + i - 1)
                gl.glDrawBuffers(1, single)
                gl.glClear(E.COLOR_BUFFER_BIT)
            end
        end
        local all = ffi.new('GLenum[?]', #S.canvases)
        for i = 1, #S.canvases do
            all[i - 1] = E.COLOR_ATTACHMENT0 + i - 1
        end
        gl.glDrawBuffers(#S.canvases, all)
    elseif colors[1] then
        local c = colors[1]
        gl.glClearColor(c[1], c[2], c[3], c[4] == nil and 1 or c[4])
        mask = E.COLOR_BUFFER_BIT
    end
    if stencilValue then
        gl.glStencilMask(0xFF)
        gl.glClearStencil(stencilValue)
        mask = bit.bor(mask, E.STENCIL_BUFFER_BIT)
    end
    if depthValue then
        gl.glDepthMask(true)
        gl.glClearDepthf(depthValue)
        mask = bit.bor(mask, E.DEPTH_BUFFER_BIT)
    end
    if mask ~= 0 then
        gl.glClear(mask)
    end
    if depthValue then
        gl.glDepthMask(S.depthWrite)
    end
    applyColorMask()
    applyStencilTest()
    if hadScissor then
        applyScissor()
    end
    markTargetsDirty()
end

-- Batched drawing ----------------------------------------------------------------------------------

local uniformMatrix = ffi.new('float[16]')
local normalMatrix = ffi.new('float[9]')
local screenSize = ffi.new('float[4]')
local colorBuffer = ffi.new('float[4]')

local function projectionInto(m)
    local w, h = target.w, target.h
    ffi.fill(m, 64)
    m[0] = 2 / w
    m[12] = -1
    if target.isCanvas then
        m[5] = 2 / h
        m[13] = -1
    else
        m[5] = -2 / h
        m[13] = 1
    end
    m[10] = -1
    m[15] = 1
end

local function activeShader()
    return S.shader or defaultShader
end

-- Sends built-in uniforms. `modelview` is the affine transform for mesh draws, nil for batched draws.
local function sendBuiltins(shader, modelview, withColor)
    local b = shader._builtin
    local proj = ffi.new('float[16]')
    projectionInto(proj)
    local t = modelview or { 1, 0, 0, 1, 0, 0 }
    local model = ffi.new('float[16]')
    model[0], model[1], model[4], model[5], model[10], model[12], model[13], model[15] = t[1], t[2], t[3], t[4], 1, t[5], t[6], 1
    if b.TransformMatrix >= 0 then
        gl.glUniformMatrix4fv(b.TransformMatrix, 1, 0, model)
    end
    if b.ProjectionMatrix >= 0 then
        gl.glUniformMatrix4fv(b.ProjectionMatrix, 1, 0, proj)
    end
    if b.TransformProjectionMatrix >= 0 then
        local out = ffi.new('float[16]')
        for col = 0, 3 do
            for row = 0, 3 do
                local sum = 0
                for k = 0, 3 do
                    sum = sum + proj[k * 4 + row] * model[col * 4 + k]
                end
                out[col * 4 + row] = sum
            end
        end
        gl.glUniformMatrix4fv(b.TransformProjectionMatrix, 1, 0, out)
    end
    if b.NormalMatrix >= 0 then
        local det = t[1] * t[4] - t[2] * t[3]
        ffi.fill(normalMatrix, 36)
        if det ~= 0 then
            normalMatrix[0], normalMatrix[1], normalMatrix[3], normalMatrix[4] = t[4] / det, -t[3] / det, -t[2] / det, t[1] / det
        end
        normalMatrix[8] = 1
        gl.glUniformMatrix3fv(b.NormalMatrix, 1, 0, normalMatrix)
    end
    if b.ConstantColor >= 0 then
        local c = S.color
        if withColor then
            gl.glUniform4fv(b.ConstantColor, 1, ffi.new('float[4]', c[1], c[2], c[3], c[4]))
        else
            gl.glUniform4fv(b.ConstantColor, 1, ffi.new('float[4]', 1, 1, 1, 1))
        end
    end
    if b.love_PointSize >= 0 then
        gl.glUniform1fv(b.love_PointSize, 1, ffi.new('float[1]', S.pointSize))
    end
    if b.love_ScreenSize >= 0 then
        if target.isCanvas then
            screenSize[0], screenSize[1], screenSize[2], screenSize[3] = target.pw, target.ph, 1, 0
        else
            screenSize[0], screenSize[1], screenSize[2], screenSize[3] = target.pw, target.ph, -1, target.ph
        end
        gl.glUniform4fv(b.love_ScreenSize, 1, screenSize)
    end
end

local function prepareDraw(textureObject, modelview, withColor)
    local shader = activeShader()
    Core.useProgram(shader._program)
    sendBuiltins(shader, modelview, withColor)
    shader:_bindSamplers()
    local id
    if textureObject then
        id = textureObject:_sampleId()
    end
    Core.bindTexture(0, id or Core.defaultTextureId)
    return shader
end

function G._flushBatch()
    local n = batch.count
    if n == 0 then
        return
    end
    batch.count = 0
    prepareDraw(batch.texture, nil, false)
    gl.glBindBuffer(E.ARRAY_BUFFER, batch.vbo)
    gl.glBufferData(E.ARRAY_BUFFER, n * 20, batch.vertices, E.STREAM_DRAW)
    gl.glVertexAttribPointer(0, 2, E.FLOAT, 0, 20, ffi.cast('void*', 0))
    gl.glVertexAttribPointer(1, 2, E.FLOAT, 0, 20, ffi.cast('void*', 8))
    gl.glVertexAttribPointer(2, 4, E.UNSIGNED_BYTE, 1, 20, ffi.cast('void*', 16))
    for location = 0, 2 do
        gl.glEnableVertexAttribArray(location)
        gl.glVertexAttribDivisor(location, 0)
    end
    local shader = activeShader()
    local wanted = { [0] = true, true, true }
    for _, location in pairs(shader._attributeLocations) do
        gl.glVertexAttrib4f(location, 0, 0, 0, 1)
    end
    Core.setEnabledAttributes(wanted)
    gl.glDrawArrays(E.TRIANGLES, 0, n)
    stats.drawcalls = stats.drawcalls + 1
    markTargetsDirty()
end

function G.flushBatch()
    flush()
end

local function setBatchTexture(texture)
    if batch.texture ~= texture then
        flush()
        batch.texture = texture
    end
end

local function reserve(count, texture)
    if batch.count + count > VERTEX_CAPACITY then
        flush()
    end
    if batch.texture ~= texture then
        flush()
        batch.texture = texture
    end
end

local function packColor()
    local c = S.color
    return math.floor(math.max(0, math.min(1, c[1])) * 255 + 0.5),
        math.floor(math.max(0, math.min(1, c[2])) * 255 + 0.5),
        math.floor(math.max(0, math.min(1, c[3])) * 255 + 0.5),
        math.floor(math.max(0, math.min(1, c[4])) * 255 + 0.5)
end

local function push(x, y, u, v, r, g, b, a)
    local vertex = batch.vertices[batch.count]
    vertex.x, vertex.y, vertex.u, vertex.v, vertex.r, vertex.g, vertex.b, vertex.a = x, y, u, v, r, g, b, a
    batch.count = batch.count + 1
end

-- Adds a transformed quad given its four local corners and uvs.
local function addQuad(texture, x1, y1, x2, y2, x3, y3, x4, y4, u0, v0, u1, v1, matrix)
    reserve(6, texture)
    local r, g, b, a = packColor()
    local t = matrix or S.transform
    local a1, b1, c1, d1, e1, f1 = t[1], t[2], t[3], t[4], t[5], t[6]
    local function tx(x, y) return a1 * x + c1 * y + e1, b1 * x + d1 * y + f1 end
    local px1, py1 = tx(x1, y1)
    local px2, py2 = tx(x2, y2)
    local px3, py3 = tx(x3, y3)
    local px4, py4 = tx(x4, y4)
    push(px1, py1, u0, v0, r, g, b, a)
    push(px2, py2, u1, v0, r, g, b, a)
    push(px3, py3, u0, v1, r, g, b, a)
    push(px3, py3, u0, v1, r, g, b, a)
    push(px2, py2, u1, v0, r, g, b, a)
    push(px4, py4, u1, v1, r, g, b, a)
end

local function localTransform(x, y, angle, sx, sy, ox, oy, kx, ky)
    x, y, angle = x or 0, y or 0, angle or 0
    sx = sx or 1
    sy = sy or sx
    ox, oy, kx, ky = ox or 0, oy or 0, kx or 0, ky or 0
    local c, s = math.cos(angle), math.sin(angle)
    -- translate * rotate * scale * shear * translate(-origin)
    local a = c * sx - ky * s * sy
    local b = s * sx + ky * c * sy
    local cc = kx * c * sx - s * sy
    local d = kx * s * sx + c * sy
    local e = x - ox * a - oy * cc
    local f = y - ox * b - oy * d
    return a, b, cc, d, e, f
end

local function composed(x, y, angle, sx, sy, ox, oy, kx, ky)
    local a, b, c, d, e, f = localTransform(x, y, angle, sx, sy, ox, oy, kx, ky)
    local t = S.transform
    return {
        t[1] * a + t[3] * b, t[2] * a + t[4] * b,
        t[1] * c + t[3] * d, t[2] * c + t[4] * d,
        t[1] * e + t[3] * f + t[5], t[2] * e + t[4] * f + t[6],
    }
end

-- Quads --------------------------------------------------------------------------------------------

local QuadMethods = {}
QuadMethods.__index = QuadMethods
function G.newQuad(x, y, w, h, sw, sh)
    if type(sw) == 'table' then
        sw, sh = sw:getPixelDimensions()
    end
    return setmetatable({ x = x, y = y, w = w, h = h, sw = sw, sh = sh }, QuadMethods)
end
function QuadMethods:getViewport() return self.x, self.y, self.w, self.h end
function QuadMethods:setViewport(x, y, w, h, sw, sh)
    self.x, self.y, self.w, self.h = x, y, w, h
    if sw then
        self.sw, self.sh = sw, sh
    end
end
function QuadMethods:getTextureDimensions() return self.sw, self.sh end
function QuadMethods:type() return 'Quad' end
function QuadMethods:typeOf(name) return name == 'Quad' or name == 'Object' end
function QuadMethods:release() return true end

-- Drawing --------------------------------------------------------------------------------------------

local function drawTexture(texture, quad, matrix)
    local dpi = texture._dpi
    if quad then
        local u0, v0 = quad.x / quad.sw, quad.y / quad.sh
        local u1, v1 = (quad.x + quad.w) / quad.sw, (quad.y + quad.h) / quad.sh
        local w, h = quad.w / dpi, quad.h / dpi
        addQuad(texture, 0, 0, w, 0, 0, h, w, h, u0, v0, u1, v1, matrix)
    else
        local w, h = texture._pw / dpi, texture._ph / dpi
        addQuad(texture, 0, 0, w, 0, 0, h, w, h, 0, 0, 1, 1, matrix)
    end
end

local function drawMesh(mesh, matrix, instances)
    flush()
    local texture = mesh._texture
    local shader = prepareDraw(texture, matrix, true)
    mesh:_bindAttributes(shader)
    mesh:_draw(instances)
    stats.drawcalls = stats.drawcalls + 1
    markTargetsDirty()
end

function G.draw(drawable, ...)
    requireReady()
    local args = { ... }
    local quad
    if type(args[1]) == 'table' and getmetatable(args[1]) == QuadMethods then
        quad = table.remove(args, 1)
    end
    local matrix = composed(args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9])
    if drawable._kind == 'image' or drawable._kind == 'canvas' then
        drawTexture(drawable, quad, matrix)
    elseif drawable.type and drawable:type() == 'Mesh' then
        drawMesh(drawable, matrix)
    elseif drawable._draw2D then
        drawable:_draw2D(G, matrix)
    else
        error('Cannot draw this object', 2)
    end
end

function G.drawInstanced(mesh, count, ...)
    requireReady()
    local args = { ... }
    local matrix = composed(args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9])
    drawMesh(mesh, matrix, count)
end

-- Exposed for text and sprite batches: draws a textured quad with an explicit local->screen matrix.
function G._drawQuadRaw(texture, w, h, u0, v0, u1, v1, matrix)
    addQuad(texture, 0, 0, w, 0, 0, h, w, h, u0, v0, u1, v1, matrix)
end
function G._currentTransform() return S.transform end
function G._composed(...) return composed(...) end

-- Primitives ---------------------------------------------------------------------------------------------

local function triangle(x1, y1, x2, y2, x3, y3)
    reserve(3, nil)
    local r, g, b, a = packColor()
    local t = S.transform
    local function tx(x, y) return t[1] * x + t[3] * y + t[5], t[2] * x + t[4] * y + t[6] end
    local ax, ay = tx(x1, y1)
    local bx, by = tx(x2, y2)
    local cx, cy = tx(x3, y3)
    push(ax, ay, 0, 0, r, g, b, a)
    push(bx, by, 0, 0, r, g, b, a)
    push(cx, cy, 0, 0, r, g, b, a)
end

local function fillPolygon(points)
    -- Triangle fan from the first vertex (convex shapes), like LÖVE's fill mode.
    for i = 3, #points / 2 do
        triangle(points[1], points[2], points[2 * i - 3], points[2 * i - 2], points[2 * i - 1], points[2 * i])
    end
end

local function polyline(points, closed)
    local width = S.lineWidth
    local half = width * 0.5
    local n = #points / 2
    local segments = closed and n or n - 1
    local px, py
    local normals = {}
    for i = 1, segments do
        local x1, y1 = points[2 * i - 1], points[2 * i]
        local j = i % n + 1
        local x2, y2 = points[2 * j - 1], points[2 * j]
        local dx, dy = x2 - x1, y2 - y1
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0 then
            local nx, ny = -dy / length * half, dx / length * half
            triangle(x1 + nx, y1 + ny, x1 - nx, y1 - ny, x2 + nx, y2 + ny)
            triangle(x2 + nx, y2 + ny, x1 - nx, y1 - ny, x2 - nx, y2 - ny)
            normals[i] = { nx, ny, x1, y1, x2, y2 }
        end
    end
    -- Joins: fill the wedge on the outer side with a bevel triangle.
    if S.lineJoin ~= 'none' and half > 0.5 then
        local count = closed and segments or segments - 1
        for i = 1, count do
            local a, b = normals[i], normals[i % segments + 1]
            if a and b then
                local cross = (a[5] - a[3]) * (b[6] - b[4]) - (a[6] - a[4]) * (b[5] - b[3])
                local sign = cross > 0 and -1 or 1
                triangle(a[5], a[6], a[5] + sign * a[1], a[6] + sign * a[2], a[5] + sign * b[1], a[6] + sign * b[2])
            end
        end
    end
end

function G.line(...)
    requireReady()
    local points = { ... }
    if type(points[1]) == 'table' then
        points = points[1]
        if type(points[1]) == 'table' then
            local flat = {}
            for _, p in ipairs(points) do
                flat[#flat + 1], flat[#flat + 2] = p[1], p[2]
            end
            points = flat
        end
    end
    assert(#points >= 4, 'Need at least two vertices to draw a line')
    setBatchTexture(nil)
    polyline(points, false)
end

function G.polygon(mode, ...)
    requireReady()
    local points = { ... }
    if type(points[1]) == 'table' then
        points = points[1]
    end
    assert(#points >= 6, 'Need at least three vertices to draw a polygon')
    setBatchTexture(nil)
    if mode == 'fill' then
        fillPolygon(points)
    else
        polyline(points, true)
    end
end

function G.rectangle(mode, x, y, w, h, rx, ry, segments)
    requireReady()
    setBatchTexture(nil)
    local points
    if rx and rx > 0 then
        ry = ry or rx
        rx, ry = math.min(rx, w / 2), math.min(ry, h / 2)
        segments = segments or math.max(4, math.floor(math.sqrt(math.max(rx, ry)) * 2))
        points = {}
        local corners = {
            { x + w - rx, y + ry, -math.pi / 2 }, { x + w - rx, y + h - ry, 0 },
            { x + rx, y + h - ry, math.pi / 2 }, { x + rx, y + ry, math.pi },
        }
        for _, corner in ipairs(corners) do
            for i = 0, segments do
                local angle = corner[3] + (i / segments) * math.pi / 2
                points[#points + 1] = corner[1] + math.cos(angle) * rx
                points[#points + 1] = corner[2] + math.sin(angle) * ry
            end
        end
    else
        points = { x, y, x + w, y, x + w, y + h, x, y + h }
    end
    if mode == 'fill' then
        fillPolygon(points)
    else
        polyline(points, true)
    end
end

function G.circle(mode, x, y, radius, segments)
    requireReady()
    setBatchTexture(nil)
    segments = segments or math.max(8, math.floor(radius > 0 and math.sqrt(radius) * 4 or 8))
    local points = {}
    for i = 0, segments - 1 do
        local angle = i / segments * math.pi * 2
        points[#points + 1] = x + math.cos(angle) * radius
        points[#points + 1] = y + math.sin(angle) * radius
    end
    if mode == 'fill' then
        fillPolygon(points)
    else
        polyline(points, true)
    end
end

function G.points(...)
    requireReady()
    local pts = { ... }
    if type(pts[1]) == 'table' then
        pts = pts[1]
    end
    setBatchTexture(nil)
    local half = S.pointSize * 0.5
    for i = 1, #pts - 1, 2 do
        local x, y = pts[i], pts[i + 1]
        triangle(x - half, y - half, x + half, y - half, x - half, y + half)
        triangle(x + half, y - half, x + half, y + half, x - half, y + half)
    end
end

-- Sprite batches -------------------------------------------------------------------------------------

local SpriteBatch = {}
SpriteBatch.__index = SpriteBatch
function G.newSpriteBatch(texture, size, usage)
    return setmetatable({ _texture = texture, _entries = {}, _color = nil }, SpriteBatch)
end
function SpriteBatch:add(...)
    local args = { ... }
    local quad
    if type(args[1]) == 'table' and getmetatable(args[1]) == QuadMethods then
        quad = table.remove(args, 1)
    end
    local entry = { quad = quad, args = args, color = self._color and { unpack(self._color) } }
    self._entries[#self._entries + 1] = entry
    return #self._entries
end
function SpriteBatch:set(id, ...)
    local args = { ... }
    local quad
    if type(args[1]) == 'table' and getmetatable(args[1]) == QuadMethods then
        quad = table.remove(args, 1)
    end
    self._entries[id] = { quad = quad, args = args, color = self._color and { unpack(self._color) } }
end
function SpriteBatch:clear() self._entries = {} end
function SpriteBatch:flush() end
function SpriteBatch:setTexture(texture) self._texture = texture end
function SpriteBatch:getTexture() return self._texture end
function SpriteBatch:setColor(r, g, b, a)
    if r == nil then
        self._color = nil
    else
        r, g, b, a = colorArgs(r, g, b, a)
        self._color = { r, g, b, a }
    end
end
function SpriteBatch:getCount() return #self._entries end
function SpriteBatch:_draw2D(graphics, matrix)
    local saved = { unpack(S.color) }
    local savedTransform = { unpack(S.transform) }
    for i = 1, 6 do
        S.transform[i] = matrix[i]
    end
    for _, entry in ipairs(self._entries) do
        if entry.color then
            G.setColor(entry.color)
        else
            G.setColor(saved)
        end
        local a = entry.args
        local m = composed(a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9])
        drawTexture(self._texture, entry.quad, m)
    end
    for i = 1, 6 do
        S.transform[i] = savedTransform[i]
    end
    G.setColor(saved)
end
function SpriteBatch:release() return true end
function SpriteBatch:type() return 'SpriteBatch' end
function SpriteBatch:typeOf(name) return name == 'SpriteBatch' or name == 'Drawable' or name == 'Object' end

-- Window and frame ------------------------------------------------------------------------------------

local function window()
    return require('source.katsa.core.window')
end
function G.getWidth() return (window().getDimensions()) end
function G.getHeight() local _, h = window().getDimensions() return h end
function G.getDimensions() return window().getDimensions() end
function G.getPixelWidth() return target.pw end
function G.getPixelHeight() return target.ph end
function G.getPixelDimensions() return target.pw, target.ph end
function G.getDPIScale() return windowDPI() end
function G.isActive() return ready and Core.platform:isVisible() end
function G.isCreated() return ready end
function G.getRendererInfo()
    requireReady()
    return Core.rendererInfo()
end
function G.getSystemLimits()
    requireReady()
    local l = Core.limits
    return {
        pointsize = 64, texturesize = l.texturesize, multicanvas = l.multicanvas, canvasmsaa = l.canvasmsaa,
        anisotropy = l.textureanisotropy, texturelayers = 256, volumetexturesize = 256,
    }
end
function G.getStats(into)
    local out = into or {}
    out.drawcalls = stats.drawcalls
    out.drawcallsbatched = stats.drawcallsbatched
    out.canvasswitches = stats.canvasswitches
    out.shaderswitches = stats.shaderswitches
    out.images, out.canvases, out.fonts = counters.images, counters.canvases, counters.fonts
    out.texturememory = counters.texturememory
    return out
end
Texture.counters = counters

function G.captureScreenshot(target)
    screenshots[#screenshots + 1] = target
end

local function readBackbuffer()
    local ImageModule = require('source.katsa.image')
    Core.bindFramebuffer(0)
    local w, h = target.pw, target.ph
    local data = ImageModule.newImageData(w, h, 'rgba8')
    gl.glPixelStorei(E.PACK_ALIGNMENT, 1)
    gl.glReadPixels(0, 0, w, h, E.RGBA, E.UNSIGNED_BYTE, data:getPointer())
    -- GL rows run bottom to top; images run top to bottom.
    local row = w * 4
    local tmp = ffi.new('uint8_t[?]', row)
    local p = data:getPointer()
    for y = 0, math.floor(h / 2) - 1 do
        ffi.copy(tmp, p + y * row, row)
        ffi.copy(p + y * row, p + (h - 1 - y) * row, row)
        ffi.copy(p + (h - 1 - y) * row, tmp, row)
    end
    return data
end

function G.present()
    requireReady()
    flush()
    assert(not S.canvases, 'present cannot be called while a Canvas is active.')
    if #screenshots > 0 then
        local pending = screenshots
        screenshots = {}
        local image = readBackbuffer()
        for _, request in ipairs(pending) do
            if type(request) == 'function' then
                request(image:clone())
            elseif type(request) == 'string' then
                image:encode('png', request)
            end
        end
    end
    Core.platform:swap()
    Core.collect()
    stats.drawcalls, stats.drawcallsbatched, stats.canvasswitches, stats.shaderswitches = 0, 0, 0, 0
    applyViewport()
    applyScissor()
end

function G.reset()
    G.origin()
    G.setColor(1, 1, 1, 1)
    G.setBackgroundColor(0, 0, 0, 1)
    G.setBlendMode('alpha')
    G.setColorMask()
    G.setScissor()
    G.setStencilTest()
    G.setDepthMode()
    G.setMeshCullMode('none')
    G.setFrontFaceWinding('ccw')
    G.setWireframe(false)
    G.setLineWidth(1)
    G.setShader()
    G.setCanvas()
end

-- Text ----------------------------------------------------------------------------------------------

function G.newFont(...)
    requireReady()
    return FontModule.new(...)
end
function G.newText(font, text)
    requireReady()
    return FontModule.newText(font, text)
end
function G.setFont(font) S.font = font end
function G.getFont()
    if not S.font then
        S.font = FontModule.new(12)
    end
    return S.font
end

-- Colored text is { {r,g,b,a}, 'text', {r,g,b,a}, 'more' }.
local function eachSegment(text, fn)
    if type(text) == 'table' then
        local color
        for i = 1, #text do
            local item = text[i]
            if type(item) == 'table' then
                color = item
            else
                fn(item, color)
            end
        end
    else
        fn(tostring(text), nil)
    end
end

local function emitLine(font, cps, matrix, ox, oy, colorOverride)
    font:_layout(cps, function(texture, gx, gy, w, h, u0, v0, u1, v1)
        local dpi = font._dpi
        addQuad(texture, (ox + gx) / dpi, (oy + gy) / dpi, (ox + gx + w) / dpi, (oy + gy) / dpi,
            (ox + gx) / dpi, (oy + gy + h) / dpi, (ox + gx + w) / dpi, (oy + gy + h) / dpi, u0, v0, u1, v1, matrix)
    end)
end

local function printLines(font, lines, matrix, alignWidth, align)
    local lineAdvance = font._height * font._lineHeight
    for index, line in ipairs(lines) do
        local cps = FontModule.decode(line)
        local offset = 0
        if alignWidth then
            local w = font:getWidth(line) * font._dpi
            if align == 'right' then
                offset = alignWidth * font._dpi - w
            elseif align == 'center' then
                offset = (alignWidth * font._dpi - w) / 2
            end
        end
        emitLine(font, cps, matrix, offset, (index - 1) * lineAdvance)
    end
end

local function splitLines(text)
    local lines = {}
    for line in (text .. '\n'):gmatch('(.-)\n') do
        lines[#lines + 1] = line
    end
    return lines
end

local function printColored(text, matrix, draw)
    local saved = { unpack(S.color) }
    local multiplied = saved
    eachSegment(text, function(segment, color)
        if color then
            S.color = { color[1] * multiplied[1], color[2] * multiplied[2], color[3] * multiplied[3], (color[4] or 1) * multiplied[4] }
        else
            S.color = saved
        end
        draw(segment)
    end)
    S.color = saved
end

function G.print(text, x, y, angle, sx, sy, ox, oy, kx, ky)
    requireReady()
    local font = G.getFont()
    local matrix = composed(x, y, angle, sx, sy, ox, oy, kx, ky)
    -- continuing colored segments on the same line advance horizontally
    local cursor = 0
    local function draw(segment)
        local lines = splitLines(segment)
        local m = matrix
        if cursor ~= 0 then
            m = { matrix[1], matrix[2], matrix[3], matrix[4], matrix[1] * cursor + matrix[5], matrix[2] * cursor + matrix[6] }
        end
        printLines(font, lines, m)
        if #lines == 1 then
            cursor = cursor + font:getWidth(lines[1])
        else
            cursor = font:getWidth(lines[#lines])
        end
    end
    if type(text) == 'table' then
        printColored(text, matrix, draw)
    else
        draw(tostring(text))
    end
end

function G.printf(text, x, y, limit, align, angle, sx, sy, ox, oy, kx, ky)
    requireReady()
    local font = G.getFont()
    local matrix = composed(x, y, angle, sx, sy, ox, oy, kx, ky)
    local _, lines = font:getWrap(text, limit)
    local plainText = FontModule.plain(text)
    if type(text) == 'table' then
        printColored(text, matrix, function() end)
        -- colors apply per wrapped text run; use the first color for the whole paragraph
        local first
        for _, item in ipairs(text) do
            if type(item) == 'table' then first = item break end
        end
        local saved = { unpack(S.color) }
        if first then
            S.color = { first[1] * saved[1], first[2] * saved[2], first[3] * saved[3], (first[4] or 1) * saved[4] }
        end
        printLines(font, lines, matrix, limit, align or 'left')
        S.color = saved
    else
        printLines(font, lines, matrix, limit, align or 'left')
    end
end

-- The window module reports every setMode; the first one creates the GL state.
local katsa = require('source.katsa')
local Window = require('source.katsa.core.window')
Window.onModeSet(function()
    if katsa.platform then
        G.setup(katsa.platform)
    end
end)
if Window.isOpen() and katsa.platform then
    G.setup(katsa.platform)
end

return G
