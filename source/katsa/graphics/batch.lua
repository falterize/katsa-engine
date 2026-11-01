-- Vertex batching, built-in uniforms and quad emission.

local ffi = require('ffi')
local Core = require('source.katsa.graphics.core')
local State = require('source.katsa.graphics.state')
local Canvas = require('source.katsa.graphics.canvas')
local S, batch, stats, target = State.S, State.batch, State.stats, State.target
local G = State.G
local gl, E
State.onSetup(function(core)
    gl, E = core.gl, core.enum
end)
local M = {}

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
    return S.shader or State.defaultShader
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
    Canvas.markTargetsDirty()
end

function G.flushBatch()
    State.flush()
end

local function setBatchTexture(texture)
    if batch.texture ~= texture then
        State.flush()
        batch.texture = texture
    end
end

local function reserve(count, texture)
    if batch.count + count > State.VERTEX_CAPACITY then
        State.flush()
    end
    if batch.texture ~= texture then
        State.flush()
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
    local function tx(x, y)
        return a1 * x + c1 * y + e1, b1 * x + d1 * y + f1
    end
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

M.prepareDraw = prepareDraw
M.setBatchTexture = setBatchTexture
M.reserve = reserve
M.packColor = packColor
M.push = push
M.addQuad = addQuad
M.composed = composed

return M
