-- Fly camera driven only by InputMap actions. Movement and look work while `editorLook` (the
-- right mouse button) is held; the wheel changes the speed in that state. The mouse delta comes
-- from the scene's Input subclass, which calls `look`.
local FlyCamera = {}
FlyCamera.__index = FlyCamera

function FlyCamera.new(camera, map, settings)
    return setmetatable({
        camera = camera,
        map = map,
        speed = settings.flySpeed,
        fast = settings.flyFastFactor,
        min = settings.flySpeedMin,
        max = settings.flySpeedMax,
        sensitivity = settings.sensitivity,
    }, FlyCamera)
end

function FlyCamera:isLooking()
    return self.map:isDown('editorLook')
end

-- Mouse motion in pixels while looking.
function FlyCamera:look(dx, dy)
    local camera = self.camera
    camera:look(dx, dy, self.sensitivity)
    camera.rotation[1] = math.max(-89, math.min(89, camera.rotation[1]))
end

local LOOK_RATE = 500 -- pixels per second at full stick deflection (scaled by the sensitivity)

-- Touch controls drive the camera without the right mouse button: `input` is
-- { moveX, moveY, vertical, lookX, lookY, fast, lookSpeed } or nil.
function FlyCamera:setTouch(input)
    self.touch = input
end

function FlyCamera:updateTouch(dt)
    local touch = self.touch
    if not touch then
        return
    end
    if touch.lookX ~= 0 or touch.lookY ~= 0 then
        self:look(touch.lookX * LOOK_RATE * touch.lookSpeed * dt, -touch.lookY * LOOK_RATE * touch.lookSpeed * dt)
    end
    if touch.moveX ~= 0 or touch.moveY ~= 0 or touch.vertical ~= 0 then
        local factor = touch.fast and self.fast or 1
        self.camera:move(touch.moveX, touch.moveY, touch.vertical, dt, self.speed * factor)
    end
end

function FlyCamera:update(dt)
    self:updateTouch(dt)
    if not self:isLooking() then
        return
    end
    local map = self.map
    if map:justPressed('editorSpeedUp') then
        self.speed = math.min(self.max, self.speed * 1.25)
    elseif map:justPressed('editorSpeedDown') then
        self.speed = math.max(self.min, self.speed / 1.25)
    end
    local x = map:getAxis('editorLeft', 'editorRight')
    local z = map:getAxis('editorBack', 'editorForward')
    local y = map:getAxis('editorDown', 'editorUp')
    if x ~= 0 or y ~= 0 or z ~= 0 then
        local factor = map:isDown('editorFast') and self.fast or 1
        self.camera:move(x, z, y, dt, self.speed * factor)
    end
end

-- Moves the camera back along its view direction until a sphere of `radius` around `center`
-- fits the vertical field of view.
function FlyCamera:frame(center, radius)
    local camera = self.camera
    local fov = math.rad(camera.fov or 70)
    local distance = math.max(radius, 0.25) / math.sin(fov / 2) * 1.1
    camera:update(camera.width or 640, camera.height or 360)
    local forward = camera.forward
    camera.position = {
        center[1] - forward[1] * distance,
        center[2] - forward[2] * distance,
        center[3] - forward[3] * distance,
    }
end

return FlyCamera
