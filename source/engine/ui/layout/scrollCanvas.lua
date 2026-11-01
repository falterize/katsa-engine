local Canvas = {}

local function finite(value, label)
    assert(
        type(value) == 'number' and value == value and math.abs(value) < math.huge,
        'ScrollFrame.' .. label .. ' must be finite'
    )
    return value
end

function Canvas.axes(node)
    local direction = node.scrollingDirection
    assert(
        direction == 'X' or direction == 'Y' or direction == 'XY',
        'ScrollFrame.scrollingDirection must be X, Y or XY'
    )
    return direction ~= 'Y', direction ~= 'X'
end

function Canvas.sync(node)
    local size, position = node.canvasSize, node.canvasPosition
    -- Legacy edits remain live; explicit canvas edits win when both change.
    if node.length ~= node._lastLength and size[4] == node._lastCanvasHeight then
        size[4] = node.length
    end
    if node.scrollX ~= node._lastScrollX and position[1] == node._lastCanvasX then
        position[1] = node.scrollX
    end
    if node.scrollY ~= node._lastScrollY and position[2] == node._lastCanvasY then
        position[2] = node.scrollY
    end
    if node.automaticLength ~= node._lastAutomaticLength then
        node.automaticCanvasSize = node.automaticLength and 'Y' or 'None'
    end
    local automatic = node.automaticCanvasSize
    assert(
        automatic == 'None' or automatic == 'X' or automatic == 'Y' or automatic == 'XY',
        'ScrollFrame.automaticCanvasSize must be None, X, Y or XY'
    )
    for index = 1, 4 do
        finite(size[index], 'canvasSize')
        assert(size[index] >= 0, 'ScrollFrame.canvasSize must be nonnegative')
    end
    finite(position[1], 'canvasPosition')
    finite(position[2], 'canvasPosition')
    local x, y = Canvas.axes(node)
    node.scrollX, node.scrollY = x and position[1] or 0, y and position[2] or 0
    return automatic == 'X' or automatic == 'XY', automatic == 'Y' or automatic == 'XY'
end

local function inset(mode, visible)
    assert(
        mode == 'None' or mode == 'Always' or mode == 'ScrollBar',
        'ScrollFrame scrollbar inset must be None, Always or ScrollBar'
    )
    return mode == 'Always' or mode == 'ScrollBar' and visible
end

function Canvas.window(node)
    local x, y = Canvas.axes(node)
    local size = node.absoluteCanvasSize
    local thickness = finite(node.scrollBarThickness, 'scrollBarThickness')
    assert(thickness >= 0, 'ScrollFrame.scrollBarThickness must be nonnegative')
    local width, height = node._width, node._height
    -- One scrollbar can make the other axis overflow; resolve the coupled insets.
    for _ = 1, 3 do
        node._horizontalBar = node.scrollingEnabled and x and size[1] > width
        node._verticalBar = node.scrollingEnabled and y and size[2] > height
        width = math.max(
            0,
            node._width - (inset(node.verticalScrollBarInset, node._verticalBar) and thickness or 0)
        )
        height = math.max(
            0,
            node._height
                - (inset(node.horizontalScrollBarInset, node._horizontalBar) and thickness or 0)
        )
    end
    local changed = node._windowWidth ~= width or node._windowHeight ~= height
    node._windowWidth, node._windowHeight = width, height
    node._windowX = node.verticalScrollBarPosition == 'Left' and node._width - width or 0
    node.absoluteWindowSize[1], node.absoluteWindowSize[2] = width, height
    return changed
end

function Canvas.clamp(node)
    local x, y = Canvas.axes(node)
    local size = node.absoluteCanvasSize
    local sx = x and math.max(0, math.min(node.scrollX, math.max(0, size[1] - node._windowWidth)))
        or 0
    local sy = y and math.max(0, math.min(node.scrollY, math.max(0, size[2] - node._windowHeight)))
        or 0
    local changed = sx ~= node.scrollX or sy ~= node.scrollY
    node.scrollX, node.scrollY = sx, sy
    node.canvasPosition[1], node.canvasPosition[2] = sx, sy
    node._lastScrollX, node._lastScrollY = sx, sy
    node._lastCanvasX, node._lastCanvasY = sx, sy
    node._lastLength, node._lastCanvasHeight = node.length, node.canvasSize[4]
    node._lastAutomaticLength = node.automaticLength
    return changed
end

return Canvas
