return function(test)
    local function check(ok, msg)
        test:check(ok, msg)
    end
    local Resources = require('source.engine.core.resources')
    local r = Resources.new(require('source.game.data.manifest'))
    local child = r:scope()
    local image = r:image('white')
    check(child:image('white') == image, 'Resource scopes share the same texture')
    local linear = r:image('bricks')
    local pixels = child:imageVariant('bricks', true)
    check(pixels ~= linear, 'Pixel texture variant remains isolated')
    child:release()
    check(image:getWidth() > 0, 'Releasing one scope retains another owner texture')
    local models = require('source.engine.import.models')
    local a = models.load('assets/models/examples/animated.glb', r)
    local b = models.load('assets/models/examples/animated.glb', r)
    check(
        a ~= b and a.parts[1].geometry == b.parts[1].geometry and a.nodes ~= b.nodes,
        'Cached models share GPU geometry and isolate animation state'
    )
    a:play(1)
    a:update(0.1)
    check(b.time ~= a.time, 'Model animation playback state is independent')
    local count = 0
    for _ in pairs(r.store.entries) do
        count = count + 1
    end
    r:preload({
        { kind = 'image', path = 'white' },
        { kind = 'model', path = 'assets/models/examples/animated.glb' },
        { kind = 'sound', path = 'assets/audio/effects/click.wav' },
    })
    check(
        r.store.entries['model:assets/models/examples/animated.glb'] ~= nil,
        'Typed preload leases existing decoded model data'
    )
    check(not pcall(r.image, r, 'missing-v54.png'), 'Missing resource reports a loading error')
    local World3D = require('source.engine.world.world')
    local settings = require('source.game.data.settings').create()
    local world = World3D.new(r, settings)
    local obj = world:create(
        'Mesh3D',
        { name = 'CacheTest', size = { 2, 2, 2 }, position = { 0, 0, 20 }, texture = 'white' }
    )
    world:updateObject(obj)
    local normal = obj.normal
    local m = require('source.engine.math.math3d')
    local original = m.normalMatrix
    local recomputations = 0
    m.normalMatrix = function(...)
        recomputations = recomputations + 1
        return original(...)
    end
    for i = 1, 5 do
        world:updateObject(obj)
        world:updateObject(obj, true)
    end
    m.normalMatrix = original
    check(
        recomputations == 0 and normal == obj.normal,
        'Static simulation/render alternation no longer rebuilds derived matrices'
    )
    local camera = world:addCamera()
    world.layerGroups:add('Hidden')
    world.layerGroups:set('Default', 'Hidden', false)
    obj.layerGroup = 'Hidden'
    world:resolveLayerGroup(obj)
    world:resolveLayerGroup(camera)
    check(
        require('bit').band(obj.layers, camera.layers) == 0,
        'Named layer matrix excludes Hidden from Default cameras'
    )
    world.layerGroups:rename('Hidden', 'Secret')
    check(obj.layerGroup == 'Secret', 'Group rename updates member names')
    world.layerGroups:remove('Secret')
    check(obj.layerGroup == 'Default', 'Group deletion reassigns members safely')
    local Physics = require('source.engine.physics')
    local physics = Physics.new({ gravity = { 0, 0, 0 } })
    world.physics = physics
    physics:addGroup('Ghost')
    physics:setGroupsCollidable('Ghost', 'Default', false)
    local body = world:create(
        'Body3D',
        { name = 'Static', bodyType = 'Static', collisionGroup = 'Ghost', isTrigger = true }
    )
    check(
        body.physics.group == 'Ghost' and not physics.collisionGroups:interacts('Ghost', 'Default'),
        'Collision matrix is independent from visibility matrix'
    )
    local properties = require('source.engine.editor.inspectors.properties')

    local function field(node, key)
        for _, f in ipairs(properties.list(node)) do
            if f.key == key then
                return f
            end
        end
    end
    check(
        field(body, 'isTrigger')
            and field(body, 'friction')
            and field(body, 'restitution')
            and not field(body, 'gravityScale'),
        'Static inspector keeps surface response and hides dynamic-only settings'
    )
    body.physics:set({ type = 'Dynamic' })
    check(
        field(body, 'gravityScale') ~= nil,
        'Changing body mode updates conditional inspector fields'
    )
    physics.collisionGroups:rename('Ghost', 'Sensors')
    check(body.collisionGroup == 'Sensors', 'Collision group rename updates body properties')
    local UI = require('source.engine.ui')
    local ui = UI.new(320, 240, r)
    local scroll = ui:scroll({ size = { 0, 200, 0, 150 }, length = 500 }, ui.content)
    ui:layout()
    ui:pointer(scroll, 'press', 50, 100, 'finger')
    ui:pointer(scroll, 'hover', 50, 100, 'mouse')
    ui:pointer(scroll, 'leave', 50, 100, 'mouse')
    ui:pointer(scroll, 'move', 50, 50, 'finger')
    check(scroll.scrollY == 50, 'Hover/leave cannot cancel an active finger scroll')
    ui:pointer(scroll, 'press', 50, 80, 'other')
    ui:pointer(scroll, 'release', 50, 80, 'other')
    ui:pointer(scroll, 'move', 50, 30, 'finger')
    check(scroll.scrollY == 70, 'A second pointer cannot steal or release the scroll owner')
    ui:pointer(scroll, 'cancel', 0, 0, 'finger')
    check(scroll._scrollPointer == nil, 'Cancellation releases the scroll owner')
    local Controller = require('source.engine.cameras.controller')
    local target = world:create('Attachment3D', { name = 'CameraAnchor', position = { 0, 2, 20 } })
    local rig = Controller.new(camera, {
        mode = 'ThirdPerson',
        target = target,
        physics = physics,
        distance = 20,
        positionSmooth = 0,
    })
    rig:look(100, 10000)
    check(rig.pitch == rig.minPitch, 'Follow camera clamps pitch')
    rig:update(0.016)
    check(camera:getWorldPosition()[3] < 20, 'Third person camera follows an Attachment3D')
    local wall = world:create(
        'Body3D',
        { name = 'CameraWall', bodyType = 'Static', position = { 0, 4, 10 }, size = { 20, 20, 2 } }
    )
    physics:update(1 / 60)
    camera.rotation = { 0, 0, 0 }
    rig.pitch, rig.yaw = 0, 0
    rig.rotationSmooth = 0
    rig:update(0.016)
    check(
        camera.position[3] > 11 and camera.position[3] < 20,
        'Third-person radius probes keep the camera in front of a wall'
    )
    wall:destroy()
    rig:transitionTo({ 0, 4, 10 }, { 0, 10, 0 }, 0.1)
    rig:update(0.1)
    check(math.abs(camera.position[2] - 4) < 0.001, 'Camera3D transition reaches its destination')
    target:destroy()
    check(pcall(rig.update, rig, 0.016), 'Removing the follow target is safe')
    local Manager = require('source.engine.core.sceneManager')
    local manager = Manager.new()
    local released = 0

    local function factory()
        return {
            load = function() end,
            release = function()
                released = released + 1
            end,
        }
    end
    local old = manager:switch(factory)
    local failed, errorMessage = manager:switch(function()
        return {
            load = function()
                error('broken resource')
            end,
            release = function() end,
        }
    end)
    check(
        failed == nil
            and errorMessage:find('broken resource')
            and manager.stack[1] == old
            and released == 0,
        'Failed scene loading reports an error and preserves the running scene'
    )
    old.pointerreleased = function()
        manager:switch(factory)
        check(manager.stack[1] == old, 'Scene switch is deferred until input dispatch completes')
    end
    manager:dispatch('pointerreleased')
    check(
        manager.stack[1] ~= old and released == 1,
        'Deferred switch releases the previous scene exactly once'
    )
    manager:release()
    check(released == 2, 'Scene manager shutdown releases the final scene')
    physics:release()
    world:release()
    ui:release()
    r:release()
    check(next(r.store.entries) == nil, 'All model, texture and sound leases are released')
end
