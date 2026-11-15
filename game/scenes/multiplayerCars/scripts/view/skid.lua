-- Tire smoke and dark skid marks of one car. The driver's client writes `drift` (0..1: how hard
-- the rear tires slide or lock under the handbrake) into the replicated model, so every machine
-- draws the same smoke and marks from it.
--
--   * Smoke: one ParticleEmitter3D per rear wheel, in world space so the cloud stays behind.
--   * Marks: while a rear wheel is sliding, a flat dual-edge Trail3D follows two world-space edge
--     nodes that the view places under the tire's contact patch. When the slide ends the edges
--     stop, the trail ages out on its own and the segment is destroyed afterwards.
local Skid = {}
Skid.__index = Skid

local ON, OFF = 0.18, 0.08 -- drift thresholds (hysteresis keeps a mark from flickering)
local LIFETIME = 9 -- seconds a mark stays on the ground
local HALF_WIDTH = 0.13

local function ramp(a, b, c)
    return { { time = 0, value = a }, { time = 0.5, value = b }, { time = 1, value = c } }
end

function Skid.new(world, root, model, netId)
    local self = setmetatable({
        world = world,
        netId = netId,
        smoke = {},
        marks = {}, -- [wheel index 3|4] = active segment
        fading = {}, -- finished segments waiting to age out
        counter = 0,
        axes = { forward = {}, right = {} },
    }, Skid)
    self.wheels = model.wheels
    for index = 3, 4 do
        local offset = model.wheels[index]
        local ok, emitter = pcall(function()
            return world:create('ParticleEmitter3D', {
                name = 'Smoke' .. netId .. '_' .. index,
                position = { offset[1], 0.15, offset[2] },
                rate = 0,
                lifetime = { 0.9, 1.6 },
                speed = { 0.4, 1.4 },
                startSize = { 0.7, 1.1 },
                spread = 60,
                drag = 1.2,
                gravityScale = -0.04,
                simulationSpace = 'World',
                lightInfluence = 0,
                castShadow = false,
                maxParticles = 160,
                lifetimeBindings = {
                    size = ramp(0.6, 1.8, 2.8),
                    transparency = ramp(0.55, 0.75, 1),
                    color = ramp({ 0.82, 0.82, 0.84 }, { 0.66, 0.66, 0.68 }, { 0.5, 0.5, 0.52 }),
                },
            }, root)
        end)
        self.smoke[index] = ok and emitter or nil
    end
    return self
end

local function edge(world, name, x, y, z)
    return world:create('Node3D', { name = name, position = { x, y, z } })
end

-- Starts a mark segment for rear wheel `index`.
function Skid:begin(index, x, y, z)
    self.counter = self.counter + 1
    local name = ('Skid%d_%d_%d'):format(self.netId, index, self.counter)
    local world = self.world
    local left, right = edge(world, name .. 'L', x, y, z), edge(world, name .. 'R', x, y, z)
    local ok, trail = pcall(function()
        return world:create('Trail3D', {
            name = name,
            trailMode = 'Dual',
            attachment0 = left,
            attachment1 = right,
            faceCamera = false,
            lifetime = LIFETIME,
            minLength = 0.25,
            breakDistance = 6,
            color = { 0.02, 0.02, 0.02 },
            lightInfluence = 0,
            castShadow = false,
            receiveShadow = false,
            zOffset = 0.2,
            rampBindings = {
                transparency = { { time = 0, value = 0.25 }, { time = 0.7, value = 0.35 }, { time = 1, value = 1 } },
            },
        })
    end)
    if not ok then
        left:destroy()
        right:destroy()
        return nil
    end
    return { trail = trail, left = left, right = right, age = 0 }
end

local function retire(self, segment)
    segment.age = 0
    self.fading[#self.fading + 1] = segment
end

local function dispose(segment)
    segment.trail:destroy()
    segment.left:destroy()
    segment.right:destroy()
end

-- origin: the model origin (on the ground below the chassis); up: the car's up axis.
function Skid:update(dt, car, origin, up)
    local drift = car.drift or 0
    local forward, right = self.axes.forward, self.axes.right
    -- forward = right x up, with right from the heading so the roll is already inside `up`.
    local h = math.rad(car.rheading or car.heading)
    right[1], right[2], right[3] = math.cos(h), 0, -math.sin(h)
    forward[1] = right[2] * up[3] - right[3] * up[2]
    forward[2] = right[3] * up[1] - right[1] * up[3]
    forward[3] = right[1] * up[2] - right[2] * up[1]
    for index = 3, 4 do
        local offset = self.wheels[index]
        local lost = math.floor((car.detached or 0) / 2 ^ (index - 1)) % 2 == 1
        local sliding = not lost and drift > (self.marks[index] and OFF or ON)
        local emitter = self.smoke[index]
        if emitter then
            emitter.rate = sliding and math.min(70, 14 + drift * 80) or 0
        end
        local x = origin[1] + right[1] * offset[1] + forward[1] * offset[2]
        local y = origin[2] + right[2] * offset[1] + forward[2] * offset[2] + 0.1
        local z = origin[3] + right[3] * offset[1] + forward[3] * offset[2]
        local segment = self.marks[index]
        if sliding then
            if not segment then
                segment = self:begin(index, x, y, z)
                self.marks[index] = segment
            end
            if segment then
                -- The edges lie across the tire, along the car's right axis.
                segment.left.position = { x - right[1] * HALF_WIDTH, y, z - right[3] * HALF_WIDTH }
                segment.right.position = { x + right[1] * HALF_WIDTH, y, z + right[3] * HALF_WIDTH }
            end
        elseif segment then
            retire(self, segment)
            self.marks[index] = nil
        end
    end
    for index = #self.fading, 1, -1 do
        local segment = self.fading[index]
        segment.age = segment.age + dt
        if segment.age > LIFETIME + 0.5 then
            dispose(segment)
            table.remove(self.fading, index)
        end
    end
end

function Skid:destroy()
    for _, segment in pairs(self.marks) do
        dispose(segment)
    end
    for _, segment in ipairs(self.fading) do
        dispose(segment)
    end
    self.marks, self.fading = {}, {}
    for _, emitter in pairs(self.smoke) do
        emitter:destroy()
    end
end

return Skid
