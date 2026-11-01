-- Transform stack and matrix helpers.

local State = require('source.katsa.graphics.state')
local S = State.S
local G = State.G

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

function G.translate(x, y)
    multiply(1, 0, 0, 1, x, y)
end

function G.scale(sx, sy)
    multiply(sx, 0, 0, sy or sx, 0, 0)
end

function G.rotate(angle)
    local c, s = math.cos(angle), math.sin(angle)
    multiply(c, s, -s, c, 0, 0)
end

function G.shear(kx, ky)
    multiply(1, ky, kx, 1, 0, 0)
end

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

local function isPlainTable(value)
    return type(value) == 'table' and getmetatable(value) == nil
end

-- Plain tables (color, scissor...) are copied; objects such as fonts and shaders are shared.
local function snapshot()
    local copy = {}
    for key, value in pairs(S) do
        if key ~= 'stack' then
            if isPlainTable(value) and key ~= 'canvases' and key ~= 'canvasOptions' then
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
