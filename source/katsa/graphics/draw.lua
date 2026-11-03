-- graphics.draw and instanced drawing.

local Mesh = require('source.katsa.graphics.mesh')
local State = require('source.katsa.graphics.state')
local Batch = require('source.katsa.graphics.batch')
local Canvas = require('source.katsa.graphics.canvas')
local Quad = require('source.katsa.graphics.quad')
local S, stats = State.S, State.stats
local G = State.G
local M = {}

local function drawTexture(texture, quad, matrix)
    local dpi = texture._dpi
    if quad then
        local u0, v0 = quad.x / quad.sw, quad.y / quad.sh
        local u1, v1 = (quad.x + quad.w) / quad.sw, (quad.y + quad.h) / quad.sh
        local w, h = quad.w / dpi, quad.h / dpi
        Batch.addQuad(texture, 0, 0, w, 0, 0, h, w, h, u0, v0, u1, v1, matrix)
    else
        local w, h = texture._pw / dpi, texture._ph / dpi
        Batch.addQuad(texture, 0, 0, w, 0, 0, h, w, h, 0, 0, 1, 1, matrix)
    end
end

local function drawMesh(mesh, matrix, instances)
    State.flush()
    local texture = mesh._texture
    local shader = Batch.prepareDraw(texture, matrix, true)
    mesh:_bindAttributes(shader)
    mesh:_draw(instances)
    stats.drawcalls = stats.drawcalls + 1
    Canvas.markTargetsDirty()
end

function G.draw(drawable, ...)
    State.requireReady()
    -- No argument table: this runs for every drawable of every frame.
    local quad, first = nil, ...
    local matrix
    if type(first) == 'table' and getmetatable(first) == Quad.QuadMethods then
        quad = first
        matrix = Batch.composed(select(2, ...))
    else
        matrix = Batch.composed(...)
    end
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
    State.requireReady()
    local args = { ... }
    local matrix = Batch.composed(unpack(args, 1, 9))
    drawMesh(mesh, matrix, count)
end

-- Exposed for text and sprite batches: draws a textured quad with an explicit local->screen matrix.
function G._drawQuadRaw(texture, w, h, u0, v0, u1, v1, matrix)
    Batch.addQuad(texture, 0, 0, w, 0, 0, h, w, h, u0, v0, u1, v1, matrix)
end

function G._currentTransform()
    return S.transform
end

function G._composed(...)
    return Batch.composed(...)
end

M.drawTexture = drawTexture

return M
