-- A car steers with its front wheels and is driven by its rear wheels (needs the real scene).
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

-- Drives a fresh car 4 s with full throttle and the given steering; returns heading change and
-- distance travelled.
function Tests:drive(detached, steer, netId)
    local Session = getmetatable(self.host.demo).__index
    local PhysicsCar = Session.PhysicsCar
    local spawn = { -12, -40, 0 }
    local model = self.host.package:require('scripts.game.carEntity').create(
        nil,
        { x = spawn[1], z = spawn[2], heading = spawn[3], detached = detached }
    )
    local body = PhysicsCar.new(self.host.world, model, netId)
    local dt = 1 / 60
    body:setInput({ throttle = 1, steer = steer })
    local startX, startZ, heading = model.x, model.z, model.heading
    local turned = 0
    local last = heading
    for _ = 1, 240 do
        body:step(dt)
        self.host.physics:update(dt)
        body:readState()
        local delta = (model.heading - last + 540) % 360 - 180
        turned, last = turned + delta, model.heading
    end
    local distance = math.sqrt((model.x - startX) ^ 2 + (model.z - startZ) ^ 2)
    body:destroy()
    return math.abs(turned), distance
end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
    self.host:load()
    local whole, wholeDistance = self:drive(0, 1, 90)
    local noFront, noFrontDistance = self:drive(3, 1, 91)
    local noRear, noRearDistance = self:drive(12, 0, 92)
    print(('turn whole %.1f  noFront %.1f  distance %.1f / %.1f / %.1f'):format(
        whole, noFront, wholeDistance, noFrontDistance, noRearDistance))
    self:check(whole > 20, 'A car with all wheels turns when steered')
    self:check(noFront < whole * 0.25, 'A car without front wheels cannot turn')
    self:check(noRearDistance < wholeDistance * 0.5, 'A car without rear wheels is not driven')
    -- A front hit pulls the hull's nose in: the collider follows the dents in three boxes.
    local Session = getmetatable(self.host.demo).__index
    local model = self.host.package:require('scripts.game.carEntity').create(nil, { x = -12, z = -40, heading = 0 })
    local body = Session.PhysicsCar.new(self.host.world, model, 93)
    body:step(1 / 60)
    local count = #body.node.body.shapes
    model.dents:addImpact({ x = 0, y = 0.6, z = 2.5, nx = 0, ny = 0, nz = -1, speed = 14 })
    body:step(1 / 60)
    local shapes = body.node.body.shapes
    local hull = body:hullFor(model.dents)
    self:check(count == 1 and #shapes == 3, 'Dents split the collider into a simplified three-box hull')
    self:check(hull.children[3].size[3] < 5.1 / 3 - 0.05, 'The nose section is shorter after a front hit')
    self:check(math.abs(hull.children[1].size[3] - 5.1 / 3) < 1e-6, 'An untouched section keeps its size')
    body:destroy()
    print('PASSED ' .. self.count .. ' v108.7 wheel steering checks')
    katsa.event.quit()
end

return Tests
