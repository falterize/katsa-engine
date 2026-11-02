-- Scissor, stencil, depth, culling, line and point state.

local Texture = require('source.katsa.graphics.texture')
local State = require('source.katsa.graphics.state')
local Color = require('source.katsa.graphics.color')
local S, target = State.S, State.target
local G = State.G
local gl, E
State.onSetup(function(core)
    gl, E = core.gl, core.enum
end)
local M = {}

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
    gl.glScissor(math.floor(x + 0.5), math.floor(glY + 0.5), math.max(0, math.floor(w + 0.5)),
        math.max(0, math.floor(h + 0.5)))
end

-- push('all')/pop() and nested UI drawing re-select the state that is already active thousands of
-- times a frame; re-applying it would only break the batch and issue redundant GL calls. The
-- scissor depends on the render target, so the target's geometry is part of what was applied.
local scissorX, scissorY, scissorW, scissorH
local scissorPW, scissorPH, scissorDPI, scissorCanvas

function G.setScissor(x, y, w, h)
    State.requireReady()
    if x == nil then
        if S.scissor == nil and scissorX == false and scissorPW == target.pw and scissorPH == target.ph
            and scissorDPI == target.dpi and scissorCanvas == target.isCanvas then
            return
        end
        State.flush()
        S.scissor = nil
        scissorX = false
    else
        assert(w >= 0 and h >= 0, 'Scissor width and height must be non-negative')
        if scissorX == x and scissorY == y and scissorW == w and scissorH == h
            and scissorPW == target.pw and scissorPH == target.ph and scissorDPI == target.dpi
            and scissorCanvas == target.isCanvas and S.scissor
            and S.scissor[1] == x and S.scissor[2] == y and S.scissor[3] == w
            and S.scissor[4] == h then
            return
        end
        State.flush()
        S.scissor = { x, y, w, h }
        scissorX, scissorY, scissorW, scissorH = x, y, w, h
    end
    scissorPW, scissorPH, scissorDPI, scissorCanvas = target.pw, target.ph, target.dpi, target.isCanvas
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
-- The stencil test reads "pixel passes when stencil <compare> value", GL tests "value <func>
-- stencil".
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

local stencilCompare, stencilValue

function G.setStencilTest(compare, value)
    State.requireReady()
    compareFunctions = compareFunctions or compareTable()
    if compare ~= nil then
        assert(compareFunctions[compare], 'Invalid compare mode: ' .. tostring(compare))
        value = value or 0
    end
    if stencilCompare == (compare or false) and stencilValue == value and (compare ~= nil) == (S.stencilTest ~= nil) then
        return
    end
    State.flush()
    if compare == nil then
        S.stencilTest = nil
    else
        S.stencilTest = { compare, value }
    end
    stencilCompare, stencilValue = compare or false, value
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
    State.requireReady()
    State.flush()
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
    State.flush()
    Color.applyColorMask()
    applyStencilTest()
    stencilCompare = nil
end

local depthCompareApplied, depthWriteApplied

function G.setDepthMode(compare, write)
    State.requireReady()
    compareFunctions = compareFunctions or compareTable()
    compare, write = compare or 'always', write and true or false
    assert(compareFunctions[compare], 'Invalid compare mode: ' .. tostring(compare))
    if depthCompareApplied == compare and depthWriteApplied == write then
        return
    end
    State.flush()
    S.depthCompare, S.depthWrite = compare, write
    depthCompareApplied, depthWriteApplied = compare, write
    gl.glEnable(E.DEPTH_TEST)
    gl.glDepthFunc(compareFunctions[S.depthCompare])
    gl.glDepthMask(S.depthWrite)
end

function G.getDepthMode()
    return S.depthCompare, S.depthWrite
end

local cullApplied

local function applyCull()
    cullApplied = S.cull .. S.winding .. tostring(target.isCanvas)
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
    State.requireReady()
    assert(mode == 'none' or mode == 'back' or mode == 'front',
        'Invalid cull mode: ' .. tostring(mode))
    if S.cull == mode and cullApplied == mode .. S.winding .. tostring(target.isCanvas) then
        return
    end
    State.flush()
    S.cull = mode
    applyCull()
end

function G.getMeshCullMode()
    return S.cull
end

function G.setFrontFaceWinding(winding)
    assert(winding == 'cw' or winding == 'ccw', 'Invalid winding: ' .. tostring(winding))
    if S.winding == winding and cullApplied == S.cull .. winding .. tostring(target.isCanvas) then
        return
    end
    State.flush()
    S.winding = winding
    applyCull()
end

function G.getFrontFaceWinding()
    return S.winding
end

local wireframeApplied

function G.setWireframe(enabled)
    enabled = not not enabled
    if wireframeApplied == enabled then
        return
    end
    State.flush()
    wireframeApplied = enabled
    S.wireframe = enabled
    if gl and gl.glPolygonMode then
        gl.glPolygonMode(0x408, S.wireframe and 0x1B01 or 0x1B02)
    end
end

function G.isWireframe()
    return S.wireframe
end

function G.setLineWidth(width)
    S.lineWidth = width
end

function G.getLineWidth()
    return S.lineWidth
end

function G.setLineJoin(join)
    S.lineJoin = join
end

function G.getLineJoin()
    return S.lineJoin
end

function G.setLineStyle(style)
    S.lineStyle = style
end

function G.getLineStyle()
    return S.lineStyle
end

function G.setPointSize(size)
    S.pointSize = size
end

function G.getPointSize()
    return S.pointSize
end

function G.setDefaultFilter(min, mag, anisotropy)
    Texture.defaultFilter.min, Texture.defaultFilter.mag = min, mag or min
    Texture.defaultFilter.anisotropy = anisotropy or 1
end

function G.getDefaultFilter()
    local f = Texture.defaultFilter
    return f.min, f.mag, f.anisotropy
end

M.applyScissor = applyScissor
M.applyStencilTest = applyStencilTest
M.applyCull = applyCull

return M
