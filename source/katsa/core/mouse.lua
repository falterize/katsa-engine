-- katsa.mouse: pointer state (love.mouse compatible subset).
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
    return true
end

return Mouse
