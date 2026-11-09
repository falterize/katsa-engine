-- Gamepads: the katsa.gamepad object API over a fake platform, stick deadzone and action bindings.
local Tests = {}

local function fakePlatform()
    local platform = { ids = { 7 }, down = {}, axes = {}, rumbles = {} }
    function platform:gamepadIds()
        return self.ids
    end
    function platform:gamepadConnected(id)
        return id == 7
    end
    function platform:gamepadName()
        return 'Fake Pad'
    end
    function platform:gamepadPlayerIndex()
        return 1
    end
    function platform:gamepadDown(_, button)
        return self.down[button] == true
    end
    function platform:gamepadAxis(_, axis)
        return self.axes[axis] or 0
    end
    function platform:gamepadRumble(_, low, high, seconds, triggers)
        self.rumbles[#self.rumbles + 1] = { low, high, seconds, triggers }
        return true
    end
    function platform:gamepadHasSensor(_, kind)
        return kind == 'gyro'
    end
    function platform:gamepadSetSensor()
        return true
    end
    function platform:gamepadSensor()
        return 0.1, 0.2, 0.3
    end
    return platform
end

function Tests.run(tester)
    local Gamepad = dofile('source/katsa/core/gamepad.lua')
    local Gamepads = dofile('source/engine/input/gamepads.lua')
    local Actions = dofile('source/engine/input/actions.lua')
    local platform = fakePlatform()
    Gamepad.setPlatform(platform)
    local pad = Gamepad.first()
    tester:check(pad and pad:getName() == 'Fake Pad' and Gamepad.getCount() == 1, 'pad is listed')
    platform.down.a = true
    tester:check(pad:isDown('b', 'a') and not pad:isDown('x'), 'isDown accepts several buttons')
    pad:setVibration(0.5)
    local rumble = platform.rumbles[1]
    tester:check(rumble[1] == 0.5 and rumble[2] == 0.5 and rumble[3] == 0.5, 'vibration defaults')
    tester:check(pad:hasSensor('gyro') and select(3, pad:getSensor('gyro')) == 0.3, 'gyro readings')
    local x, y = Gamepads.stick(0.1, 0.1)
    tester:check(x == 0 and y == 0, 'the stick deadzone reads zero')
    x = Gamepads.stick(1, 0)
    tester:check(math.abs(x - 1) < 1e-6, 'full deflection reads one')
    local actions = Actions.new()
    actions:gamepadpressed('a')
    tester:check(actions.pressed.Jump == true, 'a pad button triggers its bound action')
    actions.pressed.Jump = nil
    actions:gamepadpressed('a')
    tester:check(actions.pressed.Jump == nil, 'a held button does not retrigger')
    actions:gamepadreleased('a')
    actions:gamepadpressed('a')
    tester:check(actions.pressed.Jump == true, 'a new press triggers again')
    Gamepad.setPlatform({})
    tester:check(Gamepad.getCount() == 0 and Gamepad.first() == nil, 'no support reads as no pads')
end

return Tests
