-- Gamepad input for the scene: buttons feed the named actions, the left stick walks and the right
-- stick looks. The first connected pad drives the scene; others can read their own state through
-- katsa.gamepad. Installed on Input like the other input responsibilities.
local Gamepads = {}

local DEADZONE = 0.2 -- stick travel ignored around the centre (radial, rescaled outside)
local LOOK_SPEED = 600 -- look pixels per second at full right-stick deflection

-- Radial deadzone: the stick vector below the zone reads zero, above it rescales to 0..1.
function Gamepads.stick(x, y)
    local length = math.sqrt(x * x + y * y)
    if length <= DEADZONE then
        return 0, 0
    end
    local scale = (length - DEADZONE) / (1 - DEADZONE) / length
    return x * scale, y * scale
end

function Gamepads.install(Input)
    function Input:gamepadpressed(_, button)
        self.map:setEventStrength('pad:' .. button, 1)
        self.actions:gamepadpressed(button)
    end

    function Input:gamepadreleased(_, button)
        self.map:setEventStrength('pad:' .. button, 0)
        self.actions:gamepadreleased(button)
    end

    -- Feeds the axes some action listens to (`axis:` events) and publishes the map's edges. Runs
    -- first in Input:update, so gameplay sees this frame's presses and axis values.
    function Input:updateMap()
        local map, pad = self.map, katsa.gamepad.first()
        for axis in pairs(map.axes) do
            map:setAxisValue(axis, pad and pad:getAxis(axis) or 0)
        end
        map:update()
    end

    -- Returns the walk contribution (right, forward) of the left stick and queues right-stick
    -- look. Stick up is negative in the pad's axes; forward is positive here.
    function Input:updateGamepads(dt)
        local pad = katsa.gamepad.first()
        if not pad then
            return 0, 0
        end
        local rx, ry = Gamepads.stick(pad:getAxis('rightx'), pad:getAxis('righty'))
        if rx ~= 0 or ry ~= 0 then
            self.actions:look(rx * LOOK_SPEED * dt, ry * LOOK_SPEED * dt)
        end
        local lx, ly = Gamepads.stick(pad:getAxis('leftx'), pad:getAxis('lefty'))
        return lx, -ly
    end
end

return Gamepads
