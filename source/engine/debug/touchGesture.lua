-- Detects "N fingers down at once" (default three) from pointer events. The mouse never counts, so
-- desktop clicks cannot trigger it. Used to open the console on a phone, which has no F1 key.
local Gesture = {}
Gesture.__index = Gesture

function Gesture.new(fingers)
    return setmetatable({ fingers = fingers or 3, down = {}, count = 0, fired = false }, Gesture)
end

-- True once per gesture: when the Nth finger lands.
function Gesture:press(id)
    if id == 'mouse' then
        return false
    end
    if not self.down[id] then
        self.down[id] = true
        self.count = self.count + 1
    end
    if self.count >= self.fingers and not self.fired then
        self.fired = true
        return true
    end
    return false
end

function Gesture:release(id)
    if self.down[id] then
        self.down[id] = nil
        self.count = self.count - 1
    end
    if self.count == 0 then
        self.fired = false
    end
end

function Gesture:reset()
    self.down, self.count, self.fired = {}, 0, false
end

return Gesture
