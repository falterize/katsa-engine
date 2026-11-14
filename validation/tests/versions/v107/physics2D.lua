local World = require('source.engine.world.world')
local Physics2D = require('source.engine.physics.2d')
local Node = require('source.engine.nodes')

local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    io.stdout:setvbuf('no')
    katsa.errorhandler = function(message)
        print('FAILED Physics2D ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable({ manager = manager, count = 0 }, Tests)
end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS Physics2D', label)
end

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 0.01)
end

function Tests:environment(options)
    local resources = self.manager.resources:scope()
    local world = World.new(resources)
    local ui = world:create('World2D', { width = 1280, height = 720 })
    local physics = ui:createPhysics(options or { gravity = { 0, 0 } })
    local function body(x, y, kind, collider)
        return ui:create('Body2D', {
            position = { x, y },
            size = { 20, 20 },
            bodyType = kind or 'Dynamic',
            linearDamping = 0,
            angularDamping = 0,
            collider = collider or { shape = 'Box', size = { 20, 20 } },
        })
    end
    local function release()
        world:release()
        resources:release()
    end
    return world, ui, physics, body, release
end

function Tests:motion()
    local meter = katsa.physics.getMeter()
    local world, ui, physics, body, release = self:environment({ gravity = { 0, 640 }, units = 64 })
    local floor = body(200, 300, 'Static', { shape = 'Box', size = { 500, 20 } })
    local ball = body(200, 0, 'Dynamic', { shape = 'Circle', radius = 10 })
    local enters = 0
    ball:connect('collisionEnter', function(other)
        if other == floor then
            enters = enters + 1
        end
    end)
    for _ = 1, 180 do
        physics:update(1 / 60)
    end
    self:check(near(ball.position[2], 280, 1), 'Dynamic circle rests on a static floor')
    self:check(
        enters == 1 and #ball.physics:getContacts() == 1,
        'Contact enter and persistent contact list agree'
    )
    self:check(
        katsa.physics.getMeter() == meter,
        'Creating a world does not change the global Box2D meter'
    )
    self:check(
        physics.stats.bodies == 2 and physics.stats.fixtures == 2,
        '2D statistics count bodies and fixtures'
    )
    local before = ball.position[2]
    physics.paused = true
    physics:update(1)
    self:check(
        ball.position[2] == before and physics.stats.steps == 0,
        'Paused physics does not advance'
    )
    physics.paused = false
    ball.physics:teleport({ 200, 20 }, 30)
    self:check(
        near(ball.rotation, 30),
        'Vector teleport synchronizes position and clockwise degree rotation'
    )
    ball.physics:setVelocity({ 100, 0 })
    self:check(
        near(ball.physics:getVelocity()[1], 100),
        'Velocity API accepts the same vector convention as 3D'
    )
    ball.physics:setMass(2)
    ball.physics:applyImpulse({ 20, 0 })
    self:check(near(ball.physics:getVelocity()[1], 110), 'Impulse respects an explicit mass override')
    ball.physics:setAngularVelocity(90)
    self:check(
        near(ball.physics:getAngularVelocity(), 90),
        '2D angular velocity uses degrees per second'
    )
    physics:setGravity(0, 0)
    local gx, gy = physics:getGravity()
    self:check(gx == 0 and gy == 0, 'Gravity access uses authored world units')
    ball.physics:set({ type = 'Kinematic' })
    local y = ball.position[2]
    ball.physics:setLinearVelocity(0, 60)
    physics:update(1 / 60)
    self:check(near(ball.position[2], y + 1), 'Kinematic bodies move at their authored velocity')
    ball.position[1] = 400
    physics:update(0)
    self:check(
        near(ball.physics:getPosition(), 400),
        'In-place authored position changes teleport the solver body'
    )
    physics:update(2)
    self:check(
        physics.stats.steps == physics.maxSteps and physics.stats.droppedTime > 1,
        'Catch-up is bounded and discarded time is measured'
    )
    self:check(not pcall(physics.update, physics, -1), 'Negative simulation time is rejected')
    physics.debug.enabled, physics.debug.velocities = true, true
    physics:draw()
    physics:drawDebug()
    release()
    self:check(
        physics.released and ball.destroyed,
        'World teardown destroys its 2D nodes and native world'
    )
    physics:release()
    physics:update(1)
    self:check(true, 'Release and post-release update are idempotent')
end

function Tests:collidersAndQueries()
    local world, ui, physics, body, release = self:environment()
    local box = body(50, 50, 'Static')
    local ball = body(100, 50, 'Dynamic', { shape = 'Circle', radius = 10 })
    physics:update(0)
    local firstFixture = box.physics.fixtures[1]
    for _ = 1, 5 do
        physics:update(1 / 60)
    end
    self:check(
        box.physics.fixtures[1] == firstFixture,
        'Unchanged colliders retain their native fixtures'
    )
    local hit = physics:raycast({ 0, 50 }, { 150, 50 })
    self:check(
        hit and hit.physics == box.physics and near(hit.position[1], 40),
        'Raycast returns the nearest world-space hit'
    )
    local all = physics:raycastAll({ 0, 50 }, { 150, 50 })
    self:check(#all == 2 and all[1].fraction < all[2].fraction, 'Raycast-all sorts unclipped hits')
    box.canQuery = false
    self:check(
        physics:raycast({ 0, 50 }, { 150, 50 }).physics == ball.physics,
        'canQuery hides a body from raycasts'
    )
    box.canQuery = true
    self:check(
        #physics:overlapPoint({ 50, 50 }) == 1,
        'Point queries test exact fixture containment'
    )
    self:check(
        #physics:overlapCircle({ 50, 50 }, 5) == 1,
        'Circle overlap uses exact Box2D shape distance'
    )
    self:check(#physics:overlapBox({ 75, 50 }, { 60, 10 }) == 2, 'Box overlap deduplicates bodies')
    self:check(
        #physics:overlapCircle({ 64, 64 }, 2) == 0,
        'Circle query rejects an AABB-only false positive'
    )
    self:check(#physics:overlapBox({ 50, 50 }, { 10, 10 }, function(b)
        return b == ball.physics
    end) == 0, 'Overlap filters receive body wrappers')
    local node = ui:create('Collider2D', { shape = 'Circle', radius = 12 }, ball)
    physics:update(0)
    self:check(
        #ball.physics.fixtures == 1 and ball.physics.fixtures[1]:getShape():getType() == 'circle',
        'Explicit Collider2D replaces the default collider'
    )
    local previous = ball.physics.fixtures[1]
    node.radius = 15
    physics:update(0)
    self:check(
        previous:isDestroyed() and not ball.physics.fixtures[1]:isDestroyed(),
        'Changed collider properties rebuild safely'
    )
    local second = ui:create('Collider2D', { position = { 30, 0 }, size = { 10, 10 } }, ball)
    physics:update(0)
    self:check(#ball.physics.fixtures == 2, 'Multiple Collider2D children form a compound body')
    node.enabled, second.enabled = false, false
    physics:update(0)
    self:check(#ball.physics.fixtures == 0, 'Disabling every explicit collider removes all fixtures')
    node:destroy()
    second:destroy()
    physics:update(0)
    self:check(
        #ball.physics.fixtures == 1,
        'Removing explicit colliders restores the authored fallback shape'
    )
    for _, shape in ipairs({
        { shape = 'Polygon', vertices = { -10, -10, 10, -10, 0, 10 } },
        { shape = 'Edge', vertices = { -10, 0, 10, 0 } },
        { shape = 'Chain', vertices = { -10, 0, 0, 10, 10, 0 } },
        {
            shape = 'Compound',
            children = {
                { shape = 'Box', size = { 10, 10 } },
                { shape = 'Circle', radius = 5, offset = { 20, 0 } },
            },
        },
    }) do
        local item = body(300, 300, 'Static', shape)
        self:check(#item.physics.fixtures > 0, shape.shape .. ' collider builds native fixtures')
    end
    local original = box.physics.fixtures[1]
    self:check(
        not pcall(box.physics.setCollider, box.physics, { shape = 'Invalid' }),
        'Invalid collider input is rejected'
    )
    self:check(
        not original:isDestroyed(),
        'A failed collider replacement preserves the current fixture'
    )
    box.physics:setCollider({ shape = 'Box', size = { 20, 20 } })
    physics.debug.enabled = true
    physics:drawDebug()
    release()
end

function Tests:triggersAndLifetime()
    local world, ui, physics, body, release = self:environment()
    local sensor = body(0, 0, 'Static', { shape = 'Box', size = { 100, 100 } })
    sensor.isTrigger = true
    local item = body(0, 0)
    local enters, exits = 0, 0
    sensor:connect('triggerEnter', function()
        enters = enters + 1
    end)
    sensor:connect('triggerExit', function()
        exits = exits + 1
    end)
    physics:update(1 / 60)
    self:check(
        enters == 1 and near(item.position[1], 0),
        'Sensors emit enter without a collision response'
    )
    item.physics:teleport(200, 0)
    physics:update(1 / 60)
    self:check(exits == 1, 'Leaving a trigger emits exit')
    physics:setGroupsCollidable('Sensor', 'Actor', false)
    sensor.collisionGroup, item.collisionGroup = 'Sensor', 'Actor'
    item.physics:teleport(0, 0)
    physics:update(1 / 60)
    self:check(enters == 1, 'Collision groups filter trigger contacts')
    physics:setGroupsCollidable('Sensor', 'Actor', true)
    for _ = 1, 3 do
        physics:update(1 / 60)
    end
    self:check(enters == 2, 'Changing group interaction refilters existing fixtures')
    sensor:connect('triggerEnter', function(other)
        other:destroy()
    end)
    local doomed = body(0, 0)
    physics:update(1 / 60)
    self:check(
        doomed.destroyed and doomed.physics == nil,
        'Nodes can be destroyed safely from contact events'
    )
    local blocked = body(400, 0)
    blocked:connect('collisionEnter', function()
        physics:update(1 / 60)
    end)
    local same = body(400, 0, 'Static')
    self:check(
        not pcall(physics.update, physics, 1 / 60),
        'Reentrant simulation from contact callbacks is rejected'
    )
    blocked:destroy()
    same:destroy()
    local otherUI = world:create('World2D', { name = 'Other2D' })
    otherUI:createPhysics({ gravity = { 0, 0 } })
    self:check(
        not pcall(item.setParent, item, otherUI),
        'A body cannot migrate between physical World2D owners'
    )
    self:check(item.parent == ui, 'Rejected reparenting preserves the existing hierarchy')
    release()
end

function Tests:constraints()
    for _, kind in ipairs({
        'Hinge',
        'Prismatic',
        'Weld',
        'Rope',
        'Spring',
        'Distance',
        'Wheel',
        'Friction',
        'Motor',
        'Pulley',
        'Mouse',
    }) do
        local _, ui, physics, body, release = self:environment()
        local a, b = body(0, 0, kind == 'Pulley' and 'Dynamic' or 'Static'), body(0, 40)
        local p = ui:create('Attachment2D', {}, a)
        local q = ui:create('Attachment2D', {}, b)
        local joint = ui:create(kind .. 'Constraint2D', {
            attachment0 = p,
            attachment1 = q,
            groundAnchor0 = { -50, -100 },
            groundAnchor1 = { 50, -100 },
            length = 40,
            maxLength = 40,
            motorForce = 1000,
            maxForce = 1000,
        })
        physics:update(1 / 60)
        self:check(
            joint.status == 'Active' and joint.joint and not joint.joint:isDestroyed(),
            kind .. 'Constraint2D builds a live Box2D joint'
        )
        local native = joint.joint
        b.physics:setLinearVelocity(30, 10)
        for _ = 1, 10 do
            physics:update(1 / 60)
        end
        self:check(
            joint.joint == native,
            kind .. 'Constraint2D retains its joint while bodies move'
        )
        joint.enabled = false
        physics:update(1 / 60)
        self:check(
            joint.status == 'Disabled' and native:isDestroyed(),
            kind .. 'Constraint2D disable releases native state'
        )
        joint.enabled = true
        physics:update(1 / 60)
        self:check(joint.status == 'Active', kind .. 'Constraint2D can be enabled again')
        a:destroy()
        physics:update(1 / 60)
        self:check(
            (kind == 'Mouse' and joint.status == 'Active')
                or (not joint.joint and joint.status:find('Waiting')),
            kind .. 'Constraint2D handles endpoint deletion'
        )
        release()
    end
    local _, ui, physics, body, release = self:environment()
    local ground, a, b = body(0, 0, 'Static'), body(30, 0), body(90, 0)
    local function hinge(item)
        return ui:create('HingeConstraint2D', {
            attachment0 = ui:create('Attachment2D', { position = { item.position[1], 0 } }, ground),
            attachment1 = ui:create('Attachment2D', {}, item),
        })
    end
    local h0, h1 = hinge(a), hinge(b)
    local gear = ui:create('GearConstraint2D', {
        joint0 = h0,
        joint1 = h1,
        ratio = 2,
        attachment0 = h0.attachment1,
        attachment1 = h1.attachment1,
    })
    physics:update(1 / 60)
    self:check(gear.joint and gear.status == 'Active', 'GearConstraint2D binds two existing hinges')
    h0:destroy()
    self:check(not gear.joint, 'Deleting a gear source first releases the dependent gear')
    gear:destroy()
    local spring = ui:create('SpringConstraint2D', {
        attachment0 = ui:create('Attachment2D', {}, ground),
        attachment1 = ui:create('Attachment2D', {}, a),
        length = 2,
        breakForce = 0.001,
    })
    physics:update(1 / 60)
    self:check(
        spring.broken and spring.status == 'Broken',
        'Constraint break thresholds use solver reaction force'
    )
    spring.breakForce = 0
    spring:repair()
    physics:update(1 / 60)
    self:check(spring.status == 'Active', 'Broken constraints can be repaired explicitly')
    release()
end

function Tests:cameraAndMixed()
    local world, ui, physics, body, release = self:environment()
    local camera = ui:create('Camera2D', { position = { 100, 50 }, rotation = 30, zoom = 2 })
    local sx, sy = camera:worldToScreen(300, 150, 1280, 720)
    local x, y = camera:screenToWorld(sx, sy, 1280, 720)
    self:check(
        near(x, 300) and near(y, 150),
        'Camera2D world/screen conversions invert pan, zoom and rotation'
    )
    ui:fit(960, 540)
    sx, sy = ui:worldToScreen2D(300, 150)
    x, y = ui:screenToWorld2D(sx, sy)
    self:check(
        near(x, 300) and near(y, 150),
        'World2D pointer conversion includes UI scale and offset'
    )
    local target = body(200, 250)
    camera.followTarget = target
    camera:updateFollow(1 / 60)
    self:check(
        near(camera.position[1], 200) and near(camera.position[2], 250),
        'Camera2D follows a local spatial target'
    )
    local parent = ui:create('Node2D', { position = { 100, 100 }, rotation = 90 })
    local nested = ui:create('Body2D', { position = { 20, 0 }, bodyType = 'Kinematic' }, parent)
    local px, py = nested.physics:getPosition()
    self:check(near(px, 100) and near(py, 120), 'Body2D inherits rigid parent transforms')
    nested.physics:teleport(200, 200, 45)
    px, py = nested:getWorldPose()
    self:check(
        near(px, 200) and near(py, 200),
        'Solver world pose converts back to local hierarchy coordinates'
    )
    world:createPhysics({ backend = 'oimo', gravity = { 0, 0, 0 } })
    local spatial = world:create('Body3D', { position = { 0, 10, 0 }, size = { 1, 1, 1 } })
    spatial.physics:setVelocity({ 1, 0, 0 })
    target.physics:setVelocity({ 10, 0 })
    for _ = 1, 60 do
        world.physics:update(1 / 60)
        physics:update(1 / 60)
    end
    self:check(
        spatial.position[1] > 0.8 and target.position[1] > 205,
        '2D and 3D solvers advance independently in the same scene'
    )
    self:check(
        Node.getClass('HingeConstraint3D') and Node.getClass('HingeConstraint2D'),
        'Dimension-specific constraints coexist without ambiguous class names'
    )
    ui:draw()
    camera:destroy()
    self:check(
        ui.camera2D == nil,
        'Destroying the current Camera2D clears the active camera reference'
    )
    release()
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self:motion()
    self:collidersAndQueries()
    self:triggersAndLifetime()
    self:constraints()
    self:cameraAndMixed()
    require('validation.tests.versions.v107.colliderAuthoring').run(self)
    require('validation.tests.versions.v107.worldClocks').run(self)
    print('PASSED ' .. self.count .. ' Physics2D checks')
    katsa.event.quit()
end

return Tests
