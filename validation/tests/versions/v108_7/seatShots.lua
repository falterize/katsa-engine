-- Diagnostic: four riders on a car (driver, front passenger, hood, trunk) and the boarding move.
--   KATSA_SHOT=tmp/seats xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.seats
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

local VIEWS = { { 7, 35, -18 }, { 7, 215, -18 }, { 6, 90, -10 }, { 6, 270, -10 } }

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
        self.session:host('Tester', 47940 + math.floor(os.clock() * 100) % 9, { separate = false })
    end
    local host, session = self.host, self.session
    host:update(1 / 60, 1 / 60)
    host:draw()
    local shot = os.getenv('KATSA_SHOT') or 'tmp/seats'
    if frame == 201 then
        session:changeCar()
    elseif frame == 260 then
        local netId = session.client:getCar()
        local carView = session.views[netId]
        local WalkerView = require('source.game.scenes.multiplayerCars.scripts.walker.view')
        self.riders = {}
        for seat = 2, 4 do
            local model = { state = 8, x = 0, y = 0, z = 0, heading = 0, playerId = 9000 + seat }
            self.riders[seat] = WalkerView.new(session.scene, 9000 + seat, model)
        end
        self.carView = carView
        local orbit = session.orbit
        orbit.idle = -1000
    end
    if self.riders then
        for seat, view in pairs(self.riders) do
            view:update(1 / 60, { root = self.carView.root, seat = seat })
        end
        local i = math.floor((frame - 300) / 25) + 1
        if frame >= 300 and (frame - 300) % 25 == 0 and VIEWS[i] then
            local orbit, v = session.orbit, VIEWS[i]
            orbit.distance, orbit.yaw, orbit.pitch = v[1], v[2], v[3]
            self.pending = i
        elseif self.pending and (frame - 300) % 25 == 15 then
            katsa.graphics.captureScreenshot(shot .. '/s' .. self.pending .. '.png')
            self.pending = nil
        elseif frame > 300 + #VIEWS * 25 then
            katsa.event.quit()
        end
    end
end

return Tests
