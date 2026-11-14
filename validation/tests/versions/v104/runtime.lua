local Baseline = require('validation.tests.versions.v103.runtime')
local Physics = require('source.engine.physics')
local World = require('source.engine.world.world')

local Tests = setmetatable({}, { __index = Baseline })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Baseline.new(manager), Tests)
end

local function advance(world)
    world:updateNodes(1 / 60)
    world.physics:update(1 / 60)
end

function Tests:adapter(name)
    local resources = self.manager.resources:scope()
    local world = World.new(resources)
    world.physics = Physics.new({ backend = name })
    local physics = world.physics
    self:check(physics.adapter.world == physics.world, name .. ': adapter owns selected world')
    self:check(physics.valueTypes == Physics.backend, name .. ': historical value API preserved')

    local anchor = world:create('Body3D', {
        name = 'Anchor',
        bodyType = 'Static',
        position = { 0, 80, 0 },
        size = { 20, 20, 20 },
    })
    local weight = world:create('Body3D', {
        name = 'Weight',
        position = { 0, 40, 0 },
        size = { 20, 20, 20 },
    })
    local a = world:create('Attachment3D', {}, anchor)
    local b = world:create('Attachment3D', {}, weight)
    local constraint = world:create('BallSocketConstraint3D', { attachment0 = a, attachment1 = b })
    advance(world)
    local original = constraint.joint
    self:check(original ~= nil, name .. ': scene constraint creates a backend joint')
    advance(world)
    self:check(constraint.joint == original, name .. ': unchanged inputs keep the joint')

    weight.physics:setCollider({ shape = 'Sphere', radius = 10, position = { 0, 5, 0 } })
    advance(world)
    self:check(constraint.joint ~= original, name .. ': changed collider invalidates joint frame')
    local replacement = constraint.joint
    advance(world)
    self:check(constraint.joint == replacement, name .. ': new collider frame is cached')

    local before = weight.physics.shapes[1].raw
    local ok = pcall(function()
        weight.physics:setCollider({ shape = 'Sphere', radius = -1 })
    end)
    self:check(
        not ok and weight.physics.shapes[1].raw == before,
        name .. ': rejected replacement preserves the live collider'
    )
    world:release()
    resources:release()
    self:check(physics.released, name .. ': facade releases adapter resources')
end

function Tests:draw()
    if self.done then
        return
    end
    self:adapter('oimo')
    self:adapter('jolt')
    local Jolt = require('source.engine.physics.3d.backends.jolt.driver')
    local before = Jolt.liveWorldCount()
    local ok = pcall(Physics.new, { backend = 'jolt', maxSteps = 0 })
    self:check(
        not ok and Jolt.liveWorldCount() == before,
        'Invalid world settings fail before native allocation'
    )
    Baseline.draw(self)
    print('PASSED ' .. self.count .. ' v104 checks')
end

return Tests
