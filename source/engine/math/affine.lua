local Array = require('source.engine.math.array')
-- Row-major affine matrices with column vectors; positive scales only.
local Affine = {}

function Affine.copy(matrix, out)
    out = out or {}
    for i = 1, 16 do
        out[i] = matrix[i]
    end
    return out
end

function Affine.validate(matrix)
    assert(Array.is(matrix), 'Transform must be an affine matrix')
    for i = 1, 16 do
        local v = matrix[i]
        assert(
            type(v) == 'number' and v == v and math.abs(v) < math.huge,
            'Transform entries must be finite'
        )
    end
    assert(
        math.abs(matrix[13]) + math.abs(matrix[14]) + math.abs(matrix[15]) < 1e-8
            and math.abs(matrix[16] - 1) < 1e-8,
        'Perspective transforms are not supported'
    )
end

function Affine.inverse(m, out)
    Affine.validate(m)
    local a, b, c, d, e, f, g, h, i = m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11]
    local det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    assert(math.abs(det) > 1e-12, 'Transform is singular')
    out = out or {}
    out[1], out[2], out[3] = (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det
    out[5], out[6], out[7] = (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det
    out[9], out[10], out[11] = (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det
    out[4] = -(out[1] * m[4] + out[2] * m[8] + out[3] * m[12])
    out[8] = -(out[5] * m[4] + out[6] * m[8] + out[7] * m[12])
    out[12] = -(out[9] * m[4] + out[10] * m[8] + out[11] * m[12])
    out[13], out[14], out[15], out[16] = 0, 0, 0, 1
    return out
end

function Affine.decompose(m)
    Affine.validate(m)
    local sx = math.sqrt(m[1] ^ 2 + m[5] ^ 2 + m[9] ^ 2)
    local sy = math.sqrt(m[2] ^ 2 + m[6] ^ 2 + m[10] ^ 2)
    local sz = math.sqrt(m[3] ^ 2 + m[7] ^ 2 + m[11] ^ 2)
    assert(math.min(sx, sy, sz) > 1e-6, 'Zero or near-zero scale is unsupported')
    local a, b, c, d, e, f, g, h, i =
        m[1] / sx,
        m[2] / sy,
        m[3] / sz,
        m[5] / sx,
        m[6] / sy,
        m[7] / sz,
        m[9] / sx,
        m[10] / sy,
        m[11] / sz
    assert(
        math.abs(a * b + d * e + g * h) < 1e-5
            and math.abs(a * c + d * f + g * i) < 1e-5
            and math.abs(b * c + e * f + h * i) < 1e-5,
        'Transform contains shear; this operation requires a TRS pose'
    )
    assert(
        a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g) > 0,
        'Mirrored transforms are unsupported'
    )
    local y = math.asin(math.max(-1, math.min(1, g)))
    local x, z
    if math.abs(math.cos(y)) > 1e-6 then
        x, z = math.atan2(h, i), math.atan2(d, a)
    else
        x, z = 0, math.atan2(-b, e)
    end
    return { m[4], m[8], m[12] }, { math.deg(x), math.deg(y), math.deg(z) }, { sx, sy, sz }
end

function Affine.rotation(m, out)
    local sx = math.sqrt(m[1] ^ 2 + m[5] ^ 2 + m[9] ^ 2)
    local sy = math.sqrt(m[2] ^ 2 + m[6] ^ 2 + m[10] ^ 2)
    local sz = math.sqrt(m[3] ^ 2 + m[7] ^ 2 + m[11] ^ 2)
    assert(math.min(sx, sy, sz) > 1e-6, 'Zero or near-zero scale is unsupported')
    local a, b, c, d, e, f, g, h, i =
        m[1] / sx,
        m[2] / sy,
        m[3] / sz,
        m[5] / sx,
        m[6] / sy,
        m[7] / sz,
        m[9] / sx,
        m[10] / sy,
        m[11] / sz
    assert(
        math.abs(a * b + d * e + g * h) < 1e-5
            and math.abs(a * c + d * f + g * i) < 1e-5
            and math.abs(b * c + e * f + h * i) < 1e-5,
        'Transform contains shear; this operation requires a TRS pose'
    )
    assert(
        a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g) > 0,
        'Mirrored transforms are unsupported'
    )
    out = out or {}
    out[1], out[2], out[3], out[4] = a, b, c, m[4]
    out[5], out[6], out[7], out[8] = d, e, f, m[8]
    out[9], out[10], out[11], out[12] = g, h, i, m[12]
    out[13], out[14], out[15], out[16] = 0, 0, 0, 1
    return out
end

function Affine.euler(matrix, out)
    local y = math.asin(math.max(-1, math.min(1, matrix[9])))
    local x, z
    if math.abs(math.cos(y)) > 1e-6 then
        x, z = math.atan2(matrix[10], matrix[11]), math.atan2(matrix[5], matrix[1])
    else
        x, z = 0, math.atan2(-matrix[2], matrix[6])
    end
    out = out or {}
    out[1], out[2], out[3] = math.deg(x), math.deg(y), math.deg(z)
    return out
end
Affine.withoutScale = Affine.rotation

function Affine.parentMatrix(node, parent, out)
    while parent and not parent.getWorldMatrix do
        parent = parent.parent
    end
    if not parent then
        return nil
    end
    local matrix = parent:getWorldMatrix()
    if node.inheritScale == false then
        matrix = Affine.withoutScale(matrix, out)
    end
    return matrix, parent
end

return Affine
