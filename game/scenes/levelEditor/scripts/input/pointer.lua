-- The editor's one pointer: the mouse, or the first finger of a touch screen acting as a mouse
-- (press = left button, a long press = right click). Everything that polls the pointer reads it
-- here instead of katsa.mouse, so the whole editor works with touch.
local Pointer = {
    id = nil, -- the finger that acts as the mouse
    x = 0,
    y = 0,
    down = false,
    rightFrames = 0, -- a right click lasts two frames so edge polling sees it
    held = 0, -- seconds the finger has been down without moving
    moved = 0,
    seen = false, -- a touch has happened since start (shows the touch controls in Auto mode)
    LONG_PRESS = 0.5,
    SLOP = 12,
}

function Pointer.getX()
    if Pointer.id or Pointer.rightFrames > 0 then
        return Pointer.x
    end
    return katsa.mouse.getX()
end

function Pointer.getY()
    if Pointer.id or Pointer.rightFrames > 0 then
        return Pointer.y
    end
    return katsa.mouse.getY()
end

function Pointer.isDown(button)
    if Pointer.id or Pointer.rightFrames > 0 then
        if button == 1 then
            return Pointer.down
        elseif button == 2 then
            return Pointer.rightFrames > 0
        end
        return false
    end
    return katsa.mouse.isDown(button)
end

function Pointer.begin(id, x, y)
    Pointer.id, Pointer.x, Pointer.y = id, x, y
    Pointer.down, Pointer.held, Pointer.moved, Pointer.fired = true, 0, 0, false
    Pointer.seen = true
end

function Pointer.move(x, y, dx, dy)
    Pointer.x, Pointer.y = x, y
    Pointer.moved = Pointer.moved + math.abs(dx or 0) + math.abs(dy or 0)
end

function Pointer.finish()
    Pointer.id, Pointer.down = nil, false
end

-- Per frame. Returns true once when a long press fires (the caller opens a context menu).
function Pointer.update(dt)
    if Pointer.rightFrames > 0 then
        Pointer.rightFrames = Pointer.rightFrames - 1
    end
    if Pointer.id and Pointer.down and not Pointer.fired then
        Pointer.held = Pointer.held + dt
        if Pointer.moved > Pointer.SLOP then
            Pointer.fired = true -- a drag is never a long press
        elseif Pointer.held >= Pointer.LONG_PRESS then
            Pointer.fired = true
            Pointer.rightFrames = 2
            return true
        end
    end
    return false
end

function Pointer.reset()
    Pointer.id, Pointer.down, Pointer.rightFrames = nil, false, 0
end

return Pointer
