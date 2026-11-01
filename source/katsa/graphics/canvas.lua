-- Canvas targets: framebuffer cache, setCanvas and canvas creation.

local ffi = require('ffi')
local Core = require('source.katsa.graphics.core')
local Texture = require('source.katsa.graphics.texture')
local Mesh = require('source.katsa.graphics.mesh')
local State = require('source.katsa.graphics.state')
local Frame = require('source.katsa.graphics.frame')
local RenderState = require('source.katsa.graphics.renderState')
local S, stats, target = State.S, State.stats, State.target
local G = State.G
local gl, E
State.onSetup(function(core)
    gl, E = core.gl, core.enum
end)
local M = {}

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
    State.requireReady()
    State.flush()
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
            assert(c._pw == first._pw and c._ph == first._ph,
                'All canvases must have the same pixel dimensions')
            assert(c._msaa == first._msaa, 'All canvases must have the same MSAA value')
        end
        assert(#canvases <= Core.limits.multicanvas,
            'This system can\'t simultaneously render to that many canvases')
        local depth = options.depthstencil
        if depth then
            assert(depth._pw == first._pw and depth._ph == first._ph,
                'The depthstencil canvas must match the canvas size')
            assert(depth._msaa == first._msaa,
                'The depthstencil canvas must have the same MSAA value as the color canvas')
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
    Frame.applyViewport()
    RenderState.applyScissor()
    RenderState.applyCull()
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
    State.requireReady()
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
    State.requireReady()
    return Texture.newImage(source, settings)
end

function G.newMesh(...)
    State.requireReady()
    return Mesh.new(...)
end

local formatProbe = {}
function G.getCanvasFormats(readable)
    State.requireReady()
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

M.markTargetsDirty = markTargetsDirty

return M
