local Game = require('source.game.runtime.game')
local Application = require('source.game.runtime.application')

local Tests = {}
Tests.__index = Tests

local function frames(manager, count)
    for _ = 1, count do
        manager:update(1 / 60)
    end
end

local function capture(scene, name)
    local g = katsa.graphics
    scene.camera:update(g.getDimensions())
    local canvas = g.newCanvas(g.getWidth(), g.getHeight(), { dpiscale = 1 })
    g.push('all')
    g.setCanvas(canvas)
    g.clear(0, 0, 0, 1)
    local worldImage = scene.renderer:draw(scene.world, scene.camera, scene.time, true)
    g.setColor(1, 1, 1, 1)
    g.draw(worldImage)
    scene.ui.backgroundCanvas = worldImage
    scene.ui:draw()
    g.pop()
    local data = canvas:newImageData()
    local directory = os.getenv('KATSA_TEST_OUTPUT')
    if directory then
        local encoded = data:encode('png')
        local file = assert(io.open(directory .. '/' .. name .. '.png', 'wb'))
        file:write(encoded:getString())
        file:close()
        encoded:release()
    end
    data:release()
    canvas:release()
end

local function extendedDepth(tester, scene)
    local Mesh = require('source.engine.composition.mesh')
    scene.world.environment.render.msaa = 0
    for i = 1, 64 do
        Mesh.create(scene.world, {
            name = 'SkinDepthProbe' .. i,
            position = { (i - 1) % 8 * 0.15 - 0.6, 0.4, math.floor((i - 1) / 8) * 0.15 + 1 },
            size = { 0.08, 0.08, 0.08 },
        })
    end
    for i = 1, 3 do
        scene.world:create('PointLight3D', {
            name = 'SkinDepthLight' .. i,
            position = { i - 2, 2, 1 },
            range = 20,
            brightness = 0.1,
        })
    end
    scene.demo.orbit.distance = 4
    scene.demo.orbit:update()
    frames(scene.manager, 15)
    scene.camera:update(katsa.graphics.getDimensions())
    scene.world:invalidateRender()
    scene:draw()
    tester:check(
        scene.renderer.depthPrepassActive,
        'Extended skin participates in an active opaque depth prepass ('
            .. #scene.renderer.opaque
            .. ' opaque, '
            .. scene.renderer.lights.count
            .. ' lights)'
    )
    for _, object in ipairs(scene.demo.player.model.objects) do
        if object.geometry.eightWeights then
            assert(
                object.geometry.mesh:isAttributeEnabled('instanceRow1')
                    and object.geometry.mesh:isAttributeEnabled('instanceRow2'),
                'Depth prepass must not overwrite or detach extra weights'
            )
        end
    end
    tester:check(true, 'Depth prepass retains all eight skin influences')
end

Tests.extendedDepth = extendedDepth

function Tests.run(tester)
    local manager = tester.manager
    for _, backend in ipairs({ 'jolt', 'oimo' }) do
        local scene = assert(manager:switch(Game.new, 'stareShooter', {
            physicsBackend = backend,
            package = os.getenv('KATSA_STARE_SCENE'),
        }))
        local state = scene.demo
        local player, input = state.player, scene.input
        input.captureMouse = false
        katsa.mouse.setRelativeMode(false)
        frames(manager, 6)
        tester:check(
            player.fsm.name == 'idle' and player.grounded,
            backend
                .. ': player starts grounded and idle ('
                .. player.fsm.name
                .. ', y='
                .. player.body.node.position[2]
                .. ', vy='
                .. player.velocity[2]
                .. ', normal='
                .. tostring(player.rayHit.normal and player.rayHit.normal[2])
                .. ')'
        )
        tester:check(
            scene.physics.units == 1 and scene.physics.fixedDelta == 1 / 60,
            'Godot meter units and 60 Hz simulation are preserved'
        )
        tester:check(
            not state.retro.enabled and not scene.navigation.visible,
            'Original presentation hides test navigation and retro effect'
        )
        local clips, extended, weight = {}, 0, 0
        for _, clip in ipairs(player.model.animations) do
            clips[clip.name] = clip
        end
        tester:check(
            #player.model.animations == 6
                and math.abs(clips.Player_Jump.duration - 0.6) < 1e-6
                and math.abs(clips.Player_Idle.duration - 9.933333333) < 1e-5,
            'All source clips retain their authored durations, including trimmed jump keys'
        )
        for _, part in ipairs(player.model.parts) do
            if part.geometry.eightWeights then
                extended = extended + 1
                for _, vertex in ipairs(part.geometry.vertices) do
                    local total = 0
                    for i = 1, 4 do
                        total = total + vertex[12 + i] + vertex[20 + i]
                        weight = math.max(weight, vertex[20 + i])
                    end
                    assert(math.abs(total - 1) < 1e-5, 'Eight skin weights must normalize together')
                end
            end
        end
        tester:check(
            extended > 0 and weight > 0.1,
            'Original extra bone influences survive import and palette batching'
        )
        for _, object in ipairs(player.model.objects) do
            local exact, rendered = object:getWorldMatrix(), object:getRenderWorldMatrix()
            for i = 1, 16 do
                assert(
                    math.abs(exact[i] - rendered[i]) < 1e-5,
                    'Interpolated model descendants must retain their imported local pose'
                )
            end
        end
        tester:check(true, 'Physics interpolation preserves imported model scales and local poses')
        input:keypressed('w')
        frames(manager, 20)
        tester:check(
            player.fsm.name == 'walk' and math.abs(player.velocity[3] - 5) < 0.05,
            backend .. ': walk accelerates to 5 meters per second'
        )
        input:keypressed('lshift')
        frames(manager, 20)
        tester:check(
            player.fsm.name == 'run' and math.abs(player.velocity[3] - 8) < 0.05,
            backend .. ': sprint accelerates to 8 meters per second'
        )
        input:keypressed('c')
        frames(manager, 20)
        tester:check(
            player.fsm.name == 'crouch'
                and player.height == 1
                and math.abs(player.velocity[3] - 3.25) < 0.05,
            backend .. ': crouch resizes capsule and uses original movement speed'
        )
        tester:check(
            math.abs(player.body.node.position[2] - 1) < 0.04
                and math.abs(player.collider.position[2] + 0.5) < 1e-6,
            backend .. ': crouching keeps feet on the floor'
        )
        input:keypressed('space')
        frames(manager, 6)
        tester:check(
            player.fsm.name == 'crouch' and player.jumpSequence == 0,
            'Crouching does not allow jumping in the source FSM'
        )
        input:keyreleased('space')
        input:keyreleased('c')
        input:keyreleased('w')
        input:keyreleased('lshift')
        frames(manager, 20)
        tester:check(
            player.fsm.name == 'idle' and player.height == 2 and math.abs(player.velocity[3]) < 0.01,
            'Release returns to standing idle with friction'
        )
        input:keypressed('space')
        frames(manager, 1)
        input:keyreleased('space')
        tester:check(
            player.fsm.name == 'jump' and player.velocity[2] > 5.5,
            'Jump enters once with original impulse'
        )
        frames(manager, 17)
        tester:check(
            player.fsm.name == 'fall' and player.body.node.position[2] > 1.3,
            backend .. ': jump reaches its apex and changes to fall'
        )
        frames(manager, 50)
        tester:check(
            player.fsm.name == 'idle'
                and player.grounded
                and math.abs(player.body.node.position[2] - 1) < 0.04,
            backend .. ': fall lands without sinking'
        )
        state.orbit:look(360, 48)
        input:keypressed('q')
        input:keypressed('s')
        frames(manager, 30)
        tester:check(
            math.abs(state.orbit.yaw - 90) < 1e-6
                and state.orbit.pitch == -12
                and player.walkScale < 0,
            'Mouse sensitivity, held Q and backward animation direction match the source'
        )
        input:keyreleased('q')
        input:keyreleased('s')
        input:wheelmoved(0, -4)
        frames(manager, 1)
        tester:check(
            state.orbit.distance == 4,
            'Wheel zoom uses one-meter steps through the scene input hook'
        )
        state.orbit:zoom(-1000)
        tester:check(state.orbit.distance == 100, 'Zoom out clamps to the original maximum')
        state.orbit:zoom(1000)
        tester:check(
            state.orbit.distance == 0,
            'Zoom in restores original first-person start distance'
        )
        scene.showStats = true
        tester:check(
            not input:wheelmoved(0, -4),
            'Stats panel retains wheel input instead of zooming the camera'
        )
        frames(manager, 1)
        tester:check(
            not player.input.jump and player.input.x == 0,
            'Inspecting stats suspends character input'
        )
        scene.showStats = false
        input:reset()
        frames(manager, 20)
        local rootY = player.body.node.position[2]
        scene.systems:setEnabled('simulation', false)
        input:keypressed('space')
        frames(manager, 10)
        tester:check(
            player.body.node.position[2] == rootY,
            'Disabling the scene simulation system freezes physics'
        )
        scene.systems:setEnabled('simulation', true)
        input:reset()
        player.body:teleport({ 0, 1, 0 })
        player.body:setVelocity({ 0, 0, 0 })
        state.orbit.yaw, state.orbit.pitch = 0, -12
        player.cameraYaw, player.visualYaw = 0, math.pi
        frames(manager, 60)
        state.orbit.distance = 4
        state.orbit:update()
        scene:draw()
        if backend == 'jolt' then
            capture(scene, 'stare-shooter-third-person')
            state.retro.enabled = true
            capture(scene, 'stare-shooter-retro')
            state.retro.enabled = false
            scene.world.debug.wireframe = true
            capture(scene, 'stare-shooter-wireframe')
            scene.world.debug.wireframe = false
            state.orbit.distance = 0
            state.orbit:update()
            capture(scene, 'stare-shooter-first-person')
        end
        local intact = true
        for _, object in ipairs(player.model.objects) do
            if object.geometry.eightWeights then
                intact = intact
                    and object.geometry.mesh:isAttributeEnabled('instanceRow1')
                    and object.geometry.mesh:isAttributeEnabled('instanceRow2')
                    and not scene.renderer.batches.attached[object.geometry.mesh]
            end
        end
        tester:check(intact, 'Main and shadow passes preserve extended skin vertex attributes')
        tester:check(
            player.model.animator.tracks[2].clip == clips.Player_Walk,
            'The original walk clip drives locomotion'
        )
        if backend == 'jolt' then
            extendedDepth(tester, scene)
        end
        local package = scene.package
        assert(manager:switch(Application.new, 'menu'))
        tester:check(
            package.references == 0 and not katsa.mouse.getRelativeMode(),
            'Leaving the scene releases assets and captured mouse'
        )
    end
end

function Tests.new(manager)
    katsa.errorhandler = function(message)
        print('FAILED Stare Shooter ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable({ manager = manager, count = 0 }, Tests)
end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS Stare Shooter', label)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    Tests.run(self)
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' Stare Shooter checks')
    katsa.event.quit()
end

return Tests
