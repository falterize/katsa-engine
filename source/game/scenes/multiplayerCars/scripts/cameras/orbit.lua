-- The StareShooter orbit camera, shared by the on-foot player and the car: yaw/pitch around a pivot,
-- zoom by distance and a raycast that pulls the camera in front of walls. While driving, the view
-- also eases behind the car once the player stops dragging.
local Orbit = {}
Orbit.__index = Orbit

Orbit.settings = {
    sensitivity = 0.25, -- degrees per input unit (the source's)
    zoomSpeed = 1.5,
    minDistance = 2.5,
    maxDistance = 40,
    fov = 75,
    walkDistance = 5.5,
    carDistance = 10,
    walkPitch = -12,
    carPitch = -14,
    minPitch = -75,
    maxPitch = 60,
    recenterDelay = 1.2, -- seconds without input before the car view swings behind
    recenterRate = 2.2,
}

function Orbit.new(scene, camera)
    camera.near, camera.far, camera.drawDistance = 0.05, 4000, 4000
    camera.focalLength = camera.referenceHeight
        / (2 * math.tan(math.rad(Orbit.settings.fov) / 2))
    local self = setmetatable({
        scene = scene,
        camera = camera,
        settings = Orbit.settings,
        yaw = 0,
        pitch = Orbit.settings.walkPitch,
        distance = Orbit.settings.walkDistance,
        idle = 0,
        pivot = {},
        start = {},
        finish = {},
        hit = {},
        mode = 'walk',
    }, Orbit)
    self.filter = function(other)
        return other.canCollide and other.type == 'Static'
    end
    return self
end

-- dx/dy are pointer drags in the scene's Look units (dragging right turns the view left).
function Orbit:look(dx, dy)
    local s = self.settings
    self.yaw = (self.yaw - dx * 0.4) % 360
    self.pitch = math.max(s.minPitch, math.min(s.maxPitch, self.pitch - dy * 0.3))
    self.idle = 0
end

function Orbit:zoom(amount)
    local s = self.settings
    self.distance = math.max(s.minDistance, math.min(s.maxDistance, self.distance - amount * s.zoomSpeed))
end

-- Switches between the two distances (and the matching resting pitch) without a jump in yaw.
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
    self.snap = true
end

local function shortest(from, to)
    return (to - from + 180) % 360 - 180
end

-- px, py, pz: the pivot (the subject's chest); heading/speed only matter for the car.
function Orbit:update(dt, px, py, pz, heading, speed)
    local s, camera, pivot = self.settings, self.camera, self.pivot
    self.idle = self.idle + dt
    if self.mode == 'car' and heading and self.idle > s.recenterDelay and (speed or 0) > 2 then
        local ease = 1 - math.exp(-dt * s.recenterRate)
        self.yaw = (self.yaw + shortest(self.yaw, heading) * ease) % 360
        self.pitch = self.pitch + (s.carPitch - self.pitch) * ease
    end
    -- The pivot is smoothed, the view angles are not, so dragging stays immediate while the physics
    -- steps of the subject never reach the screen as shake.
    if not pivot[1] or self.snap or (pivot[1] - px) ^ 2 + (pivot[3] - pz) ^ 2 > 400 then
        pivot[1], pivot[2], pivot[3] = px, py, pz
        self.snap = nil
    else
        local k = 1 - math.exp(-dt * 16)
        pivot[1] = pivot[1] + (px - pivot[1]) * k
        pivot[2] = pivot[2] + (py - pivot[2]) * k
        pivot[3] = pivot[3] + (pz - pivot[3]) * k
    end
    local pitch, yaw = math.rad(self.pitch), math.rad(self.yaw)
    local x, y, z =
        math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)
    local start, finish = self.start, self.finish
    start[1], start[2], start[3] = pivot[1], pivot[2], pivot[3]
    finish[1], finish[2], finish[3] =
        start[1] - x * self.distance, start[2] - y * self.distance, start[3] - z * self.distance
    local physics = self.scene.physics
    if physics then
        local hit = physics:raycast(start, finish, self.filter, self.hit)
        if hit then
            for i = 1, 3 do
                finish[i] = hit.position[i] + hit.normal[i] * 0.15
            end
        end
    end
    local position = camera.position
    position[1], position[2], position[3] = finish[1], finish[2], finish[3]
    camera.position = position
    camera.rotation = { math.max(-89.99, math.min(89.99, self.pitch)), self.yaw, 0 }
end

return Orbit
