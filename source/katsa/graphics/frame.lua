-- Window metrics, setup, present, screenshots and reset.

local ffi = require('ffi')
local Core = require('source.katsa.graphics.core')
local Texture = require('source.katsa.graphics.texture')
local Shader = require('source.katsa.graphics.shader')
local State = require('source.katsa.graphics.state')
local RenderState = require('source.katsa.graphics.renderState')
local S = State.S
local batch = State.batch
local stats = State.stats
local counters = State.counters
local target = State.target
local G = State.G
local gl, E
State.onSetup(function(core)
    gl, E = core.gl, core.enum
end)
local M = {}

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
    if State.ready then
        applyViewport()
        return true
    end
    local ok, message = Core.init(platform)
    if not ok then
        error('Cannot initialise graphics: ' .. tostring(message))
    end
    State.runSetup(Core)
    local vao = ffi.new('GLuint[1]')
    gl.glGenVertexArrays(1, vao)
    gl.glBindVertexArray(vao[0])
    local id = ffi.new('GLuint[1]')
    gl.glGenBuffers(1, id)
    batch.vbo = id[0]
    batch.vertices = ffi.new('KatsaVertex[?]', State.VERTEX_CAPACITY)
    -- 1x1 white texture used when nothing is bound.
    local white = ffi.new('uint8_t[4]', 255, 255, 255, 255)
    State.whiteTexture = Texture.newImage(require('source.katsa.image').newImageData(1, 1, 'rgba8',
        string.char(255, 255, 255, 255)))
    Core.defaultTextureId = State.whiteTexture._res.texture
    Core.defaultTextureObject = State.whiteTexture
    State.ready = true
    State.defaultShader = Shader.new([[
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

local function window()
    return require('source.katsa.core.window')
end

function G.getWidth()
    return (window().getDimensions())
end

function G.getHeight()
    local _, h = window().getDimensions()
    return h
end

function G.getDimensions()
    return
    window().getDimensions()
end

function G.getPixelWidth()
    return target.pw
end

function G.getPixelHeight()
    return target.ph
end

function G.getPixelDimensions()
    return target.pw, target.ph
end

function G.getDPIScale()
    return
    windowDPI()
end

function G.isActive()
    return State.ready and Core.platform:isVisible()
end

function G.isCreated()
    return State.ready
end

function G.getRendererInfo()
    State.requireReady()
    return Core.rendererInfo()
end

function G.getSystemLimits()
    State.requireReady()
    local l = Core.limits
    return {
        pointsize = 64, texturesize = l.texturesize, multicanvas = l.multicanvas,
        canvasmsaa = l.canvasmsaa,
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
    State.screenshots[#State.screenshots + 1] = target
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
    State.requireReady()
    State.flush()
    assert(not S.canvases, 'present cannot be called while a Canvas is active.')
    if #State.screenshots > 0 then
        local pending = State.screenshots
        State.screenshots = {}
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
    RenderState.applyScissor()
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

-- The window module reports every setMode; the first one creates the GL state. Called once all
-- category modules have registered their setup hooks.
function M.attach()
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
end

M.applyViewport = applyViewport

return M
