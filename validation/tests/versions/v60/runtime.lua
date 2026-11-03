local Test = {}
Test.__index = Test

function Test.new(manager)
    katsa.errorhandler = function(message)
        print('FAILED v60 ' .. tostring(message))
        return function()
            katsa.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, frame = 0, count = 0 }, Test)
end

function Test:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v60 ' .. message)
end

function Test:load(zone)
    local scene, err = self.manager:switch(require('source.game.runtime.game').new, zone)
    assert(scene, err)
    self.scene = scene
    return scene
end

function Test:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        katsa.window.setMode(960, 540, { vsync = 0, stencil = 8, depth = 24 })
        local Sequence = require('source.engine.animation.sequence')
        self:check(
            Sequence.evaluate(Sequence.linear(0, 10), 0.5, 'Linear') == 5,
            'Linear sequence sampling'
        )
        local points = {
            { time = 0, value = 0, outgoing = { 0.2, 0 } },
            {
                time = 1,
                value = 1,
                incoming = { 0.8, 1 },
            },
        }
        self:check(
            math.abs(Sequence.evaluate(points, 0.5, 'Curve') - 0.5) < 0.001,
            'Bezier time inversion and handles'
        )
        local scene = self:load('animationLab')
        local ramp = scene.demo.ramp
        self:check(
            ramp.mode == 'Animated' and ramp.track == nil,
            'Prepared Ramp waits for explicit play'
        )
        local events = {}
        for _, event in ipairs({ 'Started', 'Stopped', 'Resumed' }) do
            ramp:connect(event, function()
                events[event] = true
            end)
        end
        ramp:play()
        scene:update(0.4, 0.4)
        local x = scene.demo.body.position[1]
        self:check(x > -35 and x < 35, 'Animated multi-property Ramp moves kinematic body')
        ramp:pause()
        scene:update(0.2, 0.2)
        self:check(scene.demo.body.position[1] == x, 'Pause holds animation pose')
        ramp:resume()
        ramp:stop()
        self:check(events.Started and events.Stopped and events.Resumed, 'Ramp lifecycle dispatch')
        ramp:play()
        scene.world.root.timeScale = 0
        scene:update(0.5, 0.5)
        self:check(scene.demo.body.position[1] == x, 'World TimeScale zero pauses simulation')
        scene.world.root.timeScale = 1
        scene:update(0.1, 0.1)
        scene.workspace:toggle(true)
        scene.workspace:select(ramp)
        local field
        for _, item in ipairs(require('source.engine.editor.inspectors.properties').list(ramp)) do
            if item.key == 'points' then
                field = item
            end
        end
        self:check(field and field.kind == 'sequence', 'Workspace exposes Ramp curve data')
        scene.workspace:openPopup(field)
        local graph = scene.workspace.popup.body.children[1]
        self:check(graph:isA('CurveEditor2D'), 'Workspace builds interactive curve widget')
        scene.ui:layout()
        local gx = (graph._x + graph._width * 0.5) * scene.ui.scale + scene.ui.offsetX
        local gy = (graph._y + graph._height * 0.5) * scene.ui.scale + scene.ui.offsetY
        scene.input:press('curve', gx, gy)
        scene.input:release('curve', gx, gy)
        self:check(#ramp.points == 3, 'Pointer inserts a serializable point on the Bezier curve')
        self:check(
            require('source.engine.animation.sequence').evaluate(ramp.points, 0.5, 'Curve') ~= nil,
            'Inserted curve remains valid'
        )
        scene.workspace.popup:close(true)
        scene.workspace:toggle(false)
        local visual = scene.world.byName.PlatformVisual
        local goal = scene.world:create(
            'Ramp',
            { mode = 'Animated', playbackTime = 0.1, goals = { position = { 5, 2, 0 } } },
            visual
        )
        local completed = false
        goal:connect('Completed', function()
            completed = true
        end)
        goal:play()
        scene.world:updateNodes(0.1)
        self:check(
            visual.position[1] == 5 and completed,
            'Prepared Ramp accepts a Tween-style goal table and completes'
        )
        self.capture = 'animation'
    elseif self.frame == 2 then
        local scene = self:load('shaderLab')
        local demo = scene.demo
        local resolver = require('source.engine.graphics.shaders.materialResolver')
        local defaultScope =
            scene.world:create('Shader3D', { name = 'DefaultWorldScope', enabled = false })
        self:check(defaultScope.parent == scene.world.root, 'Shader3D defaults to world scope')
        resolver.resolve(scene.world, demo.cube)
        self:check(
            #demo.cube._activeShaders == 2,
            'Hierarchical Shader3D stacks two material modifiers'
        )
        demo.pixel3D.enabled = true
        resolver.resolve(scene.world, demo.cube)
        self:check(
            #demo.cube._activeShaders == 2 and demo.cube._activeShaders[1] == demo.wave,
            'Higher Pixel suppresses Default while preserving Static'
        )
        self:check(
            demo.cube._systemEffects.shadows == false,
            'System shadow sampling follows assigned shader layer'
        )
        demo.pixel3D.enabled = false
        resolver.resolve(scene.world, demo.cube)
        self:check(
            demo.cube._activeShaders[1] == demo.default,
            'Disabling upper shader restores suppressed lower layer'
        )
        local emitter = scene.world:create(
            'ParticleEmitter3D',
            { name = 'ShaderParticles', rate = 10 },
            demo.cube.parent
        )
        resolver.resolve(scene.world, emitter)
        self:check(
            emitter._resolvedMaterial
                and emitter._resolvedMaterial.shader:hasUniform('multiplyMode'),
            'Shader3D material hooks compile for particle renderables'
        )
        local ui = scene.ui
        self.testBackground = ui:container({
            _viewportAuthored = true,
            position = { 0, 330, 0, 440 },
            size = { 0, 180, 0, 50 },
            zIndex = 70,
            backgroundColor = { 1, 0, 0 },
        }, ui.content)
        self.testEffect = ui:create('Shader2D', {
            _viewportAuthored = true,
            position = { 0, 330, 0, 440 },
            size = { 0, 90, 0, 50 },
            zIndex = 71,
            backgroundTransparency = 1,
            shaderPath = 'assets/shaders/examples/invert.glsl',
        }, ui.content)
        self.upperEffect = ui:create('Shader2D', {
            _viewportAuthored = true,
            position = { 0, 330, 0, 440 },
            size = { 0, 90, 0, 50 },
            zIndex = 72,
            shaderLayer = 'Pixel',
            backgroundTransparency = 1,
            shaderPath = 'assets/shaders/examples/identity.glsl',
        }, ui.content)
        self:check(
            not pcall(
                scene.world.addObject,
                scene.world,
                { name = 'LegacyMaterial', material = {} }
            ),
            'Direct Mesh3D material API is rejected'
        )
        scene:update(0.1, 0.1)
        self.capture = 'shaders'
    elseif self.frame == 3 then
        self.upperEffect.enabled = false
        local scene = self.scene
        local preview = scene.demo.preview._world
        self:check(
            preview.renderer and preview.renderer.stats.objects > 0,
            'Viewport descendants render through Shader2D'
        )
        local renderer = preview.renderer
        local frame = renderer.frame
        scene.demo.preview.currentCamera = nil
        scene:update(0.1, 0.1)
        self.capture = 'camera-free'
        self.renderer, self.rendererFrame = renderer, frame
    elseif self.frame == 4 then
        self:check(
            self.renderer.frame == self.rendererFrame,
            'No CurrentCamera skips all 3D render passes'
        )
        self:check(
            self.scene.demo.preview._world.uis[1].width > 0,
            'Camera-free viewport retains World2D overlay'
        )
        local scene = self:load('uiGallery')
        scene:update(0.1, 0.1)
        local component = require('source.engine.components.image')
        local source = 'assets/textures/ui/litter.png'
        local nearest =
            component.resolve(scene.resources, { pixelate = true }, source, scene.world.environment)
        local linear = component.resolve(
            scene.resources,
            { pixelate = false },
            source,
            scene.world.environment
        )
        self:check(
            nearest ~= linear
                and nearest:getFilter() == 'nearest'
                and linear:getFilter() == 'linear',
            'Pixelate variants are isolated'
        )
        scene.demo.fitImage.imageMode = 'Atlas'
        scene.demo.fitImage.atlasGrid = { 2, 2 }
        scene.demo.fitImage.atlasFrame = 1
        self.capture = 'images'
    elseif self.frame == 5 then
        local scene = self:load('particles')
        scene:update(0.1, 0.1)
        self:check(
            scene.demo.emitter.lifetimeRamp:isA('Ramp'),
            'Particle appearance uses shared lifetime Ramp'
        )
        self.capture = 'particles'
    elseif self.frame >= 6 and self.frame <= 18 then
        local zones = {
            'original',
            'models',
            'nightPlayer',
            'surfaceGallery',
            'audioNodes',
            'viewports',
            'combined',
            'physics',
            'collisionModels',
            'flyingAudio',
            'nodes',
            'shadows',
            'collisionBox',
        }
        local scene = self:load(zones[self.frame - 5])
        scene:update(0.016, 0.016)
        self:check(
            scene.ui.parent == scene.world.root,
            'Migrated scene ownership: ' .. zones[self.frame - 5]
        )
        self.capture = self.frame == 8 and 'night-player' or nil
    elseif self.frame == 19 then
        local scene, err = self.manager:switch(require('source.game.runtime.menu').new)
        assert(scene, err)
        self:check(
            scene.ui.parent == scene.world.root and scene.world.activeCamera == nil,
            'Menu has camera-free World3D -> World2D'
        )
        self:check(
            #self.manager.journal.entries == 0,
            'Scene transitions and cleanup leave empty journal'
        )
        print('PASSED ' .. self.count .. ' focused v60 checks')
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
        if name == 'shaders' then
            local r, g, b = image:getPixel(350, 460)
            local rr, gg, bb = image:getPixel(470, 460)
            self:check(
                r > 0.9 and g < 0.05 and b < 0.05 and rr > 0.9 and gg < 0.05,
                'Upper Shader2D suppresses lower effect only in its rectangle'
            )
        end
        if name == 'camera-free' then
            local r, g, b = image:getPixel(350, 460)
            self:check(
                r < 0.05 and g > 0.9 and b > 0.9,
                'Disabled upper Shader2D restores lower effect'
            )
        end
        local data = image:encode('png')
        local file =
            io.open(katsa.filesystem.getSource() .. '/docs/previews/v60/' .. name .. '.png', 'wb')
        if file then
            file:write(data:getString())
            file:close()
        end
        data:release()
        image:release()
    end)
end

return Test
