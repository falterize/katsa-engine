local World = require('source.engine.world.world')
local Mesh = require('source.engine.composition.mesh')

local Tests = {}

function Tests.run(tester)
    local _, ui, physics, body, release = tester:environment()
    local custom = body(0, 0, 'Static')
    local collider = ui:create('Collider2D', {
        shape = 'Polygon',
        points = {
            { 0, 0 },
            { 40, 0 },
            { 40, 10 },
            { 10, 10 },
            { 10, 40 },
            { 0, 40 },
        },
    }, custom)
    physics:update(0)
    tester:check(
        #custom.body.fixtures > 1,
        'A concave manual polygon decomposes into convex fixtures'
    )
    tester:check(
        #physics:overlapPoint({ 5, 30 }) == 1 and #physics:overlapPoint({ 30, 30 }) == 0,
        'Manual polygon decomposition retains concave empty regions'
    )
    local first = custom.body.fixtures[1]
    collider.points[2][1], collider.points[3][1] = 60, 60
    physics:update(0)
    tester:check(
        first:isDestroyed() and #physics:overlapPoint({ 55, 5 }) == 1,
        'Editing a nested point table updates the collider'
    )
    custom:destroy()
    local image = body(0, 0, 'Static')
    local imageCollider = ui:create('Collider2D', {
        shape = 'Image',
        image = 'shared://textures/examples/colliderMask.png',
        size = { 32, 32 },
        collisionLevel = 'Detailed',
        imageResolution = 128,
    }, image)
    physics:update(0)
    tester:check(
        #image.body.fixtures > 1 and #physics:overlapPoint({ 0, 0 }) == 0,
        'Detailed image collision preserves transparent holes'
    )
    tester:check(
        #physics:overlapPoint({ -11, 0 }) == 1,
        'Opaque image pixels create collision regions'
    )
    local native = image.body.fixtures[1]
    for _ = 1, 5 do
        physics:update(0)
    end
    tester:check(
        image.body.fixtures[1] == native,
        'Image geometry is not rebuilt when inputs are unchanged'
    )
    imageCollider.collisionLevel = 'Simple'
    physics:update(0)
    tester:check(
        #image.body.fixtures == 1 and #physics:overlapPoint({ 0, 0 }) == 1,
        'Simple image collision uses the opaque bounding box'
    )
    imageCollider.collisionLevel = 'Convex'
    physics:update(0)
    tester:check(
        #physics:overlapPoint({ 0, 0 }) == 1,
        'Convex image collision closes holes with a hull'
    )
    imageCollider.collisionLevel, imageCollider.position, imageCollider.rotation =
        'Detailed', { 60, 0 }, 90
    physics:update(0)
    tester:check(
        #physics:overlapPoint({ 60, -11 }) == 1,
        'Image colliders honor local size, offset and rotation'
    )
    imageCollider.imageResolution = 4
    physics:update(0)
    tester:check(
        #image.body.fixtures > 0,
        'Image collision supports an explicit sampling resolution'
    )
    local chain = body(200, 0, 'Static', { shape = 'Chain', vertices = { -20, 0, 0, 30, 40, 30 } })
    tester:check(
        #physics:overlapCircle({ 230, 30 }, 2) == 1,
        'Exact overlap checks all chain segments, including those after child zero'
    )
    local solid = body(600, 100, 'Static')
    local actor = body(600, 100)
    local solidExits, sensorEnters = 0, 0
    solid:connect('collisionExit', function()
        solidExits = solidExits + 1
    end)
    solid:connect('triggerEnter', function()
        sensorEnters = sensorEnters + 1
    end)
    physics:update(1 / 60)
    solid.isTrigger = true
    physics:update(1 / 60)
    tester:check(
        solidExits == 1 and sensorEnters == 1,
        'Changing a live solid to a sensor retires the solid channel and enters the trigger channel'
    )
    actor:destroy()
    solid:destroy()
    local camera = ui:create('Camera2D', { position = { 640, 360 } })
    local _, h0 = camera:getVisibleSize(1280, 720)
    camera.fieldOfView = 90
    local _, h1 = camera:getVisibleSize(1280, 720)
    tester:check(h1 > h0, 'A wider Camera2D field of view shows a larger world area')
    local fov = camera.fieldOfView
    camera:setFocalLength(camera:getFocalLength())
    tester:check(
        math.abs(camera.fieldOfView - fov) < 0.00001,
        'FOV and focal-length conversion use the same projection'
    )
    tester:check(camera.followSmooth == nil, 'Camera2D has no built-in follow smoothing')
    local x, y = camera:worldToScreen(200, 350, 1280, 720)
    x, y = camera:screenToWorld(x, y, 1280, 720)
    tester:check(
        math.abs(x - 200) < 0.00001 and math.abs(y - 350) < 0.00001,
        'Pointer conversions remain correct after changing FOV'
    )
    local timed = body(400, 400)
    timed.body:setVelocity({ 60, 0 })
    ui:update(1, 0)
    tester:check(timed.position[1] == 400, 'UI wall time cannot advance paused 2D simulation')
    ui:update(1 / 60, 1 / 60)
    tester:check(
        math.abs(timed.position[1] - 401) < 0.01,
        'UI accepts a separate scaled simulation delta'
    )
    ui.autoUpdatePhysics = false
    ui:update(1 / 60, 1 / 60)
    tester:check(
        math.abs(timed.position[1] - 401) < 0.01,
        'Explicit scene systems can disable automatic 2D stepping'
    )
    release()

    for _, backend in ipairs({ 'oimo', 'jolt' }) do
        local resources = tester.manager.resources:scope()
        local world = World.new(resources)
        world:createPhysics({ backend = backend, gravity = { 0, 0, 0 } })
        local owner = world:create('Body3D', { bodyType = 'Static', position = { 10, 20, 30 } })
        local mesh = Mesh.create(
            world,
            { name = 'ExtractionSource', position = { 2, 0, 0 }, size = { 4, 2, 2 } },
            owner
        )
        local collider3D = world:create('Collider3D', { collisionLevel = 'Single Convex' }, owner)
        local originalX = mesh.geometry.vertices[1][1]
        local points, indices = collider3D:getPointsFromMesh(mesh)
        tester:check(
            #points == 8 and #indices == 36,
            backend .. ': mesh extraction welds cube vertices and retains topology'
        )
        points[1][1] = points[1][1] + 0.3
        tester:check(
            mesh.geometry.vertices[1][1] == originalX,
            backend .. ': extracted points do not alias the source mesh'
        )
        collider3D:setPoints(points, indices)
        world:updateNodes(1 / 60)
        tester:check(
            collider3D.status == 'Ready' and #owner.body.shapes > 0,
            backend .. ': an edited point cloud creates a convex 3D collider'
        )
        local key = collider3D._descriptorKey
        collider3D.points[1][2] = collider3D.points[1][2] + 0.25
        world:updateNodes(1 / 60)
        tester:check(
            collider3D._descriptorKey ~= key and collider3D.status == 'Ready',
            backend .. ': in-place edits rebuild a manual 3D collider'
        )
        collider3D.collisionLevel = 'Trimesh'
        world:updateNodes(1 / 60)
        tester:check(
            collider3D.status == 'Ready' and #owner.body.shapes == 12,
            backend .. ': indexed manual points build static triangle collision'
        )
        collider3D.collisionLevel = 'Bounding Box'
        world:updateNodes(1 / 60)
        tester:check(
            collider3D.status == 'Ready' and #owner.body.shapes == 1,
            backend .. ': manual points support Bounding Box collision quality'
        )
        local meshPoints, meshIndices = mesh:getCollisionPoints(owner)
        tester:check(
            #meshPoints == 8 and #meshIndices == 36,
            backend .. ': meshes expose the same extraction API'
        )
        local pointsFromFacade = require('source.engine.physics.3d').extractMeshPoints(mesh, owner)
        tester:check(
            #pointsFromFacade == 8,
            backend .. ': the 3D physics facade exposes extraction'
        )
        local largeIndices = {}
        for i = 1, 12000 do
            largeIndices[i] = (i - 1) % #points + 1
        end
        collider3D:setPoints(points, largeIndices)
        tester:check(
            #collider3D.indices == 12000 and collider3D.indices ~= largeIndices,
            backend .. ': large topology tables copy without Lua vararg limits'
        )
        collider3D:setPointsFromMesh(mesh)
        tester:check(
            collider3D.shape == 'Points' and #collider3D.points == 8,
            backend .. ': setPointsFromMesh stores an editable local copy'
        )
        world:release()
        resources:release()
    end
end

return Tests
