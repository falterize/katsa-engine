local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    if os.getenv('KATSA_TEST_INTERPRETER') == '1' then
        jit.off()
        jit.flush()
    end
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS v103', label)
end

function T:update() end

local function fixture(manager, backend)
    local resources = manager.resources:scope()
    local world = require('source.engine.world.world').new(resources)
    world.physics = require('source.engine.physics').new({ backend = backend, interpolate = true })
    return world, resources
end

local function body(w, name, position, kind, shape)
    return w:create('Body3D', {
        name = name,
        position = position,
        size = { 20, 20, 20 },
        bodyType = kind or 'Dynamic',
        collider = shape or { shape = 'Box', size = { 20, 20, 20 } },
    })
end

local function step(w, count)
    for i = 1, count do
        w:updateNodes(1 / 60)
        w.physics:update(1 / 60)
    end
end

function T:backend(name)
    local w, res = fixture(self.manager, name)
    local p = w.physics
    self:check(p.backendName == name, 'Explicit backend selection: ' .. name)
    local floor = body(
        w,
        'Floor',
        { 0, -10, 0 },
        'Static',
        { shape = 'Box', size = { 400, 20, 400 } }
    )
    local cube = body(w, 'Cube', { 0, 100, 0 })
    local beginCount, endCount = 0, 0
    cube:connect('contactBegin', function()
        beginCount = beginCount + 1
    end)
    cube:connect('contactEnd', function()
        endCount = endCount + 1
    end)
    step(w, 180)
    print('SETTLED', name, cube.position[2], cube.body:getVelocity()[2], beginCount)
    self:check(math.abs(cube.position[2] - 10) < 1, name .. ': falling body settles on floor')
    self:check(beginCount > 0, name .. ': native contactBegin reaches scene events')
    local hit = p:raycast({ 0, 100, 0 }, { 0, -40, 0 })
    self:check(
        hit and hit.body == cube.body and hit.normal[2] > 0.9,
        name .. ': closest ray hit and normal'
    )
    hit = p:raycast({ 0, 100, 0 }, { 0, -40, 0 }, function(b)
        return b ~= cube.body
    end)
    self:check(
        hit and hit.body == floor.body,
        name .. ': filtered ray sees body behind rejected hit'
    )
    cube.body:teleport({ 0, 80, 0 }, { 0, 0, 0 })
    step(w, 2)
    self:check(endCount > 0, name .. ': contactEnd after teleport')
    cube.body:set({ gravityScale = 0, mass = 3 })
    self:check(math.abs(cube.body:getMass() - 3) < 0.001, name .. ': mass update')
    cube.body:setVelocity({ 10, 0, 0 })
    step(w, 6)
    self:check(cube.body:getVelocity()[1] > 9, name .. ': velocity uses scene units')
    cube.body:applyImpulse({ 30, 0, 0 })
    self:check(cube.body:getVelocity()[1] > 18, name .. ': impulse changes velocity immediately')
    cube.body:teleport({ 0, 50, 0 }, { 0, 0, 0 })
    cube.body:setVelocity({ 0, 0, 0 })
    cube.body:setCollider({ shape = 'Sphere', radius = 15 })
    hit = p:raycast({ 0, 100, 0 }, { 0, 0, 0 })
    self:check(
        hit and hit.body == cube.body and math.abs(hit.position[2] - 65) < 0.2,
        name .. ': rebuilt collider is visible to ray immediately'
    )
    local sensor = body(w, 'Sensor', { 70, 30, 0 }, 'Static')
    sensor.body:set({ isTrigger = true })
    local target = body(w, 'Target', { 70, 30, 0 }, 'Static')
    local enters, exits = 0, 0
    sensor:connect('triggerEntered', function()
        enters = enters + 1
    end)
    sensor:connect('triggerExited', function()
        exits = exits + 1
    end)
    step(w, 1)
    self:check(enters > 0, name .. ': exact trigger enter')
    target.body:teleport({ 120, 30, 0 })
    step(w, 1)
    self:check(exits > 0, name .. ': exact trigger exit')
    local old = target.body
    target:destroy()
    step(w, 1)
    self:check(old.destroyed and not old._inWorld, name .. ': destruction detaches body')
    local locked = body(w, 'Locked', { -60, 50, 0 })
    locked.body:set({ gravityScale = 0, rotationFactor = { 0, 0, 0 } })
    locked.body:applyAngularImpulse({ 1000, 0, 0 })
    step(w, 3)
    self:check(math.abs(locked.rotation[1]) < 0.01, name .. ': rotation axis locks')
    locked.body.raw:sleep()
    self:check(locked.body.raw:isSleeping(), name .. ': explicit sleep')
    locked.body.raw:wakeUp()
    self:check(not locked.body.raw:isSleeping(), name .. ': explicit wake')
    local ghost = body(w, 'Ghost', { 120, 80, 0 })
    p:setGroupsCollidable('Ghosts', 'Default', false)
    ghost.body:set({ collisionGroup = 'Ghosts' })
    step(w, 100)
    self:check(
        ghost.position[2] < -20,
        name .. ': collision matrix changes disable existing broadphase pairs'
    )
    ghost.body:teleport({ 120, 80, 0 })
    ghost.body:setVelocity({ 0, 0, 0 })
    p:setGroupsCollidable('Ghosts', 'Default', true)
    step(w, 180)
    self:check(math.abs(ghost.position[2] - 10) < 1, name .. ': re-enabled groups collide again')
    ghost:destroy()
    if name == 'jolt' then
        local before = cube.body.settings.collider
        local ok = pcall(
            cube.body.setCollider,
            cube.body,
            { shape = 'Convex', vertices = { { 0, 0, 0 }, { 1, 0, 0 }, { 2, 0, 0 }, { 3, 0, 0 } } }
        )
        self:check(
            not ok and cube.body.settings.collider == before,
            name .. ': invalid native shape preserves the live collider'
        )
        self:check(
            not pcall(p.raycast, p, { 0, 100, 0 }, { 0, 0, 0 }, function()
                    error('expected ray filter failure')
                end) and p.rayFilter == nil,
            name .. ': query errors return safely across FFI and reset filter state'
        )
    end
    -- All public joint families must construct, update and release on either backend.
    for _, class in ipairs({
        'BallSocketConstraint3D',
        'HingeConstraint3D',
        'PrismaticConstraint3D',
        'SliderConstraint3D',
        'CylindricalConstraint3D',
        'UniversalConstraint3D',
        'RagdollConstraint3D',
        'GenericConstraint3D',
        'WeldConstraint3D',
        'RopeConstraint3D',
        'SpringConstraint3D',
    }) do
        local a = body(w, 'JointA', { -120, 100, 0 }, 'Static')
        local b = body(w, 'JointB', { -120, 80, 0 })
        local a0 = w:create('Attachment3D', { position = { 0, -10, 0 } }, a)
        local a1 = w:create('Attachment3D', {
            position = { 0, 10, 0 },
            rotation = class == 'UniversalConstraint3D' and { 0, 0, 90 } or nil,
        }, b)
        local joint = w:create(class, { attachment0 = a0, attachment1 = a1 })
        step(w, 4)
        self:check(
            joint.joint and joint.status == 'Active',
            name .. ': ' .. class .. ' creates a solver constraint'
        )
        joint:step(1 / 60)
        local handle = joint.joint
        joint:step(1 / 60)
        self:check(joint.joint == handle, name .. ': ' .. class .. ' retains unchanged joint')
        if
            class == 'HingeConstraint3D'
            or class == 'PrismaticConstraint3D'
            or class == 'SliderConstraint3D'
            or class == 'CylindricalConstraint3D'
            or class == 'UniversalConstraint3D'
            or class == 'RagdollConstraint3D'
        then
            b.body:set({ gravityScale = 0 })
            joint.motorSpeed, joint.motorForce = 30, 100
            step(w, 12)
            local linear = class == 'PrismaticConstraint3D' or class == 'SliderConstraint3D'
            local v = linear and b.body:getVelocity() or b.body.raw:getAngularVelocity()
            local magnitude = linear and math.abs(v[1]) + math.abs(v[2]) + math.abs(v[3])
                or math.abs(v.x) + math.abs(v.y) + math.abs(v.z)
            self:check(magnitude > 0.01, name .. ': ' .. class .. ' motor drives motion')
        end
        joint.enabled = false
        step(w, 1)
        self:check(not joint.joint, name .. ': ' .. class .. ' releases when disabled')
        joint:destroy()
        a:destroy()
        b:destroy()
    end
    p:release()
    w:release()
    res:release()
    self:check(not p.driver or not p.driver.system, name .. ': native world resources released')
    w, res = fixture(self.manager, name)
    p = w.physics
    local a = body(w, 'CloseStatic', { 0, 0, 0 }, 'Static')
    local b = body(w, 'CloseDynamic', { 0, 0, 0 })
    b:connect('contactBegin', function()
        w:release()
    end)
    p:update(1 / 60)
    self:check(
        p.released and #p.bodies == 0,
        name .. ': releasing scene from contact defers native teardown safely'
    )
    res:release()
    w, res = fixture(self.manager, name)
    p = w.physics
    local target = body(w, 'QueryMutation', { 0, 30, 0 }, 'Static')
    p:raycast({ 0, 100, 0 }, { 0, -100, 0 }, function(hitBody)
        target:destroy()
        return true
    end)
    self:check(
        target.destroyed and #p.bodies == 0 and not p._querying,
        name .. ': query filter mutations commit after native traversal'
    )
    w:release()
    res:release()
end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local Physics = require('source.engine.physics')
    local default = Physics.backends.default
    for _, name in ipairs({ 'oimo', 'jolt' }) do
        self:backend(name)
        Physics.setDefaultBackend(name)
        require('validation.tests.integration.contactLifecycle')(self)
        require('validation.tests.integration.physicsTransforms')(self)
    end
    Physics.setDefaultBackend(default)
    local driver = require('source.engine.physics.3d.backends.jolt.driver')
    local count = driver.liveWorldCount()
    local wa, ra = fixture(self.manager, 'jolt')
    local wb, rb = fixture(self.manager, 'jolt')
    wb.physics.world:setGravity(Physics.backend.Vec3.new(0, 0, 0))
    local a = body(wa, 'WorldA', { 0, 80, 0 })
    local b = body(wb, 'WorldB', { 0, 80, 0 })
    step(wa, 60)
    step(wb, 60)
    self:check(
        a.position[2] < 0 and b.position[2] == 80,
        'Simultaneous Jolt worlds retain independent gravity and state'
    )
    wa:release()
    ra:release()
    step(wb, 2)
    self:check(
        b.body and b.position[2] == 80,
        'Releasing one Jolt world does not invalidate another'
    )
    wb:release()
    rb:release()
    self:check(
        driver.liveWorldCount() == count,
        'Scene roots release native worlds and callback references'
    )
    local w, res = fixture(self.manager, 'jolt')
    local a = body(w, 'BreakAnchor', { 0, 100, 0 }, 'Static')
    local b = body(w, 'BreakWeight', { 0, 50, 0 })
    local aa = w:create('Attachment3D', {}, a)
    local bb = w:create('Attachment3D', {}, b)
    local constraint = w:create(
        'BallSocketConstraint3D',
        { attachment0 = aa, attachment1 = bb, breakForce = 0.0001 }
    )
    local broken = false
    constraint:connect('Broken', function()
        broken = true
    end)
    step(w, 2)
    self:check(
        broken and constraint.enabled == false,
        'Native constraint reaction force enforces breakForce and emits Broken'
    )
    w:release()
    res:release()
    require('validation.tests.versions.v103.optimization')(self)
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' v103 backend checks')
    katsa.event.quit()
end

return T
