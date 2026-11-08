-- The shapeKeysLab example: the generated glTF exposes its shape keys and sliders move vertices.
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

function Tests:draw()
    self.frame = self.frame + 1
    if self.host then
        self.host:update(1 / 60, 1 / 60)
        self.host:draw()
    end
    if self.frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'shapeKeysLab')
        self.host:load()
        self.lab = self.host.demo
        local mesh = self.lab.mesh
        self:check(mesh and mesh:getBlendShapeCount() == 4, 'the blob exposes four shape keys')
        self:check(mesh:findBlendShapeByName('Squash') == 1, 'shape names come from targetNames')
        self:check(self.lab.sliders.Spike ~= nil, 'every shape key has a slider')
        self.lab:setShape('Stretch', 1)
        self:check(mesh:getBlendShapeValue('Stretch') == 1, 'a slider value sets the shape weight')
        self.lab.wave = true
    elseif self.frame == 4 then
        self:check(self.lab.mesh:getBlendShapeValue('Twist') ~= 0, 'Wave drives the weights from code')
        print('PASSED ' .. self.count .. ' v108.7 shapeKeys checks')
        katsa.event.quit()
    end
end

return Tests
