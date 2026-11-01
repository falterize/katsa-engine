local ScrollBar = {}

function ScrollBar.geometry(node, horizontal)
    local key = horizontal and '_horizontalGeometry' or '_verticalGeometry'
    local out = node[key] or {}
    node[key] = out
    local window = horizontal and node._windowWidth or node._windowHeight
    local total = node.absoluteCanvasSize[horizontal and 1 or 2]
    local position = horizontal and node.scrollX or node.scrollY
    local thickness = node.scrollBarThickness
    local track = math.max(1, window - 12)
    out.length = math.min(track, math.max(16, track * window / math.max(1, total)))
    out.travel = track - out.length
    out.maximum = math.max(0, total - window)
    out.start = (horizontal and node._x + node._windowX or node._y) + 6
    local offset = out.travel * position / math.max(1, out.maximum)
    out.x = horizontal and out.start + offset
        or node.verticalScrollBarPosition == 'Left' and node._x + 2
        or node._x + node._width - thickness - 2
    out.y = horizontal and node._y + node._height - thickness - 2 or out.start + offset
    out.width, out.height =
        horizontal and out.length or thickness, horizontal and thickness or out.length
    out.trackX, out.trackY = horizontal and out.start or out.x, horizontal and out.y or out.start
    out.trackWidth, out.trackHeight =
        horizontal and track or thickness, horizontal and thickness or track
    return out
end

function ScrollBar.hit(node, x, y)
    if
        not node.scrollingEnabled
        or node.scrollBarThickness <= 0
        or node.scrollBarImageTransparency >= 1
    then
        return
    end
    for index = 1, 2 do
        local horizontal = index == 2
        if horizontal and node._horizontalBar or not horizontal and node._verticalBar then
            local bar = ScrollBar.geometry(node, horizontal)
            if
                x >= bar.trackX
                and x <= bar.trackX + bar.trackWidth
                and y >= bar.trackY
                and y <= bar.trackY + bar.trackHeight
            then
                local position = horizontal and x or y
                local first = horizontal and bar.x or bar.y
                return horizontal and 'X' or 'Y',
                    position >= first and position <= first + bar.length
            end
        end
    end
end

function ScrollBar.move(ui, node, axis, coordinate, grab)
    local horizontal = axis == 'X'
    local bar = ScrollBar.geometry(node, horizontal)
    local fraction = bar.travel > 0 and (coordinate - grab - bar.start) / bar.travel or 0
    local target = math.max(0, math.min(1, fraction)) * bar.maximum
    ui:scrollBy(
        node,
        horizontal and 0 or target - node.scrollY,
        horizontal and target - node.scrollX or 0
    )
end

return ScrollBar
