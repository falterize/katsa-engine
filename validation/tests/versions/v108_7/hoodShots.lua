-- Diagnostic (not pass/fail): the Duke 69 hood with a dent, seen from above and from the side.
--   KATSA_SHOT=tmp/hood xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.hood
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
    katsa.graphics.captureScreenshot((os.getenv('KATSA_SHOT') or 'tmp/hood') .. '/' .. name .. '.png')
end

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
        self.session:host('Tester', 47940 + math.floor(os.clock() * 100) % 9, { separate = false })
    end
    self.host:update(1 / 60, 1 / 60)
    self.host:draw()
    if frame == 201 then
        self.session:changeCar()
    elseif frame == 240 then
        local _, car = self.session.client:getCar()
        car.dents:add({ x = 0.2, y = 1.05, z = 1.7, dx = 0, dy = -1, dz = 0, depth = 0.12, radius = 0.6 })
        self.session.views[self.session.client:getCar()]:markDirty()
        self:view(3.2, 20, -62)
    elseif frame == 250 then
        self:shot('top')
        self:view(4, 70, -25)
    elseif frame == 256 then
        self:shot('side')
        katsa.event.quit()
    end
end

return Tests
