-- Diagnostic (not pass/fail): screenshots of the Duke 69 in multiplayerCars, clean and dented.
--   KATSA_SHOT=tmp/cars xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.6.shots
-- PNGs land in ~/.local/share/Katsa/katsa-engine/tmp/cars (look at them with the Read tool).
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

function Tests:shot(name)
    katsa.graphics.captureScreenshot((os.getenv('KATSA_SHOT') or 'tmp/cars') .. '/' .. name .. '.png')
end

-- Turns the chase camera: distance in metres, yaw in degrees, pitch in degrees.
function Tests:view(distance, yaw, pitch)
    local orbit = self.session.orbit
    orbit.distance, orbit.yaw, orbit.pitch, orbit.idle = distance, yaw, pitch, -1000
end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
        self.host:load()
        self.session = self.host.demo
        self.session:host('Tester', 47930 + math.floor(os.clock() * 100) % 9)
    end
    local host, session = self.host, self.session
    host:update(1 / 60, 1 / 60)
    host:draw()
    if frame == 201 then
        session:changeCar()
    elseif frame == 230 then
        self:view(7, 35, -12)
    elseif frame == 236 then
        self:shot('front')
        self:view(7, 215, -12)
    elseif frame == 242 then
        self:shot('rear')
        self:view(7, 90, -8)
    elseif frame == 248 then
        self:shot('side')
        local _, car = session.client:getCar()
        -- A hard front-left hit and a side swipe.
        car.dents:addImpact({ x = -0.5, y = 0.7, z = 2.5, nx = 0.3, ny = 0, nz = -0.95, speed = 24 })
        car.dents:addImpact({ x = 0.95, y = 0.7, z = 0.3, nx = -1, ny = 0, nz = 0, speed = 16 })
        session.views[session.client:getCar()]:markDirty()
        self:view(7, 35, -12)
    elseif frame == 256 then
        self:shot('dentFront')
        self:view(7, 120, -12)
    elseif frame == 262 then
        self:shot('dentSide')
        katsa.event.quit()
    end
end

return Tests
