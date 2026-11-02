-- The StareShooter orbit camera, shared by the on-foot player and the car. The look, zoom and
-- wall-avoidance maths are the source's (scripts/cameras/orbit.lua); only these are added for a
-- driving game: the view eases behind the car once the player stops dragging, and the field of
-- view widens smoothly with speed.
local Orbit = {}
Orbit.__index = Orbit

Orbit.settings = {
    sensitivity = 0.25, -- degrees per input unit
    zoomSpeed = 1, -- meters per wheel notch
    minDistance = 0, -- 0 is first person, as in the source
    maxDistance = 100,
    fov = 75,
    walkDistance = 5.5,
    carDistance = 10,
    walkPitch = -12,
    carPitch = -14,
    recenterDelay = 1.2, -- seconds without input before the car view swings behind
    recenterRate = 2.2,
    speedFov = 14, -- extra degrees of field of view at top speed
    speedFovFrom = 12, -- m/s where the widening starts
    speedFovTo = 40, -- m/s where it is complete
    fovRate = 3, -- how quickly the field of view follows (1/s)
}

function Orbit.new(scene, camera)
    camera.near, camera.far, camera.drawDistance = 0.05, 4000, 4000
    local self = setmetatable({
        scene = scene,
        camera = camera,
        settings = Orbit.settings,
        yaw = 0,
        pitch = Orbit.settings.walkPitch,
        distance = Orbit.settings.walkDistance,
        fov = Orbit.settings.fov,
        idle = 0,
        start = {},
        finish = {},
        hit = {},
        mode = 'walk',
    }, Orbit)
    -- Only static level geometry pulls the camera in; bodies and cars never do.
    self.filter = function(other)
        return other.canCollide and other.type == 'Static'
    end
    self:applyFov()
    return self
end

function Orbit:applyFov()
    local camera = self.camera
    camera.focalLength = camera.referenceHeight / (2 * math.tan(math.rad(self.fov) / 2))
end

-- dx/dy are pointer movements: moving right turns the view right, moving up looks up.
function Orbit:look(x, y)
    self.yaw = (self.yaw + x * self.settings.sensitivity) % 360
    self.pitch = math.max(-90, math.min(90, self.pitch - y * self.settings.sensitivity))
    self.idle = 0
end

function Orbit:zoom(amount)
    local s = self.settings
    self.distance = math.max(s.minDistance, math.min(s.maxDistance, self.distance - amount * s.zoomSpeed))
end

-- Switches between the two resting distances/pitches without a jump in yaw.
function Orbit:setMode(mode, heading)
    if mode == self.mode then
        return
    end
    self.mode = mode
    local s = self.settings
    self.distance = mode == 'car' and s.carDistance or s.walkDistance
    self.pitch = mode == 'car' and s.carPitch or s.walkPitch
    if mode == 'car' and heading then
        self.yaw = heading % 360
    end
    self.idle = 0
end

local function shortest(from, to)
    return (to - from + 180) % 360 - 180
end

-- Driving: swing behind the car after a pause, and widen the view with speed.
function Orbit:follow(dt, heading, speed)
    local s = self.settings
    self.idle = self.idle + dt
    speed = math.abs(speed or 0)
    if heading and self.idle > s.recenterDelay and speed > 2 then
        local ease = 1 - math.exp(-dt * s.recenterRate)
        self.yaw = (self.yaw + shortest(self.yaw, heading) * ease) % 360
        self.pitch = self.pitch + (s.carPitch - self.pitch) * ease
    end
    local boost = math.max(0, math.min(1, (speed - s.speedFovFrom) / (s.speedFovTo - s.speedFovFrom)))
    self:setFov(s.fov + s.speedFov * boost, dt)
end

function Orbit:setFov(target, dt)
    local k = dt and (1 - math.exp(-dt * self.settings.fovRate)) or 1
    local fov = self.fov + (target - self.fov) * k
    if math.abs(fov - self.fov) > 1e-4 then
        self.fov = fov
        self:applyFov()
    end
end

-- px, py, pz: the pivot (the subject's chest). Interpolated poses make the pivot smooth already.
function Orbit:update(px, py, pz)
    if self.scene.freeDebugCamera then
        return
    end
    local camera = self.camera
    local pitch, yaw = math.rad(self.pitch), math.rad(self.yaw)
    local x, y, z =
        math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)
    local offset = 0.5 - self.distance
    local start, finish = self.start, self.finish
    start[1], start[2], start[3] = px, py, pz
    finish[1], finish[2], finish[3] = px + x * offset, py + y * offset, pz + z * offset
    local physics = self.scene.physics
    if self.distance > 0.5 and physics then
        local hit = physics:raycast(start, finish, self.filter, self.hit)
        if hit then
            for i = 1, 3 do
                finish[i] = hit.position[i] + hit.normal[i] * 0.05
            end
        end
    end
    local position = camera.position
    position[1], position[2], position[3] = finish[1], finish[2], finish[3]
    camera.position = position
    -- A tiny pitch clamp keeps a valid camera basis at the source's +/-90 limits.
    camera.rotation = { math.max(-89.99, math.min(89.99, self.pitch)), self.yaw, 0 }
end

return Orbit
