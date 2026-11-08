-- A car whose nose was dented in must not climb a wall with its wheels, and a wheel can be lost
-- twice (needs the real scene).
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

-- Drives a car at a wall for `seconds` (heading in degrees); returns the highest chassis height
-- above its start and the distance to the wall at the end.
function Tests:crash(dents, seconds, heading, corner)
    local Session = getmetatable(self.host.demo).__index
    local world = self.host.world
    local spawn = { -12, -40 }
    local ground = self.host.package:require('scripts.game.arena').ground
    local wallZ = spawn[2] + 5.5
    local wall = world:create('Body3D', {
        name = 'TestWall',
        bodyType = 'Static',
        position = { spawn[1], ground(spawn[1], wallZ) + 2, wallZ },
    })
    world:create('Collider3D', { shape = 'Box', size = { 60, 4, 1 } }, wall)
    wall:update(0)
    local model = self.host.package:require('scripts.game.carEntity').create(
        nil,
        { x = spawn[1], z = spawn[2], heading = heading or 0 }
    )
    for _ = 1, dents do
        if corner then
            model.dents:addImpact({ x = corner * 0.9, y = 0.6, z = 2.3, nx = -corner * 0.5, ny = 0, nz = -0.85, speed = 22 })
        else
            model.dents:addImpact({ x = 0, y = 0.6, z = 2.5, nx = 0, ny = 0, nz = -1, speed = 22 })
        end
    end
    local body = Session.PhysicsCar.new(world, model, 95)
    body:setInput({ throttle = 1 })
    local dt = 1 / 60
    local top, startY = -math.huge, nil
    for _ = 1, math.floor(seconds * 60) do
        body:step(dt)
        self.host.physics:update(dt)
        body:readState()
        startY = startY or model.y
        top = math.max(top, model.y)
    end
    local gap = wallZ - 0.5 - model.z
    body:destroy()
    wall:destroy()
    return top - startY, gap
end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
    self.host:load()
    local intactRise = self:crash(0, 3, 15)
    local dentedRise = self:crash(8, 3, 15)
    print(('rise intact %.2f m  dented %.2f m'):format(intactRise, dentedRise))
    self:check(intactRise < 0.5, 'An undamaged car stays on the ground in front of a wall')
    self:check(dentedRise < 0.5, 'A car with a dented-in nose does not climb the wall with its wheels')
    -- A repaired car can lose the same wheel again while the first one still rolls around.
    local CarView = self.host.package:require('scripts.view.carView')
    local model = self.host.package:require('scripts.game.carEntity').create(nil, { x = -12, z = -40 })
    local view = CarView.new(self.host, 96, model)
    local ok, why = pcall(function()
        view:shedWheel(1)
        view:shedWheel(1)
    end)
    self:check(ok and #view.debris == 2, 'The same wheel can be lost twice while the first still rolls: ' .. tostring(why))
    view:destroy()
    print('PASSED ' .. self.count .. ' v108.7 wall climb checks')
    katsa.event.quit()
end

return Tests
