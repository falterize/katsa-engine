-- katsa.mouse: pointer state.
local Mouse = {}
local platform

function Mouse.setPlatform(p)
    platform = p
end

function Mouse.getPosition()
    return platform:getMousePosition()
end

function Mouse.getX()
    return (platform:getMousePosition())
end

function Mouse.getY()
    local _, y = platform:getMousePosition()
    return y
end

function Mouse.isDown(...)
    for i = 1, select('#', ...) do
        if platform:isMouseDown((select(i, ...))) then
            return true
        end
    end
    return false
end

function Mouse.setRelativeMode(enabled)
    platform:setRelativeMouse(enabled)
end

function Mouse.getRelativeMode()
    return platform ~= nil and platform:getRelativeMouse()
end

function Mouse.setVisible(visible)
    platform:setCursorVisible(visible)
end

function Mouse.isVisible()
    return platform:isCursorVisible()
end

-- Moves the pointer (window units, like getPosition).
function Mouse.setPosition(x, y)
    platform:setMousePosition(x, y)
end

function Mouse.setX(x)
    platform:setMousePosition(x, select(2, platform:getMousePosition()))
end

function Mouse.setY(y)
    platform:setMousePosition((platform:getMousePosition()), y)
end

-- Confines the pointer to the window.
function Mouse.setGrabbed(grabbed)
    platform:setMouseGrab(grabbed)
end

function Mouse.isGrabbed()
    return platform:getMouseGrab()
end

-- System cursors by name: arrow, ibeam, wait, crosshair, waitarrow, sizenwse, sizenesw, sizewe,
-- sizens, sizeall, no, hand. Returns nil for an unknown name.
function Mouse.getSystemCursor(name)
    return platform:getSystemCursor(name)
end

function Mouse.setCursor(cursor)
    platform:setCursor(cursor or platform:getSystemCursor('arrow'))
end

function Mouse.getCursor()
    return platform.activeCursor
end

function Mouse.isCursorSupported()
    return true
end

return Mouse
