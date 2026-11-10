-- Diagnostic (not pass/fail): the multiplayerCars hills in a hosted game, from the chase camera.
--   KATSA_QUALITY=Medium KATSA_SHOT=tmp/hills xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.hills
-- PNGs land in ~/.local/share/Katsa/katsa-engine/tmp/hills.
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

local VIEWS = { { 9, 0, -10 }, { 9, 90, -10 }, { 9, 180, -10 }, { 9, 270, -10 }, { 14, 45, -25 } }

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
        self.host:load()
        self.session = self.host.demo
        self.session:host('Tester', 47930 + math.floor(os.clock() * 100) % 9, { separate = false })
    end
    local host, session = self.host, self.session
    host:update(1 / 60, 1 / 60)
    host:draw()
    if frame == 201 then
        session:changeCar()
        local quality = os.getenv('KATSA_QUALITY')
        if quality then
            host.world.environment:applyQualityProfile(quality)
        end
    elseif frame == 230 then
        local netId = session.client:getCar()
        local node = session.server.game.bodies[netId].node
        node.position = { -30, 8, -10 }
        node.body:sync()
    elseif frame >= 260 and (frame - 260) % 20 == 0 then
        local index = (frame - 260) / 20 + 1
        local view = VIEWS[index]
        if not view then
            katsa.event.quit()
            return
        end
        local orbit = session.orbit
        orbit.distance, orbit.yaw, orbit.pitch, orbit.idle = view[1], view[2], view[3], -1000
        self.pending = index
    elseif self.pending and frame % 20 == 14 then
        katsa.graphics.captureScreenshot(
            (os.getenv('KATSA_SHOT') or 'tmp/hills') .. '/v' .. self.pending .. '.png'
        )
        self.pending = nil
    end
end

return Tests
