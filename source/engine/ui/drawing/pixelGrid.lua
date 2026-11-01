local PixelGrid = {}

-- Snap the label origin in physical target pixels, leaving authored layout and
-- pointer rectangles intact. Rotated/sheared labels keep their authored transform.
function PixelGrid.snap(g, x, y)
    local ox, oy = g.transformPoint(0, 0)
    local xx, xy = g.transformPoint(1, 0)
    local yx, yy = g.transformPoint(0, 1)
    if math.abs(xy - oy) > 0.00001 or math.abs(yx - ox) > 0.00001 then
        return x, y
    end
    local canvas = g.getCanvas()
    local density = canvas and canvas:getDPIScale() or g.getDPIScale()
    local px, py = g.transformPoint(x, y)
    return g.inverseTransformPoint(
        math.floor(px * density + 0.5) / density,
        math.floor(py * density + 0.5) / density
    )
end

return PixelGrid
