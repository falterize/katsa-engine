-- Game controllers for the SDL2 platform: connection, buttons, axes, rumble and motion sensors.
--
-- SDL's controller API maps every pad (Xbox, PlayStation, Switch, generic) to one layout, so the
-- engine only sees the names below. A controller is addressed by its instance id: it stays valid
-- until the pad is unplugged and is never reused during a session.
local ffi = require('ffi')

ffi.cdef([[
typedef struct SDL_GameController SDL_GameController;
typedef struct { uint32_t type, timestamp; int32_t which; uint8_t axis, padding1, padding2, padding3; int16_t value; uint16_t padding4; } SDL_ControllerAxisEvent;
typedef struct { uint32_t type, timestamp; int32_t which; uint8_t button, state, padding1, padding2; } SDL_ControllerButtonEvent;
typedef struct { uint32_t type, timestamp; int32_t which; } SDL_ControllerDeviceEvent;
int SDL_InitSubSystem(uint32_t flags);
int SDL_NumJoysticks(void);
int SDL_IsGameController(int index);
SDL_GameController* SDL_GameControllerOpen(int index);
void SDL_GameControllerClose(SDL_GameController* controller);
void* SDL_GameControllerGetJoystick(SDL_GameController* controller);
int32_t SDL_JoystickInstanceID(void* joystick);
const char* SDL_GameControllerName(SDL_GameController* controller);
int SDL_GameControllerGetPlayerIndex(SDL_GameController* controller);
int SDL_GameControllerGetAttached(SDL_GameController* controller);
uint8_t SDL_GameControllerGetButton(SDL_GameController* controller, int button);
int16_t SDL_GameControllerGetAxis(SDL_GameController* controller, int axis);
int SDL_GameControllerRumble(SDL_GameController* controller, uint16_t low, uint16_t high, uint32_t ms);
int SDL_GameControllerRumbleTriggers(SDL_GameController* controller, uint16_t left, uint16_t right, uint32_t ms);
int SDL_GameControllerHasSensor(SDL_GameController* controller, int type);
int SDL_GameControllerSetSensorEnabled(SDL_GameController* controller, int type, int enabled);
int SDL_GameControllerIsSensorEnabled(SDL_GameController* controller, int type);
int SDL_GameControllerGetSensorData(SDL_GameController* controller, int type, float* data, int count);
]])

local INIT_GAMECONTROLLER = 0x2000
local EVENT = { AXIS = 0x650, BUTTONDOWN = 0x651, BUTTONUP = 0x652, ADDED = 0x653, REMOVED = 0x654 }

local BUTTONS = {
    [0] = 'a', 'b', 'x', 'y', 'back', 'guide', 'start', 'leftstick', 'rightstick',
    'leftshoulder', 'rightshoulder', 'dpup', 'dpdown', 'dpleft', 'dpright', 'misc1',
    'paddle1', 'paddle2', 'paddle3', 'paddle4', 'touchpad',
}
local AXES = { [0] = 'leftx', 'lefty', 'rightx', 'righty', 'triggerleft', 'triggerright' }
local SENSORS = { accel = 1, gyro = 2 }

local BUTTON_ID, AXIS_ID = {}, {}
for id, name in pairs(BUTTONS) do
    BUTTON_ID[name] = id
end
for id, name in pairs(AXES) do
    AXIS_ID[name] = id
end

-- A symbol an old SDL2 build lacks (rumble and sensors need 2.0.9 / 2.0.14) reads as an error.
local function optional(sdl, name)
    local ok, fn = pcall(function()
        return sdl[name]
    end)
    return ok and fn or nil
end

return function(Platform)
    -- Called once after SDL_Init. SDL then reports the pads that are already plugged in as
    -- ADDED events, so connection handling lives in one place.
    function Platform:initGamepads()
        self.pads = {}
        self.padOrder = {} -- instance ids, oldest connection first
        if self.sdl.SDL_InitSubSystem(INIT_GAMECONTROLLER) ~= 0 then
            require('source.katsa.core.log').write(
                'warn',
                'Game controllers are unavailable: ' .. ffi.string(self.sdl.SDL_GetError()),
                'input',
                true
            )
            self.padsDisabled = true
        end
    end

    -- The live, ordered id list (do not modify); the first pad is the one scenes follow.
    function Platform:gamepadIds()
        return self.padOrder
    end

    local function pad(self, id)
        return self.pads and self.pads[id]
    end

    -- Turns a controller event into a katsa event, or nil. Raw ids stay inside the platform;
    -- katsa.gamepad wraps them in objects.
    function Platform:translateGamepad(e)
        local t = e.type
        local sdl = self.sdl
        if t == EVENT.ADDED then
            local index = ffi.cast('SDL_ControllerDeviceEvent*', e).which
            if sdl.SDL_IsGameController(index) == 0 then
                return nil
            end
            local controller = sdl.SDL_GameControllerOpen(index)
            if controller == nil then
                return nil
            end
            local id = sdl.SDL_JoystickInstanceID(sdl.SDL_GameControllerGetJoystick(controller))
            self.pads[id] = { handle = controller, id = id }
            self.padOrder[#self.padOrder + 1] = id
            return { 'gamepadadded', id }
        elseif t == EVENT.REMOVED then
            local id = ffi.cast('SDL_ControllerDeviceEvent*', e).which
            local entry = self.pads[id]
            if not entry then
                return nil
            end
            self.pads[id] = nil
            for position, other in ipairs(self.padOrder) do
                if other == id then
                    table.remove(self.padOrder, position)
                    break
                end
            end
            sdl.SDL_GameControllerClose(entry.handle)
            return { 'gamepadremoved', id }
        elseif t == EVENT.BUTTONDOWN or t == EVENT.BUTTONUP then
            local event = ffi.cast('SDL_ControllerButtonEvent*', e)
            local name = BUTTONS[event.button]
            if name and self.pads[event.which] then
                return { t == EVENT.BUTTONDOWN and 'gamepadpressed' or 'gamepadreleased', event.which, name }
            end
        elseif t == EVENT.AXIS then
            local event = ffi.cast('SDL_ControllerAxisEvent*', e)
            local name = AXES[event.axis]
            if name and self.pads[event.which] then
                return { 'gamepadaxis', event.which, name, self:gamepadAxis(event.which, name) }
            end
        end
        return nil
    end

    function Platform:isGamepadEvent(type)
        return type >= EVENT.AXIS and type <= EVENT.REMOVED
    end

    function Platform:gamepadName(id)
        local entry = pad(self, id)
        local name = entry and self.sdl.SDL_GameControllerName(entry.handle)
        return name ~= nil and name ~= false and ffi.string(name) or 'Unknown controller'
    end

    function Platform:gamepadPlayerIndex(id)
        local entry = pad(self, id)
        local index = entry and self.sdl.SDL_GameControllerGetPlayerIndex(entry.handle) or -1
        return index >= 0 and index + 1 or nil
    end

    function Platform:gamepadConnected(id)
        return pad(self, id) ~= nil
    end

    function Platform:gamepadDown(id, button)
        local entry, number = pad(self, id), BUTTON_ID[button]
        assert(number, 'Unknown gamepad button: ' .. tostring(button))
        return entry ~= nil and self.sdl.SDL_GameControllerGetButton(entry.handle, number) ~= 0
    end

    -- Sticks read -1..1 (up and left are negative), triggers 0..1.
    function Platform:gamepadAxis(id, axis)
        local entry, number = pad(self, id), AXIS_ID[axis]
        assert(number, 'Unknown gamepad axis: ' .. tostring(axis))
        if not entry then
            return 0
        end
        local value = self.sdl.SDL_GameControllerGetAxis(entry.handle, number)
        return math.max(-1, value / 32767)
    end

    -- Motors run `seconds` (a new call replaces the old one); strengths are 0..1. Returns false
    -- when the pad or the SDL build has no rumble.
    function Platform:gamepadRumble(id, low, high, seconds, triggers)
        local entry = pad(self, id)
        local rumble = optional(
            self.sdl,
            triggers and 'SDL_GameControllerRumbleTriggers' or 'SDL_GameControllerRumble'
        )
        if not entry or not rumble then
            return false
        end
        local function strength(value)
            return math.floor(math.max(0, math.min(1, value)) * 65535 + 0.5)
        end
        local ms = math.max(0, math.floor(seconds * 1000 + 0.5))
        return rumble(entry.handle, strength(low), strength(high), ms) == 0
    end

    function Platform:gamepadHasSensor(id, kind)
        local entry, number = pad(self, id), SENSORS[kind]
        assert(number, 'Unknown sensor: ' .. tostring(kind) .. ' (use "gyro" or "accel")')
        local has = optional(self.sdl, 'SDL_GameControllerHasSensor')
        return entry ~= nil and has ~= nil and has(entry.handle, number) ~= 0
    end

    function Platform:gamepadSetSensor(id, kind, enabled)
        local entry, number = pad(self, id), SENSORS[kind]
        assert(number, 'Unknown sensor: ' .. tostring(kind) .. ' (use "gyro" or "accel")')
        local set = optional(self.sdl, 'SDL_GameControllerSetSensorEnabled')
        return entry ~= nil and set ~= nil and set(entry.handle, number, enabled and 1 or 0) == 0
    end

    local sample = ffi.new('float[3]')

    -- Gyro: angular speed in rad/s around x, y, z. Accel: m/s^2 including gravity.
    -- Returns nil until the sensor is enabled.
    function Platform:gamepadSensor(id, kind)
        local entry, number = pad(self, id), SENSORS[kind]
        local read = optional(self.sdl, 'SDL_GameControllerGetSensorData')
        if not entry or not number or not read then
            return nil
        end
        if read(entry.handle, number, sample, 3) ~= 0 then
            return nil
        end
        return sample[0], sample[1], sample[2]
    end
end
