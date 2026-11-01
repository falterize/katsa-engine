local readValue = require('source.engine.math.managedValue').read

local zeroAnchor = { 0, 0 }
local Layout = {}

function Layout.resolve(value, w, h, mode, x, y)
    if not value then
        return x, y
    end
    value = readValue(value)
    assert(#value == 4, 'UDim2 requires {scaleX, offsetX, scaleY, offsetY}')
    mode = mode or 'XY'
    assert(mode == 'XY' or mode == 'XX' or mode == 'YY', 'relativeTo must be XY, XX or YY')
    local sx, sy = mode == 'YY' and h or w, mode == 'XX' and w or h
    for i = 1, 4 do
        local component = value[i]
        assert(
            type(component) == 'number'
                and component == component
                and math.abs(component) < math.huge,
            'Invalid UDim2 component'
        )
    end
    return sx * value[1] + value[2], sy * value[3] + value[4]
end

function Layout.rect(node, w, h)
    local nw, nh = Layout.resolve(
        node.size,
        w,
        h,
        node.sizeRelativeTo or node.relativeTo,
        node.width,
        node.height
    )
    local x, y = Layout.resolve(
        node.position,
        w,
        h,
        node.positionRelativeTo or node.relativeTo,
        node.x,
        node.y
    )
    node._layoutCollapsed = nw < 0 or nh < 0
    node.layoutStatus = node._layoutCollapsed
            and 'Collapsed: parent is smaller than authored padding'
        or 'Resolved'
    nw, nh = math.max(0, nw), math.max(0, nh)
    local a = readValue(node.anchorPoint or zeroAnchor)
    return x - nw * a[1], y - nh * a[2], nw, nh
end

return Layout
