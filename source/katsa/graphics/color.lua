-- Color, blend mode and color mask.

local State = require('source.katsa.graphics.state')
local S = State.S
local G = State.G
local gl, E
State.onSetup(function(core)
    gl, E = core.gl, core.enum
end)
local M = {}

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

function G.getColor()
    local c = S.color return c[1], c[2], c[3], c[4]
end

function G.setBackgroundColor(r, g, b, a)
    r, g, b, a = colorArgs(r, g, b, a)
    S.background = { r, g, b, a }
end

function G.getBackgroundColor()
    local c = S.background
    return c[1], c[2], c[3], c[4]
end

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

local blendApplied, alphaApplied

function G.setBlendMode(mode, alphamode)
    State.requireReady()
    blendFactors = blendFactors or blendTable()
    assert(blendFactors[mode], 'Invalid blend mode: ' .. tostring(mode))
    alphamode = alphamode or 'alphamultiply'
    -- Re-selecting the active mode must not break the batch (push('all')/pop() do it constantly).
    if blendApplied == mode and alphaApplied == alphamode then
        return
    end
    State.flush()
    S.blend, S.alphaMode = mode, alphamode
    blendApplied, alphaApplied = mode, alphamode
    applyBlend()
end

function G.getBlendMode()
    return S.blend, S.alphaMode
end

local function applyColorMask()
    local m = S.colorMask
    gl.glColorMask(m[1], m[2], m[3], m[4])
end

local maskR, maskG, maskB, maskA

function G.setColorMask(r, g, b, a)
    if r == nil then
        r, g, b, a = true, true, true, true
    end
    r, g, b, a = not not r, not not g, not not b, not not a
    if maskR == r and maskG == g and maskB == b and maskA == a then
        return
    end
    State.flush()
    S.colorMask = { r, g, b, a }
    maskR, maskG, maskB, maskA = r, g, b, a
    applyColorMask()
end

function G.getColorMask()
    local m = S.colorMask
    return m[1], m[2], m[3], m[4]
end

M.colorArgs = colorArgs
M.applyColorMask = applyColorMask

return M
