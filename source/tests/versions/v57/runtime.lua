local R = {}
R.__index = R

function R.new(manager)
    return setmetatable({ manager = manager, frame = 0, count = 0 }, R)
end

function R:check(ok, msg)
    assert(ok, msg)
    self.count = self.count + 1
    print('PASS v57 ' .. msg)
end

function R:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        katsa.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, 'particles')
        assert(scene, err)
        self.scene = scene
        local world = scene.world
        local e = scene.demo.emitters[1]
        local system = world.particles
        self:check(
            world.root.className == 'World3D'
                and require('source.engine.nodes').getClass('RigidBody').name == 'Body3D',
            'Canonical 3D node names and migration aliases resolve'
        )
        e:clear()
        e.rate = 0
        e.speed = { 0, 0 }
        e.lifetime = { 4, 4 }
        e.drag = 0
        e.gravityScale = 0
        e.acceleration = { 0, 0, 0 }
        e.simulationSpace = 'World'
        e:emit(1)
        local p = e.particles[1]
        local x = p.x
        e.parent.position[1] = e.parent.position[1] + 25
        system:update(1 / 60)
        self:check(
            math.abs(p.x - x) < 0.001,
            'Emitted world particles do not move with their parent'
        )
        e:clear()
        e.simulationSpace = 'Local'
        e:emit(1)
        p = e.particles[1]
        x = e:pointToWorldSpace({ p.x, p.y, p.z })[1]
        e.parent.position[1] = e.parent.position[1] + 25
        self:check(
            math.abs(e:pointToWorldSpace({ p.x, p.y, p.z })[1] - x - 25) < 0.001,
            'Local particles retain their support frame'
        )
        e.simulationSpace = 'World'
        e:clear()
        e.gravityScale = 1
        e:emit(1)
        system:update(1 / 60)
        self:check(e.particles[1].vy < 0, 'Gravity multiplier accelerates particles downward')
        e:clear()
        e.gravityScale = 0
        e.attractionEnabled = true
        e:emit(1)
        p = e.particles[1]
        e.attractionPoint = { p.x + 20, p.y, p.z }
        system:update(1 / 60)
        self:check(p.vx > 0, 'Point attraction applies force toward its world target')
        e.attractionEnabled = false
        e:clear()
        e.quality = 'Low'
        self:check(
            e:emit(1000) == 128 and #e.particles == 128,
            'Burst obeys profile and emitter limits'
        )
        e.enabled = false
        local age = e.particles[1].age
        system:update(1 / 60)
        self:check(e.particles[1].age > age, 'Disabled emitter drains existing particles')
        e.disabledBehavior = 'Clear'
        system:update(1 / 60)
        self:check(e.liveCount == 0, 'Clear disable policy removes existing particles')
        e.disabledBehavior = 'Drain'
        e.enabled = true
        e.maxParticles = 1
        local pool = e.pool[#e.pool]
        e:emit(1)
        self:check(e.particles[1] == pool, 'Expired/cleared particle records are reused')
        local Props = require('source.engine.editor.inspectors.properties')
        local bad
        for _, field in ipairs(Props.list(e)) do
            if field.key == 'lifetime' then
                bad = field
            end
        end
        local ok = Props.set(scene, e, bad, '0', 1)
        self:check(
            not ok and e.lifetime[1] == 4,
            'Inspector rejects invalid lifetime and restores the previous value'
        )
        for _, shape in ipairs({ 'Point', 'Box', 'Sphere', 'Disc', 'Cylinder' }) do
            e.shape = shape
            e:clear()
            e:emit(1)
            self:check(e.particles[1].x == e.particles[1].x, 'Finite spawn for ' .. shape)
        end
        system.collisionBudget = 2
        for _, emitter in ipairs(scene.demo.emitters) do
            emitter.collisionEnabled = true
            emitter:emit(10)
        end
        system:update(0.1)
        self:check(
            system.stats.collisionQueries <= 2,
            'Collision query cost stays within the shared update budget'
        )
        system.collisionBudget = 64
        local temp = world:create('ParticleEmitter3D', { name = 'CleanupEmitter' }, e.parent)
        temp:emit(2)
        local n = #system.emitters
        temp:destroy()
        self:check(
            #system.emitters == n - 1 and temp.liveCount == 0,
            'Destroy removes emitter registration, particles and signals'
        )
        for _, emitter in ipairs(scene.demo.emitters) do
            scene.demo:restorePreset(emitter)
        end
        for i = 1, 90 do
            scene:update(1 / 60, 1 / 60)
        end
        scene.demo.panel.visible = false
        self.capture = 'particles'
    elseif self.frame == 2 then
        self:check(
            self.scene.world.particles.stats.drawCalls > 0
                and self.scene.world.particles.stats.rendered > 0,
            'Particle meshes render with the real depth canvas and atlas shader'
        )
        self.scene.demo.emitters[2].blendMode = 'Multiply'
        self.scene.demo.emitters[3].orientation = 'Axes'
    elseif self.frame == 3 then
        local scene, err =
            self.manager:switch(require('source.game.runtime.game').new, 'nightPlayer')
        assert(scene, err)
        self.scene = scene
        local rig = scene.demo.firstController
        for _, yaw in ipairs({ 89, 91, 135, 179, 181, 225, 270, 359, 450, -135 }) do
            rig.yaw = yaw
            rig.pitch = 25
            rig:update(0, true)
            local forward = scene.camera.forward
            local expected = math.rad(yaw)
            local cosine = math.cos(math.rad(25))
            self:check(
                math.abs(forward[1] - math.sin(expected) * cosine) < 0.001
                    and scene.camera.up[2] > 0.8,
                'Upright follow camera at yaw ' .. yaw
            )
        end
        scene.demo.thirdController.pitch, scene.demo.thirdController.yaw = rig.pitch, rig.yaw
        for i = 1, 6 do
            scene.camera =
                scene.world:setCamera(i % 2 == 0 and scene.demo.first or scene.demo.third, 0.25)
            scene:update(0.016, 0.016)
        end
        for i = 1, 30 do
            scene:update(1 / 60, 1 / 60)
        end
        self:check(
            scene.camera.up[2] > 0.8,
            'Interrupted camera transitions retain upright orientation'
        )
        self:check(
            scene.demo.interactCube:findByType('ClickDetector3D') ~= nil,
            'Night Player has an explicit Interact target'
        )
        local eye, cube =
            scene.demo.head:getWorldPosition(), scene.demo.interactCube:getWorldPosition()
        local dx, dy, dz = cube[1] - eye[1], cube[2] - eye[2], cube[3] - eye[3]
        scene.camera = scene.world:setCamera(scene.demo.first)
        rig.pitch = math.deg(math.atan2(dy, math.sqrt(dx * dx + dz * dz)))
        rig.yaw = math.deg(math.atan2(dx, dz))
        rig:update(0, true)
        scene.renderer:prepare(scene.world, scene.camera, scene.time)
        local enabled = scene.demo.flashlight.enabled
        scene.input:trigger('Interact')
        scene.input:update(0)
        self:check(
            scene.demo.flashlight.enabled ~= enabled,
            'Real Interact action ray toggles the aimed orange cube flashlight'
        )
        local row
        for _, child in
            ipairs(require('source.engine.editor.tree.traversal').children(scene.demo.player))
        do
            if child.className == 'Body3D' then
                row = child
            end
        end
        scene.workspace:select(scene.demo.player)
        scene.workspace:select(row)
        self:check(
            scene.workspace.parentPathText == nil and #scene.workspace.fields > 0,
            'Renamed virtual Body3D remains editable without stale Parent state'
        )
    elseif self.frame == 4 then
        local scene, err =
            self.manager:switch(require('source.game.runtime.game').new, 'surfaceGallery')
        assert(scene, err)
        self:check(
            scene.zone == 'surfaceGallery',
            'Existing world UI scene loads after 3D type migration'
        )
    elseif self.frame == 5 then
        self:check(
            #self.manager.journal.entries == 0,
            'Changed scenes leave the error journal empty'
        )
        print('PASSED ' .. self.count .. ' targeted v57 checks')
        katsa.event.quit()
    end
end

function R:draw()
    if not self.capture then
        return
    end
    local name = self.capture
    self.capture = nil
    katsa.graphics.captureScreenshot(function(image)
        local data = image:encode('png')
        local file =
            io.open(katsa.filesystem.getSource() .. '/docs/previews/v57/' .. name .. '.png', 'wb')
        if file then
            file:write(data:getString())
            file:close()
        end
        data:release()
        image:release()
    end)
end

return R
