local R = {}
R.__index = R

function R.new(manager)
    return setmetatable({ manager = manager, frame = 0, count = 0 }, R)
end

function R:check(ok, msg)
    assert(ok, msg)
    self.count = self.count + 1
    print('PASS v59 ' .. msg)
end

function R:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        love.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, 'viewports')
        assert(scene, err)
        self.scene = scene
        local a, b = scene.demo.views[1], scene.demo.views[2]
        self:check(
            a.root.parent == a.frame and a.world ~= b.world and a.root._tree == a.world.nodeTree,
            'Viewport worlds retain independent ownership and update trees'
        )
        self:check(
            scene.ui.className == 'World2D' and scene.ui.parent == scene.world.root,
            'Main World2D belongs to World3D'
        )
        self:check(
            a.world.environment:isA('EnvironmentLighting')
                and a.world.lighting == a.world.environment
                and a.world.environment ~= b.world.environment,
            'Each World3D has its own EnvironmentLighting settings node'
        )
        self:check(
            not pcall(a.world.environment.destroy, a.world.environment),
            'Required EnvironmentLighting cannot be deleted alone'
        )
        a.root.currentCamera = a.second
        self:check(
            a.world.activeCamera == a.second and b.root.currentCamera == b.camera,
            'CurrentCamera assignment affects only its owning world'
        )
        self:check(
            not pcall(a.root.setCurrentCamera, a.root, b.camera),
            'Cross-world camera references are rejected'
        )
        local Properties = require('source.engine.editor.inspectors.properties')
        local field
        for _, f in ipairs(Properties.list(a.root)) do
            if f.key == 'currentCamera' then
                field = f
            end
        end
        self:check(
            field and field.kind == 'node' and Properties.set(scene, a.root, field, a.camera),
            'CurrentCamera uses the inspector node selector'
        )
        scene.world:setInteractionSource(scene.camera)
        local target = scene.world:create('Mesh3D', {
            name = 'ExternalTarget',
            position = { 0, 0, 30 },
            size = { 8, 8, 8 },
            texture = 'white',
        })
        local detector = scene.world:create(
            'ClickDetector3D',
            { name = 'ExternalDetector', adornee = target, radius = 100 },
            scene.world.folders.Scripts
        )
        self:check(
            detector:getTarget() == target and detector:canActivate(),
            'ClickDetector Adornee redirects its clicked target while source remains separate'
        )
        detector.adornee = nil
        self:check(
            not detector:canActivate(),
            'Clearing Adornee uses the valid Parent or disables targetless detectors'
        )
        detector.adornee = target
        target:destroy()
        self:check(
            not detector:canActivate(),
            'Destroyed ClickDetector Adornee cannot activate or silently retarget'
        )
        local anchor = a.root:create(
            'Attachment3D',
            { name = 'SeparateEmitterAnchor', position = { 45, 20, 25 } }
        )
        a.emitter.adornee = anchor
        a.emitter:clear()
        a.emitter.speed = { 0, 0 }
        a.emitter:emit(1)
        self:check(
            math.abs(a.emitter.particles[1].x - 15) < 0.001,
            'Particle Adornee transforms the emitter local offset independently of Parent'
        )
        anchor:destroy()
        self:check(
            a.emitter:emit(1) == 0,
            'Removed particle Adornee stops births until explicitly cleared'
        )
        a.emitter.adornee = nil
        a.emitter.speed = { 10, 20 }
        for i = 1, 30 do
            scene:update(1 / 60, 1 / 60)
        end
        self.capture = 'viewports'
    elseif self.frame == 2 then
        local a, b = self.scene.demo.views[1], self.scene.demo.views[2]
        self:check(
            a.world.renderer.canvas ~= b.world.renderer.canvas
                and a.world.renderer.width == a.frame._width,
            'Viewport render targets and sizes are independent of the window'
        )
        self:check(
            a.world.particles.stats.rendered > 0 and b.world.particles.stats.rendered > 0,
            'Particles render inside both independent worlds'
        )
        self:check(
            a.ui.width == a.world.renderer.width and a.ui.height == a.world.renderer.height,
            'World2D overlay resolves against its viewport target'
        )
        local button = a.ui.content.children[2]
        a.ui:layout()
        local x = (a.frame._x + button._x + button._width / 2) * self.scene.ui.scale
            + self.scene.ui.offsetX
        local y = (a.frame._y + button._y + button._height / 2) * self.scene.ui.scale
            + self.scene.ui.offsetY
        local before = a.root.currentCamera
        self.scene.input:press('viewport-ui', x, y)
        self.scene.input:release('viewport-ui', x, y)
        self:check(
            a.root.currentCamera ~= before and b.root.currentCamera == b.camera,
            'Actual viewport pointer routes to its inner UI camera button'
        )
        a.frame.renderScale = 0.5
        self.capture = 'viewports-second-frame'
    elseif self.frame == 3 then
        local a = self.scene.demo.views[1]
        self:check(
            a.world.renderer.width == math.ceil(a.frame._width * 0.5),
            'Viewport renderScale changes target dimensions'
        )
        local world = a.world
        local renderer = world.renderer
        a.frame:destroy()
        self:check(
            world.root.destroyed and world.resources.released and renderer.canvas == nil,
            'Removing ViewportFrame destroys its world and releases target/resources'
        )
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, 'particles')
        assert(scene, err)
        self.scene = scene
        scene.demo.selected = 3
        scene.demo.emitter = scene.demo.emitters[3]
        scene.demo.syncControls = true
        scene:update(1 / 60, 1 / 60)
        self:check(
            scene.demo.buttons.Enabled.text == 'Continuous: ON'
                and scene.demo.sliders.gravity.node.value == scene.demo.emitter.gravityScale,
            'Particle controls show the selected effect state and actual gravity multiplier'
        )
        scene.demo.buttons.Attraction.onPress()
        scene:update(1 / 60, 1 / 60)
        self:check(
            scene.demo.buttons.Attraction.text == 'Point attraction: ON',
            'Particle controls update state labels immediately'
        )
        self.capture = 'particle-controls'
    elseif self.frame == 4 then
        self:check(
            #self.manager.journal.entries == 0,
            'Viewport rendering, UI input and scene cleanup leave an empty error journal'
        )
        print('PASSED ' .. self.count .. ' targeted v59 checks')
        love.event.quit()
    end
end

function R:draw()
    if not self.capture then
        return
    end
    local name = self.capture
    self.capture = nil
    love.graphics.captureScreenshot(function(image)
        if name == 'viewports' then
            local r, g, b = image:getPixel(30, 430)
            self:check(
                b > 0.3 and g > 0.2,
                'Bottom-anchored viewport UI is visible after offscreen scissor restoration'
            )
        end
        local data = image:encode('png')
        local f =
            io.open(love.filesystem.getSource() .. '/docs/previews/v59/' .. name .. '.png', 'wb')
        if f then
            f:write(data:getString())
            f:close()
        end
        data:release()
        image:release()
    end)
end

return R
