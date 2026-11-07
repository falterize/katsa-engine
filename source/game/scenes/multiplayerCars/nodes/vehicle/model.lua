-- Arcade car model. One `step(input, dt)` function advances all state; because it is
-- deterministic, a server and a predicting client that feed it the same inputs agree.
--
-- Coordinates: x/z on the ground plane, y up. `heading` is yaw in degrees: heading 0 faces +z.
-- Input: { throttle = -1..1 (negative brakes/reverses), steer = -1..1 (right positive), nitro = bool }
local Vehicle = {}
Vehicle.__index = Vehicle

local DEFAULTS = {
    wheelBase = 2.935, -- front to rear axle, as in the Duke 69 model
    frontAxle = 1.635, -- front axle ahead of the origin (the model centre is 0.17 m behind the middle)
    rearAxle = 1.3, -- rear axle behind the origin
    hubHeight = 0.315, -- wheel centre above the ground at rest (the tire radius)
    track = 1.56,
    radius = 1.0, -- collision circle radius (two circles, front and rear)
    circleOffset = 1.0,
    maxSpeed = 32,
    reverseSpeed = 8,
    acceleration = 24,
    brake = 42,
    drag = 0.12,
    rolling = 2.5,
    maxSteer = 32,
    steerSpeedFalloff = 14,
    grip = 5,
    nitroMultiplier = 1.8,
    nitroSpeedMultiplier = 1.5,
    nitroDrain = 0.25,
    rideHeight = 0.85, -- chassis center above the ground at rest
    springStiffness = 90,
    springDamping = 9,
    seats = 4,
}

-- Wheel layout in car space (x right, z forward): front-left, front-right, rear-left, rear-right.
function Vehicle.wheelOffsets(config)
    local half = config.track / 2
    local front = config.frontAxle or config.wheelBase / 2
    local rear = config.rearAxle or config.wheelBase / 2
    return { { -half, front }, { half, front }, { -half, -rear }, { half, -rear } }
end

-- config overrides DEFAULTS; ground(x, z) returns the terrain height (default flat 0).
function Vehicle.new(config, ground)
    local settings = {}
    for key, value in pairs(DEFAULTS) do
        settings[key] = value
    end
    for key, value in pairs(config or {}) do
        settings[key] = value
    end
    local self = setmetatable({
        config = settings,
        ground = ground or function()
            return 0
        end,
        x = 0,
        y = settings.rideHeight,
        z = 0,
        heading = 0,
        speed = 0,
        slide = 0,
        drift = 0, -- 0..1 rear-tire slide / lock, drives smoke and skid marks
        steerAngle = 0,
        nitro = 1,
        spring = { 0, 0, 0, 0 },
        springVelocity = { 0, 0, 0, 0 },
        seats = {},
        wheels = Vehicle.wheelOffsets(settings),
    }, Vehicle)
    return self
end

function Vehicle:setPose(x, z, heading)
    self.x, self.z, self.heading = x, z, heading
    self.y = self.ground(x, z) + self.config.rideHeight
end

-- Unit forward and right vectors on the ground plane.
function Vehicle:axes()
    local radians = math.rad(self.heading)
    local s, c = math.sin(radians), math.cos(radians)
    return s, c, c, -s -- forward x, z; right x, z
end

-- World position of a point given in car space (x right, z forward).
function Vehicle:toWorld(localX, localZ)
    local fx, fz, rx, rz = self:axes()
    return self.x + rx * localX + fx * localZ, self.z + rz * localX + fz * localZ
end

function Vehicle:toLocal(worldX, worldZ)
    local fx, fz, rx, rz = self:axes()
    local dx, dz = worldX - self.x, worldZ - self.z
    return dx * rx + dz * rz, dx * fx + dz * fz
end

local function approach(value, target, rate, dt)
    local step = rate * dt
    if value < target then
        return math.min(target, value + step)
    end
    return math.max(target, value - step)
end

local function drive(self, input, dt)
    local config = self.config
    local throttle = math.max(-1, math.min(1, input.throttle or 0))
    local boosting = input.nitro == true and self.nitro > 0 and throttle > 0
    local top = config.maxSpeed * (boosting and config.nitroSpeedMultiplier or 1)
    if throttle > 0 then
        if self.speed < 0 then
            self.speed = self.speed + config.brake * throttle * dt
        else
            local power = config.acceleration * (boosting and config.nitroMultiplier or 1)
            self.speed = self.speed + power * throttle * dt
        end
    elseif throttle < 0 then
        if self.speed > 0 then
            self.speed = self.speed + config.brake * throttle * dt
        else
            self.speed = self.speed + config.acceleration * 0.6 * throttle * dt
        end
    end
    if boosting then
        self.nitro = math.max(0, self.nitro - config.nitroDrain * dt)
    end
    -- Air drag grows with speed; rolling resistance pulls toward zero when coasting.
    self.speed = self.speed - self.speed * config.drag * dt
    if throttle == 0 then
        self.speed = approach(self.speed, 0, config.rolling, dt)
    end
    self.speed = math.max(-config.reverseSpeed, math.min(top, self.speed))
    return boosting
end

local function steer(self, input, dt)
    local config = self.config
    local limit = config.maxSteer / (1 + math.abs(self.speed) / config.steerSpeedFalloff)
    local target = math.max(-1, math.min(1, input.steer or 0)) * limit
    self.steerAngle = approach(self.steerAngle, target, 180, dt)
    local yawRate = self.speed / config.wheelBase * math.tan(math.rad(self.steerAngle))
    self.heading = (self.heading + math.deg(yawRate) * dt) % 360
    -- Sideways slide builds in corners and decays with tire grip.
    self.slide = self.slide + (-yawRate * self.speed * 0.12 - self.slide * config.grip) * dt
end

local function suspension(self, dt)
    local config = self.config
    local center, count = 0, 0
    local heights = {}
    for index, wheel in ipairs(self.wheels) do
        local wx, wz = self:toWorld(wheel[1], wheel[2])
        heights[index] = self.ground(wx, wz)
        center = center + heights[index]
        count = count + 1
    end
    center = center / count
    local sum = 0
    for index = 1, 4 do
        -- The spring is stretched by how much the terrain under this wheel differs from the
        -- body's mean support height, and pulled back by a damped spring.
        local target = heights[index] - center
        local force = config.springStiffness * (target - self.spring[index])
            - config.springDamping * self.springVelocity[index]
        self.springVelocity[index] = self.springVelocity[index] + force * dt
        self.spring[index] = self.spring[index] + self.springVelocity[index] * dt
        sum = sum + self.spring[index]
    end
    self.y = center + config.rideHeight + sum / 4
end

-- Advances the car by dt seconds. Returns true while nitro is burning.
function Vehicle:step(input, dt)
    input = input or {}
    local boosting = drive(self, input, dt)
    steer(self, input, dt)
    local fx, fz, rx, rz = self:axes()
    self.x = self.x + (fx * self.speed + rx * self.slide) * dt
    self.z = self.z + (fz * self.speed + rz * self.slide) * dt
    suspension(self, dt)
    return boosting
end

-- Body tilt in degrees from the wheel springs (visual only): positive pitch raises the nose.
function Vehicle:tilt()
    local s, config = self.spring, self.config
    local front, rear = (s[1] + s[2]) / 2, (s[3] + s[4]) / 2
    local left, right = (s[1] + s[3]) / 2, (s[2] + s[4]) / 2
    return math.deg(math.atan2(front - rear, config.wheelBase)),
        math.deg(math.atan2(right - left, config.track))
end

function Vehicle:addNitro(amount)
    self.nitro = math.max(0, math.min(1, self.nitro + amount))
end

-- Seats hold player ids. Seat 1 is the driver. Returns the seat index or nil when full.
function Vehicle:sit(playerId)
    for index = 1, self.config.seats do
        if self.seats[index] == playerId then
            return index
        end
    end
    for index = 1, self.config.seats do
        if self.seats[index] == nil then
            self.seats[index] = playerId
            return index
        end
    end
end

function Vehicle:leave(playerId)
    for index = 1, self.config.seats do
        if self.seats[index] == playerId then
            self.seats[index] = nil
            return index
        end
    end
end

function Vehicle:getDriver()
    return self.seats[1]
end

function Vehicle:getOccupants()
    local count = 0
    for index = 1, self.config.seats do
        count = count + (self.seats[index] and 1 or 0)
    end
    return count
end

return Vehicle
