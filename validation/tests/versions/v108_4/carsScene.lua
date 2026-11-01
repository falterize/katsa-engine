-- multiplayerCars scene end to end on the real renderer: host, connect, drive, bot, dents.
-- Set KATSA_CARS_SHOT=<dir> to save screenshots of the run.
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
    local dir = os.getenv('KATSA_CARS_SHOT')
    if dir then
        katsa.graphics.captureScreenshot(dir .. '/' .. name .. '.png')
    end
end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
        self.host:load()
        self.session = self.host.demo
        self:check(self.session.mode == 'menu', 'cars scene starts at the menu')
        self.session:host('Tester', 47990 + math.floor(os.clock() * 100) % 9)
    end
    local host, session = self.host, self.session
    if not host then
        return
    end
    host:update(1 / 60, 1 / 60)
    host:draw()
    if frame == 200 then
        self:check(session.mode == 'playing', 'hosting connects the local client')
        local count = 0
        for _ in pairs(session.views) do
            count = count + 1
        end
        self:check(count == 2, 'the player car and the bot are drawn')
        self:shot('start')
    elseif frame == 201 then
        host.input.actions.keys.w = true
    elseif frame == 320 then
        local _, car = session.client:getCar()
        self:check(car and car.speed > 8, 'holding W drives the car')
        self:shot('driving')
        host.input.actions.keys.w = nil
    elseif frame == 340 then
        local _, car = session.client:getCar()
        car.dents:addImpact({ x = 0, z = 2.1, nx = 0, nz = -1, speed = 15 })
        session.views[session.client:getCar()]:markDirty()
    elseif frame == 350 then
        self:shot('dent')
    elseif frame == 360 then
        self:check(session.hud.info.text:find('Driving'), 'the HUD shows the seat')
        session:leave()
        self:check(
            session.mode == 'menu' and next(session.views) == nil,
            'leaving returns to the menu'
        )
        host:update(1 / 60, 1 / 60)
        host:draw()
    elseif frame == 370 then
        host:release()
        print('PASSED ' .. self.count .. ' v108.4 cars scene checks')
        katsa.event.quit()
    end
end

return Tests
