-- katsa.gamepad: game controllers.
--
--   for _, pad in ipairs(katsa.gamepad.getGamepads()) do print(pad:getName()) end
--   pad:isDown('a'), pad:getAxis('leftx')            -- sticks -1..1 (up/left negative), triggers 0..1
--   pad:setVibration(0.5, 1, 0.3)                    -- low motor, high motor, seconds
--   pad:setSensorEnabled('gyro', true); pad:getSensor('gyro')   -- rad/s around x, y, z
--
-- Buttons: a b x y back guide start leftstick rightstick leftshoulder rightshoulder dpup dpdown
-- dpleft dpright misc1 paddle1..paddle4 touchpad. Axes: leftx lefty rightx righty triggerleft
-- triggerright. Events (katsa.gamepadadded/removed/pressed/released/axis) pass the Gamepad object.
local Gamepad = {}
local Pad = {}
Pad.__index = Pad

local platform
local pads = {} -- instance id -> Pad, kept for the lifetime of the connection

function Gamepad.setPlatform(p)
    platform = p
end

local function supported()
    return platform ~= nil and platform.gamepadIds ~= nil
end

-- The Pad object of an instance id (created on first use). Used by the event bridge.
function Gamepad.get(id)
    if not supported() or not platform:gamepadConnected(id) then
        pads[id] = nil
        return nil
    end
    local pad = pads[id]
    if not pad then
        pad = setmetatable({ id = id }, Pad)
        pads[id] = pad
    end
    return pad
end

-- Forgets a removed pad; the object stays valid but reports isConnected() == false.
function Gamepad.forget(id)
    local pad = pads[id]
    pads[id] = nil
    return pad
end

function Gamepad.getGamepads()
    local list = {}
    if supported() then
        for _, id in ipairs(platform:gamepadIds()) do
            list[#list + 1] = Gamepad.get(id)
        end
    end
    return list
end

-- The pad that was connected first and still is, or nil. Allocation-free, for per-frame use.
function Gamepad.first()
    local id = supported() and platform:gamepadIds()[1]
    return id and Gamepad.get(id) or nil
end

function Gamepad.getCount()
    return supported() and #platform:gamepadIds() or 0
end

function Pad:getID()
    return self.id
end

function Pad:isConnected()
    return supported() and platform:gamepadConnected(self.id)
end

function Pad:getName()
    return platform:gamepadName(self.id)
end

-- 1-based player slot (the lit LED on many pads), or nil when the system gives none.
function Pad:getPlayerIndex()
    return platform:gamepadPlayerIndex(self.id)
end

function Pad:isDown(...)
    for i = 1, select('#', ...) do
        if platform:gamepadDown(self.id, (select(i, ...))) then
            return true
        end
    end
    return false
end

function Pad:getAxis(axis)
    return platform:gamepadAxis(self.id, axis)
end

-- Both motors run for `duration` seconds (default 0.5); strengths 0..1. Returns false when this
-- pad cannot vibrate. A new call replaces the running one; setVibration(0, 0) stops it.
function Pad:setVibration(low, high, duration)
    return platform:gamepadRumble(self.id, low or 0, high or low or 0, duration or 0.5, false)
end

-- Impulse triggers (Xbox One / Series). Same arguments as setVibration.
function Pad:setTriggerVibration(left, right, duration)
    return platform:gamepadRumble(self.id, left or 0, right or left or 0, duration or 0.5, true)
end

-- kind: 'gyro' or 'accel'.
function Pad:hasSensor(kind)
    return platform:gamepadHasSensor(self.id, kind)
end

function Pad:setSensorEnabled(kind, enabled)
    return platform:gamepadSetSensor(self.id, kind, enabled)
end

-- x, y, z of the last reading, or nil while the sensor is off or missing.
function Pad:getSensor(kind)
    return platform:gamepadSensor(self.id, kind)
end

return Gamepad
