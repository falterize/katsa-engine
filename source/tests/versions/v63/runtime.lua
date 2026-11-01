local Test = {}
Test.__index = Test

function Test.new(manager)
    katsa.errorhandler = function(message)
        print('FAILED v63 ' .. tostring(message))
        return function()
            katsa.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, frame = 0, count = 0 }, Test)
end

function Test:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v63 ' .. message)
end

function Test:load(zone)
    local scene, err = self.manager:switch(require('source.game.runtime.game').new, zone)
    assert(scene, err)
    self.scene = scene
    scene:update(0.016, 0.016)
    return scene
end

function Test:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        katsa.window.setMode(960, 540, { vsync = 0, stencil = 8, depth = 24 })
        local scene = self:load('animationLab')
        local ramp = scene.demo.ramp
        ramp.Playing = true
        scene.world:updateNodes(0.25)
        local pose = scene.demo.body.position[1]
        ramp.Enabled = false
        scene.world:updateNodes(0.25)
        self:check(
            ramp.Playing and scene.demo.body.position[1] == pose and ramp.track.elapsed > 0.25,
            'Disabled Ramp advances time without applying target properties'
        )
        ramp.Enabled = true
        self:check(
            scene.demo.body.position[1] ~= pose,
            'Re-enabling Ramp applies current timeline value immediately'
        )
        ramp.Playing = false
        local elapsed = ramp.track.elapsed
        scene.world:updateNodes(0.2)
        self:check(ramp.track.elapsed == elapsed, 'Playing false holds Ramp playback')
        ramp.Playing = true
        self:check(ramp.track.elapsed == 0, 'Playing true restarts Ramp from the beginning')
        local sound = scene.world:create(
            'Sound',
            { resource = 'assets/audio/ambient/ambient.wav', looped = true, playing = true }
        )
        sound.Enabled = false
        self:check(
            sound.Playing and sound._voice.volume == 0 and sound._voice.source:isPlaying(),
            'Sound Enabled mutes its running source without stopping'
        )
        sound.Enabled = true
        self:check(sound._voice.volume > 0, 'Sound Enabled restores gain immediately')
        sound.Playing = false
        self:check(
            sound.status == 'Paused' and not sound.Playing,
            'Sound Playing controls playback separately'
        )
        local scene = self:load('particles')
        local e = scene.demo.emitters[3]
        local system = scene.world.particles
        for _, emitter in ipairs(system.emitters) do
            emitter.rate = 0
            emitter:clear()
        end
        e:emit(1)
        local p = e.particles[1]
        p.x, p.y, p.z, p.vx, p.vy, p.vz, p.age, p.life = 0, 3, 70, 0, -100, 0, 0, 8
        e.gravityScale = 0
        e.drag = 0
        e.collisionEnabled = true
        system.collisionBudget = 0
        system:update(0.06)
        self:check(p.y < 0, 'Particle crosses floor during an intentionally deferred query')
        system.collisionBudget = 1
        system:update(0.02)
        self:check(
            p.y >= 0 and p.vy > 0,
            'Deferred particle collision checks the retained swept path and bounces'
        )
        scene.physics.collisionGroups:add('Particles')
        scene.physics.collisionGroups:set('Particles', 'Default', false)
        e.collisionGroup = 'Particles'
        p.x, p.y, p.z, p.vx, p.vy, p.vz = 0, 1, 70, 0, -100, 0
        p.collisionX, p.collisionY, p.collisionZ = nil, nil, nil
        system:update(0.02)
        self:check(p.y < 0 and p.vy < 0, 'Particle CollisionGroup exclusions prevent bounce')
        self.capture = 'particles'
    elseif self.frame == 2 then
        local scene = self:load('modelLab')
        local model = scene.demo.model
        self:check(
            model.root:isA('Node3D') and #model.skins == 2 and #model.skins[1].joints == 65,
            'XBot imports as named hierarchy with original skin joints'
        )
        self:check(
            model.root:find('Beta_Surface', true) and model.root:find('Beta_Joints', true),
            'Original multi-mesh names are accessible through the model tree'
        )
        self:check(
            #model.animations == 6 and scene.demo.attachment.parent:isA('Bone3D'),
            'Procedural states and bone Attachment are instantiated'
        )
        local skin = model.objects[1].skin
        local changed = false
        local before = {}
        for mi, m in ipairs(skin.matrices) do
            before[mi] = { unpack(m) }
        end
        scene:update(0.2, 0.2)
        for mi, m in ipairs(skin.matrices) do
            for i = 1, 16 do
                if before[mi][i] ~= m[i] then
                    changed = true
                end
            end
        end
        self:check(changed and #skin.palette <= 32, 'Animation updates a bounded GPU joint palette')
        local pose = require('source.engine.animation.skeleton.pose')
        local c = {
            target = 'translation',
            method = 'CUBICSPLINE',
            times = { { 0 }, { 1 } },
            values = {
                { 0, 0, 0 },
                { 0, 0, 0 },
                { 1, 0, 0 },
                { 1, 0, 0 },
                { 1, 0, 0 },
                { 0, 0, 0 },
            },
        }
        self:check(
            math.abs(pose.sample(c, 0.5)[1] - 0.5) < 1e-6,
            'glTF CUBICSPLINE tangents evaluate with segment duration'
        )
        local node = model.nodes[model.skins[1].joints[1] + 1]
        local clip = {
            name = 'Foreign',
            duration = 1,
            channels = {
                { node = { index = node.index }, target = 'rotation' },
            },
        }
        self:check(
            not pcall(model.animator.load, model.animator, clip),
            'Animation compatibility rejects foreign skeleton node references'
        )
        self:check(
            #scene.demo.multi.objects == 2 and #scene.demo.colliders == 2,
            'Cube and floating triangle share one asset with separate mesh bodies'
        )
        local root, ribbon = scene.world:loadModel(
            'assets/models/examples/skinRibbon.gltf',
            { name = 'Ribbon', position = { -110, 10, 50 }, scale = { 12, 12, 12 } }
        )
        local marker = false
        local track = ribbon.animator:load('Bend')
        track:connect('Marker:Quarter', function()
            marker = true
        end)
        track:play()
        scene.world:updateNodes(0.3)
        self:check(
            marker and ribbon.nodes[2].rotation[3] > 0,
            'External glTF skin animation and imported marker advance together'
        )
        local node = ribbon.nodes[2]
        local hold = {
            name = 'HoldTip',
            duration = 1,
            markers = {},
            channels = {
                {
                    node = node,
                    target = 'rotation',
                    times = { { 0 }, { 1 } },
                    values = { { 0, 0, 0, 1 }, { 0, 0, 0, 1 } },
                    method = 'LINEAR',
                },
            },
        }
        local overlay = ribbon.animator:load(hold)
        overlay.priority = 10
        overlay.boneMask = { TipBone = 1 }
        overlay:play()
        scene.world:updateNodes(0.08)
        self:check(
            math.abs(node.rotation[3]) < 1e-6,
            'Higher-priority bone mask overrides only its selected channel'
        )
        overlay.weight = 0.25
        scene.world:updateNodes(0.08)
        self:check(
            node.rotation[3] > 0,
            'Lower-priority animation fills remaining weight during blending'
        )
        overlay:stop()
        local rootClip = {
            name = 'RootMove',
            duration = 1,
            markers = {},
            channels = {
                {
                    node = ribbon.nodes[1],
                    target = 'translation',
                    times = { { 0 }, { 1 } },
                    values = { { 0, 0, 0 }, { 4, 0, 0 } },
                    method = 'LINEAR',
                },
            },
        }
        local movement = 0
        ribbon.animator.rootMotionEnabled = true
        ribbon.animator.rootMotionHandler = function(delta)
            movement = movement + delta[1]
        end
        local rootTrack = ribbon.animator:load(rootClip)
        rootTrack:play()
        scene.world:updateNodes(0.08)
        scene.world:updateNodes(0.08)
        self:check(
            movement > 0 and ribbon.nodes[1].translation[1] == 0,
            'Root motion emits movement through its explicit handler and removes duplicate bone motion'
        )
        rootTrack:stop()
        ribbon.animator.rootMotionEnabled = false
        self.capture = 'models'
    elseif self.frame == 3 then
        local scene = self.scene
        scene.demo.animator:transition('Demo Run', 0.2)
        scene:update(0.35, 0.35)
        self:check(
            scene.demo.track.state == 'Stopped',
            'Animation transition fades the previous track out'
        )
        self:check(
            scene.renderer.stats.objects > 0 and scene.world.lighting.shadows.enabled,
            'Skinned main and shadow shaders render the demonstration'
        )
        scene.demo.animator.tracks[#scene.demo.animator.tracks]:pause()
        scene.world:updateNodes(0.04)
        local revision = scene.demo.model.objects[1].shadowRevision
        scene.world:updateNodes(0.04)
        self:check(
            revision == scene.demo.model.objects[1].shadowRevision,
            'Paused skeleton does not repeatedly dirty its shadow geometry'
        )
        self.capture = 'transition'
    elseif self.frame == 4 then
        local scene = self:load('models')
        scene:update(0.1, 0.1)
        self:check(
            scene.model.legacyTrack.Playing,
            'Legacy rigid-node GLB example still plays through Animator'
        )
    elseif self.frame == 5 then
        self:load('collisionModels')
    elseif self.frame == 6 then
        self:load('audioNodes')
    elseif self.frame == 7 then
        self:check(
            #self.manager.journal.entries == 0,
            'Scene teardown and new systems leave no runtime errors'
        )
        print('PASSED ' .. self.count .. ' focused v63 checks')
        katsa.event.quit()
    end
end

function Test:draw()
    if not self.capture then
        return
    end
    local name = self.capture
    self.capture = nil
    katsa.graphics.captureScreenshot(function(image)
        local bytes = image:encode('png')
        local f = assert(
            io.open(katsa.filesystem.getSource() .. '/docs/previews/v63/' .. name .. '.png', 'wb')
        )
        f:write(bytes:getString())
        f:close()
        bytes:release()
        image:release()
    end)
end

return Test
