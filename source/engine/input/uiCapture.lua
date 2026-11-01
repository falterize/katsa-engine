local Canvas = require('source.engine.ui.layout.scrollCanvas')
local Capture = {}

-- Gesture origins use host-local UI coordinates. lastX/Y retain raw pointer positions
-- for screen/world host adapters; projection happens before gesture dispatch.
function Capture.new(node, x, y, billboard, pointerX, pointerY)
    local scroll = node
    while scroll and scroll ~= node.ui and scroll ~= node.ui.owner and not scroll.scrollable do
        scroll = scroll.parent
    end
    if scroll == node.ui or scroll == node.ui.owner then
        scroll = nil
    end
    return {
        kind = billboard and 'billboard' or 'ui',
        node = node,
        billboard = billboard,
        scroll = scroll,
        startX = x,
        startY = y,
        lastX = pointerX or x,
        lastY = pointerY or y,
        pendingPress = scroll
            and node ~= scroll
            and not node:isA('Slider')
            and not node.dragCapture,
    }
end

function Capture.point(capture, x, y)
    if capture.billboard then
        return capture.billboard:localPoint(x, y)
    end
    return x, y
end

function Capture.press(c, x, y, id)
    if not c.pendingPress then
        c.node.ui:pointer(c.node, 'press', x, y, id)
    end
end

function Capture.move(c, x, y, id)
    if c.scroll and not c.node.dragCapture and c.node ~= c.scroll then
        local horizontal, vertical = Canvas.axes(c.scroll)
        local movedX, movedY = x - c.startX, y - c.startY
        if c.node:isA('Slider') then
            horizontal = false
            vertical = vertical and math.abs(movedY) > math.abs(movedX)
        end
        local threshold = 8 * c.node.ui.scale
        local dragX = horizontal
            and math.abs(movedX) > threshold
            and (vertical or math.abs(movedX) > math.abs(movedY))
        local dragY = vertical
            and math.abs(movedY) > threshold
            and (horizontal or math.abs(movedY) > math.abs(movedX))
        if
            c.pendingPress
            and not (dragX or dragY)
            and math.max(math.abs(movedX), math.abs(movedY)) > threshold
        then
            c.suppressedPress = true
        end
        if dragX or dragY then
            if not c.pendingPress then
                c.node.ui:pointer(c.node, 'cancel', x, y, id)
            end
            c.pendingPress = false
            c.node = c.scroll
            c.node.ui:pointer(c.node, 'press', c.startX, c.startY, id)
        end
    end
    if c.pendingPress then
        return
    end
    if x then
        c.node.ui:pointer(c.node, 'move', x, y, id)
    end
end

function Capture.release(c, x, y, id)
    if c.pendingPress then
        c.pendingPress = false
        if c.suppressedPress then
            c.node.ui:pointer(c.node, 'cancel', x, y, id)
            return
        end
        c.node.ui:pointer(c.node, 'press', x, y, id)
    end
    c.node.ui:pointer(c.node, 'release', x, y, id)
end

return Capture
