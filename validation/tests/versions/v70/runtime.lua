local T = {}
T.__index = T

function T.new(manager)
    katsa.errorhandler = function(err)
        print('FAILED v70 ' .. tostring(err))
        return function()
            return 1
        end
    end
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager, frame = 0, count = 0 }, T)
end

function T:check(ok, label)
    assert(ok, label)
    self.count = self.count + 1
    print('PASS v70 ' .. label)
end

function T:load(route)
    local scene, err = self.manager:switch(require('source.game.runtime.game').new, route)
    assert(scene, err)
    self.scene = scene
    return scene
end

function T:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        local scene = self:load('animationPhysicsLab')
        scene:update(1 / 60, 1 / 60)
        self:check(#scene.demo.constraints == 10, 'Ten attachment constraint nodes mount')
        self:check(
            scene.demo.handRope and scene.demo.handRope.status == 'Active',
            'Animated bone attachment drives a physical rope endpoint'
        )
        for _, constraint in ipairs(scene.demo.constraints) do
            self:check(constraint.status == 'Active', 'Constraint active: ' .. constraint.className)
        end
        local body = scene.world:create(
            'Body3D',
            { name = 'SourceColliderBody', bodyType = 'Static', position = { 200, 30, 0 } }
        )
        local root =
            scene.world:create('Node3D', { name = 'GeometryParts', rotation = { 0, 25, 0 } }, body)
        local cube = scene.world:create(
            'Mesh3D',
            { name = 'ColliderCube', position = { 10, 0, 0 }, size = { 10, 12, 14 } },
            root
        )
        local second = scene.world:create(
            'Mesh3D',
            { name = 'ColliderCube2', position = { -15, 5, 0 }, size = { 8, 8, 8 } },
            root
        )
        local collider = scene.world:create(
            'Collider3D',
            { shape = 'Geometry', geometrySource = root, collisionLevel = 'Simple' },
            body
        )
        body:update(0)
        self:check(
            #body.body.shapes == 2,
            'Simple geometry collision includes both transformed model parts'
        )
        collider.collisionLevel = 'Convex'
        body:update(0)
        self:check(#body.body.shapes == 2, 'Convex geometry collision keeps separate mesh hulls')
        collider.collisionLevel = 'Detailed'
        body:update(0)
        self:check(
            #body.body.shapes == 24,
            'Detailed geometry collision includes all source triangles'
        )
        local before = body._colliderSignature
        cube.position[1] = 20
        body:update(0)
        self:check(
            body._colliderSignature ~= before,
            'Changing model transforms rebuilds geometry collider'
        )
        local Properties = require('source.engine.editor.inspectors.properties')
        for _, field in ipairs(Properties.list(cube)) do
            assert(field.key ~= 'shadowRevision', 'Internal ShadowRevision leaked')
        end
        self:check(true, 'ShadowRevision is hidden from public properties')
        local walk = scene.demo.tracks.walk
        local wave = scene.demo.tracks.wave
        wave:stop(0)
        wave:play(0.5)
        local weight = wave._blendWeight
        scene.world:updateNodes(0.1)
        self:check(
            wave._blendWeight > weight and wave._blendWeight < 1,
            'Animation FadeIn changes blend weight gradually'
        )
        wave:stop(0.5)
        weight = wave._blendWeight
        scene.world:updateNodes(0.1)
        self:check(
            wave._blendWeight < weight and wave.state == 'Fading',
            'Animation FadeOut remains smooth'
        )
        walk.order = 3
        walk.speed = 2
        local time = walk.timePosition
        scene.world:updateNodes(0.05)
        self:check(
            math.abs(walk.timePosition - time - 0.1) < 0.001,
            'Live animation Order and Speed are accepted'
        )
        self:check(
            scene.demo.tracks.idle.order == 0 and scene.demo.tracks.walk.order == 3,
            'Prepared animation tracks expose Order'
        )
        local joint = scene.demo.constraints[2]
        local old = joint.joint
        joint.enabled = false
        scene.physics:update(1 / 60)
        self:check(
            not joint.joint and joint.status == 'Disabled',
            'Disabling a constraint releases its backend joint'
        )
        joint.enabled = true
        scene.physics:update(1 / 60)
        self:check(
            joint.joint and joint.joint ~= old,
            'Re-enabling a constraint rebuilds its backend joint'
        )
        scene.world.environment.shadows.strength = 0.35
        scene.debugOverlay._syncDebug()
        local labels = scene.debugOverlay:getDescendants()
        local synced = false
        for _, label in ipairs(labels) do
            if label.text == 'Shadow strength 0.35' then
                synced = true
            end
        end
        self:check(synced, 'Debug sliders show current values immediately')
        local fields = Properties.list(collider)
        local sources = 0
        for _, field in ipairs(fields) do
            if field.key == 'geometrySource' then
                sources = sources + 1
                assert(field.kind == 'node')
            end
        end
        self:check(sources == 1, 'GeometrySource uses one selectable node field')
        local shader = scene.world:create('Shader3D', { name = 'OrderingTest', zIndex = 7 })
        self:check(
            shader.ZIndex == 7 and shader.order == nil,
            'Shader3D uses ZIndex without a duplicate Order'
        )
    elseif self.frame == 2 then
        local physicsScene = self.scene
        local rolling = physicsScene.world.root:find('RollingBall1', true)
        local startZ = rolling.position[3]
        for _ = 1, 120 do
            physicsScene:update(1 / 60)
        end
        self:check(rolling.position[3] > startZ + 1, 'Objects roll down the inclined physical ramp')
        for _, body in ipairs(physicsScene.physics.bodies) do
            for _, v in ipairs(body.object.position:toArray()) do
                assert(v == v and math.abs(v) < 100000, 'Unstable body pose')
            end
        end
        self:check(true, 'Constraint showcase remains finite during two seconds of simulation')
        local scene = self:load('particles')
        local emitter = scene.demo.emitter
        self:check(emitter.quality == nil, 'Particle Quality has been removed')
        emitter.rate = 120
        emitter.maxParticles = 500
        emitter:clear()
        scene.world.particles:update(1 / 60)
        self:check(emitter.liveCount <= 500, 'Rate and MaxParticles directly control births')
        local fields = require('source.engine.editor.inspectors.properties').list(emitter)
        local keys = {}
        for _, field in ipairs(fields) do
            keys[field.key] = true
        end
        self:check(
            keys.castShadow and keys.receiveShadow and keys.shadowGroup and not keys.quality,
            'Particle shadow and budget properties appear in Workspace'
        )
        local source = katsa.audio.newSource('assets/audio/effects/effectProbe.wav', 'static')
        local filter = {
            enabled = true,
            effectType = 'filter',
            filterType = 'lowpass',
            volume = 1,
            lowgain = 1,
            highgain = 0.15,
        }
        require('source.engine.audio.effects.routing').apply(
            scene.audio,
            { enabled = true },
            { sources = { source } },
            { filter }
        )
        local settings = source:getFilter()
        self:check(
            filter.status == 'Applied' and settings and settings.type == 'lowpass',
            'Native Low-Pass filter applies successfully'
        )
        source:release()
    elseif self.frame == 3 then
        local scene = self:load('graphicsLab')
        self.graphics = scene
        self:check(
            scene.world.environment.render.renderDensity == 3
                and scene.world.environment.render.msaa == 8,
            'Graphics lab requests highest supported render quality'
        )
        scene:update(1 / 60, 1 / 60)
    elseif self.frame == 4 then
        self:check(
            #self.manager.journal.entries == 0,
            'Graphics, material and particle shadow shaders render'
        )
        local scene = self.graphics
        self:check(
            scene.demo.emitter._shadowProxy and scene.demo.emitter._shadowProxy.geometry.mesh,
            'Particles produce bounded shadow-caster geometry'
        )
        local proxy = scene.demo.emitter._shadowProxy
        scene.demo.emitter.castShadow = false
        scene.demo.emitter.receiveShadow = false
        require('source.engine.particles.shadows').prepare(scene.world, scene.camera)
        self:check(not proxy.geometry.mesh, 'Disabling particle shadows releases caster buffers')
        local shadows = scene.renderer.shadows
        local oldUpdate = shadows.update
        local calls = 0
        shadows.update = function(...)
            calls = calls + 1
            return oldUpdate(...)
        end
        scene.world.debug = { wireframe = true }
        scene.renderer:draw(scene.world, scene.camera, 0)
        self:check(calls == 0 and shadows.drawCalls == 0, 'Wireframe bypasses shadow generation')
        self:check(
            katsa.graphics.getShader() == nil,
            'Wireframe graphics state does not leak into UI'
        )
        shadows.update = oldUpdate
    elseif self.frame == 5 then
        local scene = self:load('shaderLab')
        self.shaderScene = scene
        scene.demo.preset = 'Clean'
        scene.demo:sync()
        scene.demo.preview.timeScale = 0
        scene.demo.original.timeScale = 0
    elseif self.frame == 6 then
        assert(self.clean, 'Clean screenshot was not captured')
        self.shaderScene.demo.preset = 'Pixel'
        self.shaderScene.demo:sync()
    elseif self.frame == 7 then
        local scene = self.shaderScene
        local data = scene.ui._sceneCanvas:newImageData()
        local node = scene.demo.pixel
        local difference = 0
        local samples = 0
        for y = math.floor(node._y) + 4, math.floor(node._y + node._height) - 4, 7 do
            for x = math.floor(node._x) + 4, math.floor(node._x + node._width) - 4, 7 do
                local a, b, c = self.clean:getPixel(x, y)
                local d, e, f = data:getPixel(x, y)
                difference = difference + math.abs(a - d) + math.abs(b - e) + math.abs(c - f)
                samples = samples + 1
            end
        end
        print('PIXEL DIFFERENCE', difference / samples)
        self:check(
            difference / samples > 0.01,
            'Pixel effect visibly changes rendered viewport pixels'
        )
        data:release()
        scene.demo.preset = 'CRT'
        scene.demo:sync()
    elseif self.frame == 8 then
        local scene = self.shaderScene
        local data = scene.ui._sceneCanvas:newImageData()
        local node = scene.demo.tv
        local difference, samples = 0, 0
        for y = math.floor(node._y) + 4, math.floor(node._y + node._height) - 4, 7 do
            for x = math.floor(node._x) + 4, math.floor(node._x + node._width) - 4, 7 do
                local a, b, c = self.clean:getPixel(x, y)
                local d, e, f = data:getPixel(x, y)
                difference = difference + math.abs(a - d) + math.abs(b - e) + math.abs(c - f)
                samples = samples + 1
            end
        end
        self:check(
            difference / samples > 0.005,
            'CRT effect visibly changes rendered viewport pixels'
        )
        data:release()
        self.clean:release()
        self:check(
            #self.manager.journal.entries == 0,
            'CRT and suppression effects render without errors'
        )
        local menu = assert(self.manager:switch(require('source.game.runtime.menu').new))
        menu.rebuildCategory('Physics')
        local list = menu.ui:find('LevelList', true)
        self:check(#list.children > 0 and #list.children < 10, 'Menu category filters scene list')
        local scroll = menu.ui:scroll({
            scrollBarThickness = 10,
            scrollBarImageColor3 = { 1, 0, 0 },
            scrollBarImageTransparency = 0.2,
            verticalScrollBarPosition = 'Left',
            clip = false,
            length = 1000,
            size = { 0, 100, 0, 80 },
        }, menu.ui.content)
        self:check(
            scroll.clip == false and scroll.scrollBarThickness == 10,
            'ScrollFrame supports custom scrollbar and optional clipping'
        )
        self:check(
            require('source.engine.nodes').getClass('BillboardUI').name == 'BillboardUI'
                and require('source.engine.nodes').getClass('SurfaceUI').name == 'SurfaceUI',
            'Spatial UI has consistent new class names'
        )
        print('PASSED ' .. self.count .. ' focused v70 checks')
        katsa.event.quit()
    end
end

function T:draw()
    if self.frame == 5 then
        katsa.graphics.captureScreenshot(function(data)
            self.clean = data
        end)
    end
    if self.frame == 1 or self.frame == 3 or self.frame == 7 then
        local name = ({
            [1] = 'animation-physics',
            [3] = 'maximum-graphics',
            [7] = 'shader-effects',
        })[self.frame]
        katsa.graphics.captureScreenshot(function(data)
            local blob = data:encode('png')
            local file = io.open(
                katsa.filesystem.getSource() .. '/docs/previews/v70/' .. name .. '.png',
                'wb'
            )
            if file then
                file:write(blob:getString())
                file:close()
            else
                -- Packaged archives cannot receive preview files.
                katsa.filesystem.write('v70-' .. name .. '.png', blob)
            end
            blob:release()
            data:release()
        end)
    end
end

return T
