return function(T)
    local P = require('source.katsa.physics')
    local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end
    P.setMeter(30)
    T.check(P.getMeter() == 30, 'meter default')

    local w = P.newWorld(0, 0, true)
    local b = P.newBody(w, 0, 0, 'dynamic')
    P.newFixture(b, P.newCircleShape(30), 1)
    T.check(near(b:getMass(), 3.14159, 1e-3), 'circle mass r=30px is pi kg')
    T.check(near(b:getInertia(), 1413.72, 0.05), 'inertia scaled by meter^2')

    b:applyForce(30, 0); w:update(1 / 60)
    T.check(near(b:getLinearVelocity(), 0.159155, 1e-3), 'force scaled by meter')
    b:setLinearVelocity(0, 0); b:applyLinearImpulse(30, 0)
    T.check(near(b:getLinearVelocity(), 9.5493, 1e-2), 'impulse scaled')
    b:setLinearVelocity(0, 0); b:setAngularVelocity(0); b:applyTorque(1000); w:update(1 / 60)
    T.check(near(b:getAngularVelocity(), 0.011789, 1e-4), 'torque scaled by meter^2')
    b:setAngularVelocity(0); b:applyAngularImpulse(1000)
    T.check(near(b:getAngularVelocity(), 0.707355, 1e-3), 'angular impulse scaled')

    local a1 = P.newBody(w, 0, 100, 'static'); local f1 = P.newFixture(a1, P.newCircleShape(10), 1)
    local a2 = P.newBody(w, 100, 100, 'static'); local f2 = P.newFixture(a2, P.newCircleShape(10), 1)
    T.check(near(select(1, P.getDistance(f1, f2)), 80, 0.05), 'getDistance in pixels')

    -- gravity, falling, callbacks
    local g = P.newWorld(0, 300, true)
    local ground = P.newBody(g, 0, 200, 'static'); P.newFixture(ground, P.newRectangleShape(400, 20), 1)
    local ball = P.newBody(g, 0, 0, 'dynamic'); local bf = P.newFixture(ball, P.newCircleShape(10), 1)
    bf:setRestitution(0.2); ball:setUserData('ball')
    local began, ended, post = 0, 0, 0
    g:setCallbacks(function(a, c, contact) began = began + 1 end, function() ended = ended + 1 end, nil,
        function(a, c, contact, n) post = post + 1 end)
    for _ = 1, 120 do g:update(1 / 60) end
    T.check(began >= 1 and post >= 1, 'begin/post-solve callbacks fire')
    T.check(ball:getY() < 200 and ball:getY() > 150, 'ball rests on ground')
    T.check(#ball:getContacts() >= 1, 'body contacts listed')
    T.check(ball:getFixtures()[1] == bf and bf:getBody() == ball, 'registry round trip')
    T.check(bf:getShape():getType() == 'circle', 'shape type')

    -- errors in callbacks surface after the step
    local e = P.newWorld(0, 300, true)
    local eg = P.newBody(e, 0, 50, 'static'); P.newFixture(eg, P.newRectangleShape(400, 20), 1)
    local eb = P.newBody(e, 0, 0, 'dynamic'); P.newFixture(eb, P.newCircleShape(10), 1)
    e:setCallbacks(function() error('boom') end)
    local ok, err = pcall(function() for _ = 1, 120 do e:update(1 / 60) end end)
    T.check(not ok and tostring(err):find('boom'), 'callback error is rethrown')

    -- destroyed objects and locked world
    local d = P.newBody(w, 5, 5, 'dynamic'); local df = P.newFixture(d, P.newCircleShape(5), 1)
    d:destroy()
    T.check(d:isDestroyed() and df:isDestroyed(), 'destroy marks body and fixtures')
    T.check(not pcall(d.getPosition, d), 'destroyed body errors')

    -- joints
    local jw = P.newWorld(0, 0, true)
    local j1 = P.newBody(jw, 0, 0, 'static'); local j2 = P.newBody(jw, 50, 0, 'dynamic')
    P.newFixture(j2, P.newCircleShape(5), 1)
    local rj = P.newRevoluteJoint(j1, j2, 0, 0)
    rj:setLimitsEnabled(true); rj:setLimits(-0.5, 0.5)
    T.check(rj:getType() == 'revolute' and near(rj:getUpperLimit(), 0.5), 'revolute limits')
    local pj = P.newPrismaticJoint(j1, j2, 0, 0, 1, 0)
    pj:setLimits(-30, 60)
    T.check(near(pj:getLowerLimit(), -30, 1e-2) and near(pj:getUpperLimit(), 60, 1e-2), 'prismatic limits in pixels')
    T.check(#j2:getJoints() == 2 and jw:getJointCount() == 2, 'joint bookkeeping')
    rj:destroy()
    T.check(#j2:getJoints() == 1, 'joint destroy updates bodies')

    -- ray cast + query
    local qw = P.newWorld(0, 0, true)
    local qb = P.newBody(qw, 100, 0, 'static'); P.newFixture(qb, P.newRectangleShape(20, 20), 1)
    local hit
    qw:rayCast(0, 0, 200, 0, function(f, x, y, nx, ny, frac) hit = x; return 0 end)
    T.check(hit and near(hit, 90, 0.1), 'ray cast hit point in pixels')
    local found = 0
    qw:queryBoundingBox(80, -20, 120, 20, function() found = found + 1 return true end)
    T.check(found == 1, 'bounding box query')

    -- polygon validation
    T.check(not pcall(P.newPolygonShape, 0, 0, 10, 0), 'degenerate polygon rejected')
    local poly = P.newPolygonShape(0, 0, 20, 0, 20, 20, 0, 20)
    T.check(poly:getVertexCount() == 4, 'polygon vertex count')
end
