-- graphics.clear.

local ffi = require('ffi')
local bit = require('bit')
local State = require('source.katsa.graphics.state')
local Canvas = require('source.katsa.graphics.canvas')
local Color = require('source.katsa.graphics.color')
local RenderState = require('source.katsa.graphics.renderState')
local S = State.S
local G = State.G
local gl, E
State.onSetup(function(core)
    gl, E = core.gl, core.enum
end)

function G.clear(...)
    State.requireReady()
    State.flush()
    local args = { ... }
    local colors, rest = {}, 1
    -- clear(color, stencil, depth): `false` skips the color of that target. One entry per active
    -- color canvas, so clear(false, false, 1) is "keep color, keep stencil, clear depth to 1".
    local limit = math.max(1, S.canvases and #S.canvases or 1)
    if type(args[1]) == 'table' or args[1] == false then
        local count = 0
        while count < limit and (type(args[rest]) == 'table' or args[rest] == false) do
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
    -- Like glClear, clearing is limited to the scissor box (shadow atlas tiles rely on it).
    local hadScissor = false
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
    Color.applyColorMask()
    RenderState.applyStencilTest()
    if hadScissor then
        RenderState.applyScissor()
    end
    Canvas.markTargetsDirty()
end
