-- Colour and transparency of every visual node (Mesh3D, Decal3D, SurfaceAppearance3D, ribbons).
-- `color` is stored as exactly three channels; an alpha written by older scenes (a fourth
-- channel) is folded into `transparency` once and dropped, so renderers never see it.
local V = require('../core.validate')

local Tint = {}

local function rgb(color)
    return { color[1], color[2], color[3] }
end

-- Fixes up `color` and `transparency` in place. `default` is the class colour (white if omitted).
function Tint.normalize(node, name, default)
    name = name or 'Node'
    local color = node.color or default or { 1, 1, 1 }
    node.transparency = node.transparency or 0
    if color[4] ~= nil then
        node.transparency = 1 - (1 - node.transparency) * color[4]
    end
    node.color = rgb(color)
    V.vector(node.color, name .. '.color', 3)
    V.number(node.transparency, name .. '.transparency', 0, 1)
end

-- Transparency only, for nodes that carry no colour (billboards, spatial UI).
function Tint.normalizeTransparency(node, name)
    node.transparency = node.transparency or 0
    V.number(node.transparency, (name or 'Node') .. '.transparency', 0, 1)
end

-- Drops a legacy fourth channel that was assigned after creation.
function Tint.stripAlpha(node)
    if node.color[4] ~= nil then
        node.color = rgb(node.color)
    end
end

return Tint
