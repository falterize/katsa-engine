-- SSAO reads depth only at texel centres, so the normal never depends on rounding at a border.
local Module = {}

local function read(path)
    local text = assert(katsa.filesystem.read(path))
    return text
end

function Module.run(self)
    local chunk = read('assets/shaders/engine/chunks/depth.glsl')
    local trace = read('assets/shaders/engine/post/ssao.glsl')
    local blur = read('assets/shaders/engine/post/ssaoBlur.glsl')
    self:check(chunk:find('snapToDepthTexel', 1, true) ~= nil, 'The depth chunk snaps to texel centres')
    self:check(
        trace:find('snapToDepthTexel(targetUV)', 1, true) ~= nil
            and trace:find('quv = snapToDepthTexel(quv)', 1, true) ~= nil,
        'The occlusion trace snaps the pixel and every tap'
    )
    self:check(blur:find('snapToDepthTexel(at)', 1, true) ~= nil, 'The blur snaps its taps')
    -- A half-resolution pixel centre lies on a full-resolution texel border; the snap must give one
    -- texel centre whatever the rounding noise.
    local size = 1280
    local function snap(uv)
        return (math.floor(uv * size) + 0.5) / size
    end
    local border = 641 / size
    self:check(
        snap(border) == snap(border + 1e-9) and snap(border - 1e-9) ~= snap(border),
        'A border resolves to a texel centre, not to either neighbour at random'
    )
end

return Module
