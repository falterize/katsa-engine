local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(manager, shadowsOnly)
    return setmetatable(
        { manager = manager, frame = 0, report = {}, shadowsOnly = shadowsOnly },
        Runtime
    )
end

function Runtime:check(condition, message)
    assert(condition, message)
    self.report[#self.report + 1] = 'PASS ' .. message
    print('PASS ' .. message)
end

function Runtime:capture(name)
    katsa.graphics.captureScreenshot(function(image)
        image:encode(
            'png',
            'test' .. name:gsub('^%l', string.upper):gsub('[-_](%l)', string.upper) .. '.png'
        )
        image:release()
    end)
end

function Runtime:update()
    self.frame = self.frame + 1
    local m = self.manager
    local s = m.stack[#m.stack]
    if self.shadowsOnly then
        require('validation.tests.integration.shadows')(self)
        katsa.event.quit(0)
        return
    end
    if self.frame == 3 then
        self:check(#m.stack == 1, '2D menu loads')
        for _, path in ipairs({
            'assets/shaders/engine/world.glsl',
            'assets/shaders/engine/sky.glsl',
        }) do
            local code = katsa.filesystem.read(path)
            local vertex = path == 'assets/shaders/engine/world.glsl' and code
                or 'vec4 position(mat4 transformProjection, vec4 vertexPosition) { return transformProjection * vertexPosition; }'
            local valid, message = katsa.graphics.validateShader(true, code, vertex)
            self:check(
                valid,
                'GLES shader validation: ' .. path .. (valid and '' or ': ' .. message)
            )
        end
        self.screenshot = 'menu'
    elseif self.frame == 5 then
        s.ui:layout()
        local button = s.firstSceneButton
        local x, y = s.ui:position(button)
        x = x + button._width / 2
        y = y + button._height / 2
        m:dispatch('pointerpressed', 'test', x, y)
        m:dispatch('pointerreleased', 'test')
    elseif self.frame == 10 then
        self:check(s.zone == 'original', 'Menu button opens original scene')
        self:check(
            #s.world.objects == 7 and #s.world.lights == 15 and #s.world.billboards == 6,
            'v33 scene counts'
        )
        self:check(
            s.renderer.stats.objects > 0 and s.renderer.stats.lights > 0,
            'Visible GPU geometry and selected lights'
        )
        self:check(s.world.byName.Sphinx.size[2] == 150, 'Original Sphinx size override')
        require('validation.tests.integration.features')(self, s)
        require('validation.tests.integration.workspace')(self, s)
        require('validation.tests.integration.canvasGroups')(self, s)
        self.screenshot = 'original'
        local input = s.input
        input:press('joystick', 125, 570)
        input:press('camera', 900, 350)
        input:move('joystick', 165, 540, 40, -30)
        input:move('camera', 950, 360, 50, 10)
        self:check(
            input.joystickId == 'joystick' and input.cameraId == 'camera' and input.axisX > 0,
            'Independent multitouch captures'
        )
        input:release('camera')
        self:check(input.joystickId == 'joystick', 'Camera3D release preserves joystick')
        m:focus(false)
        self:check(input.joystickId == nil and input.axisX == 0, 'Focus loss resets input')
        m:focus(true)
        s.camera.position = { 0, 0, 0 }
        s.camera.rotation = { 0, 0, 0 }
    elseif self.frame == 11 then
        s.workspace:toggle(true)
        s.workspace:update(0.3)
        s.workspace:select(s.world.lights[1])
        self.screenshot = 'workspace'
    elseif self.frame == 12 then
        s.workspace:toggle(false)
        s.workspace:update(0.3)
    elseif self.frame == 13 then
        local b = s.boards.button
        local x = b.screenX
        local y = b.screenY - 4 / b.canvasSize[2] * b.screenHeight
        s.input:press('billboard', x, y)
        self:check(s.boards.moving.sizeMode == 'Screen', 'Interactive billboard switches size mode')
        self:check(s.input.cameraId == nil, 'BillboardUI press does not rotate camera')
        s.input:release('billboard')
        local depth = s.world.billboards[3]
        self:check(
            s.world:occluded(s.camera, depth.screenX, depth.screenY, depth.depth),
            'Depth billboard picking is occluded by stone cube'
        )
        s.demoAnimations = true
        s:playSound()
    elseif self.frame == 17 then
        s.camera.rotation = { 0, 180, 0 }
    elseif self.frame == 18 then
        self.screenshot = 'original-back'
    elseif self.frame == 20 then
        self:check(s.world.byName.SpinningCube.rotation[1] ~= 0, 'Object animation updates')
        self:check(#s.audio.voices > 0, 'Spatial sound creates a voice')
        self.savedTime = s.time
        m:dispatch('keypressed', 'escape')
    elseif self.frame == 24 then
        self:check(
            s.pauseMenu:isOpen() and m.time.scale == 0 and s.time == self.savedTime,
            'Pause freezes game update'
        )
        self.screenshot = 'pause'
        m:dispatch('keypressed', 'escape')
    elseif self.frame == 27 then
        self:check(
            not s.pauseMenu:isOpen() and m.time.scale == 1 and s.time > self.savedTime,
            'Resume updates game'
        )
        m:switch(require('source.game.runtime.game').new, 'models')
    elseif self.frame == 34 then
        self:check(
            #s.model.nodes == 2 and #s.model.animations == 1,
            'GLB hierarchy and animation import'
        )
        self:check(s.model.nodes[2].rotation[2] ~= 0, 'GLB quaternion animation runs')
        self:check(s.world.byName['OBJ.1'] ~= nil, 'OBJ and MTL load')
        local board = s.world.billboards[1]
        self:check(
            board.screenWidth >= 350 and board.ui.children[1].fontSize >= 26,
            'Animated GLB label has readable screen size and font'
        )
        self:check(s.world.byName['FBX.1'] ~= nil, 'Blender-converted FBX loads as GLB')
        self.screenshot = 'models'
    elseif self.frame == 35 then
        s.buttons.effects:press()
        self.screenshot = 'materials'
    elseif self.frame == 36 then
        s.mixerOverlay.visible = true
        self.screenshot = 'mixer'
    elseif self.frame == 37 then
        s.mixerOverlay.visible = false
        s.buttons.effects:press()
    elseif self.frame == 38 then
        m:switch(require('source.game.runtime.game').new, 'objects')
    elseif self.frame == 42 then
        self:check(#s.world.objects == 401, '400 object test zone')
        self.screenshot = 'objects'
    elseif self.frame == 46 then
        m:switch(require('source.game.runtime.game').new, 'lights')
    elseif self.frame == 50 then
        self:check(
            #s.world.lights == 64 and s.renderer.stats.lights == 32,
            '32 simultaneous GPU lights from 64 candidates'
        )
        self.screenshot = 'lights'
    elseif self.frame == 54 then
        m:switch(require('source.game.runtime.game').new, 'combined')
    elseif self.frame == 59 then
        self:check(#s.world.objects == 401 and s.renderer.stats.lights == 32, 'Combined test zone')
        self.screenshot = 'combined'
    elseif self.frame == 63 then
        katsa.window.setMode(960, 540, { resizable = true, depth = 24, stencil = 8 })
        katsa.resize(960, 540)
    elseif self.frame == 68 then
        self:check(
            s.renderer.width == 960 and s.ui.scale == 1 and s.ui.width == 960,
            'Resize recreates render targets and adapts UI'
        )
        m:switch(require('source.game.runtime.menu').new)
    elseif self.frame == 70 then
        require('validation.tests.integration.renderChecks')(self)
    elseif self.frame == 72 then
        require('validation.tests.integration.parenting')(self)
        require('validation.tests.integration.nodeLifecycle')(self)
        require('validation.tests.integration.contactLifecycle')(self)
        require('validation.tests.integration.shadowSchedule')(self)
        require('validation.tests.integration.spatialTransforms')(self)
        require('validation.tests.integration.physicsTransforms')(self)
        require('validation.tests.integration.audioUIRuntime')(self)
        require('validation.tests.integration.lightSelection')(self)
        require('validation.tests.integration.classSystem')(self)
        require('validation.tests.integration.nodesPhysics')(self)
        m:switch(require('source.game.runtime.game').new, 'physics')
    elseif self.frame == 80 then
        self:check(
            s.physics
                and #s.physics.bodies == 23
                and s.demo.independentBody.body
                and s.demo.triggerBody.body.isTrigger,
            'Physics Lab retains legacy bodies and adds independent body/trigger'
        )
        s.physics.debugEnabled = true
        self.screenshot = 'physics'
    elseif self.frame == 84 then
        self:check(s.physics.debugDraw ~= nil, 'Oimo physics debug geometry draws successfully')
        m:switch(require('source.game.runtime.game').new, 'collisionModels')
    elseif self.frame == 92 then
        self:check(
            s.world.byName['Pyramid.detailed'].body.type == 'static',
            'Trimesh model collider is static'
        )
        local glb = s.world.byName['PhysicalGLB.1']
        self:check(glb ~= nil, 'Physical GLB instance exists')
        for i = 1, 180 do
            s.physics:update(1 / 60)
        end
        s.world:updateObject(glb)
        self:check(
            glb.combined == nil and math.abs(glb.matrix[8] - glb.physicsMatrix[8]) < 0.001,
            'Baked GLB render matrix follows the falling physical body'
        )
        self.screenshot = 'collision-models'
    elseif self.frame == 94 then
        m:switch(require('source.game.runtime.game').new, 'flyingAudio')
    elseif self.frame == 102 then
        self:check(
            s.demo.voice:isPlaying() and #s.demo.voice.sources == 2,
            'Flying emitter continuously plays a spatial stereo pair'
        )
        self:check(s.demo.board.worldPosition[1] ~= 0, 'BillboardUI follows moving attachment')
        self.screenshot = 'flying-audio'
    elseif self.frame == 104 then
        m:switch(require('source.game.runtime.game').new, 'nightPlayer')
    elseif self.frame == 112 then
        require('validation.tests.integration.cameraDebug')(self, s)
        s.input:press('look', 700 * s.ui.scale, 300 * s.ui.scale)
        local yaw = s.camera.rotation[2]
        m.time:setScale(0)
        s.input:move('look', 750 * s.ui.scale, 300 * s.ui.scale, 50 * s.ui.scale, 0)
        self:check(
            s.camera.rotation[2] == yaw + 5,
            'Camera3D look keeps real-time sensitivity while time is frozen'
        )
        s.input:release('look')
        m.time:setScale(1)
        s.camera = s.world:setCamera(s.demo.third)
        s.character.camera = s.camera
        s.demo.third.rotation = { unpack(s.demo.first.rotation) }
        s:update(1 / 60, 1 / 60)
        self:check(
            s.camera.layers == 3 and s.demo.player.layers == 2,
            'Third-person camera renders the player layer'
        )
        self:check(
            s.demo.flashlight:getWorldPosition()[2] > s.demo.player.position[2],
            'Flashlight stays centered at head attachment'
        )
        s.input.axisY = 1
        local start = s.demo.player.position[3]
        for i = 1, 60 do
            s:update(1 / 60, 1 / 60)
        end
        s.input.axisY = 0
        self:check(
            s.demo.player.position[3] > start + 50,
            'Capsule player walks through physical velocity controller'
        )
        s.character:jump()
        s:update(1 / 60, 1 / 60)
        self:check(
            s.demo.player.body:getVelocity()[2] > 50,
            'Grounded capsule player jumps with gravity'
        )
        self.screenshot = 'night-player'
    elseif self.frame == 113 then
        s.demo:setTimeOfDay(12)
        self:check(
            s.world.lighting.sun.enabled and s.world.lighting.sky.brightness > 0.9,
            'Noon slider configuration lights the player scene'
        )
        s.ui:pointer(
            s.demo.daySlider,
            'press',
            (s.demo.daySlider._x + 12) * s.ui.scale + s.ui.offsetX,
            (s.demo.daySlider._y + 20) * s.ui.scale + s.ui.offsetY,
            'day'
        )
        self:check(
            not s.world.lighting.sun.enabled and s.demo.dayHour == 0,
            'time-of-day slider changes actual lighting'
        )
        local body = s.demo.player.body
        body:teleport({ -55, 45, 60 })
        body:setVelocity({ 0, -5, 0 })
        s.character:setMove(0, 0)
        local launched = false
        for i = 1, 80 do
            s.demo:update(1 / 60)
            if body:getVelocity()[2] > 140 then
                launched = true
                break
            end
        end
        self:check(launched, 'Trampoline launches player through an actual collision contact')
        body:teleport({ 55, 40, 70 })
        body:setVelocity({ 0, -5, 0 })
        for i = 1, 90 do
            s.demo:update(1 / 60)
            if m.pendingSwitch then
                break
            end
        end
        self:check(
            m.pendingSwitch ~= nil,
            'Physical scene button queues a transition on player contact'
        )
        local oldWorld = s.world
        m:update(0)
        self:check(
            m.stack[1].zone == 'physics' and oldWorld.root.destroyed,
            'Deferred contact transition releases the previous physics scene'
        )
    elseif self.frame == 114 then
        m:switch(require('source.game.runtime.game').new, 'nodes')
    elseif self.frame == 122 then
        self:check(
            s.demo.satellite.parent == s.demo.pivot and s.demo.socket.parent == s.demo.satellite,
            'Mesh3D and Attachment3D use shared node hierarchy'
        )
        self:check(#s.world.cameras == 2, 'Multiple camera nodes are scene-owned')
        self.screenshot = 'nodes'
    elseif self.frame == 124 then
        s.debugOverlay.visible = true
        self.screenshot = 'debug-menu'
    elseif self.frame == 126 then
        m:switch(require('source.game.runtime.game').new, 'shadows')
    elseif self.frame == 128 then
        self:check(s.renderer.shadows.generation > 0, 'Shadow demo renders readable depth maps')
        self.screenshot = 'shadows-spot'
    elseif self.frame == 129 then
        require('validation.tests.integration.shadows')(self)
        s.demo.shadowSpot.castShadow = false
        s.demo.shadowPoint.castShadow = true
        s.renderer.shadows.nextUpdate = 0
        self.screenshot = 'shadows-point'
    elseif self.frame == 130 then
        m:switch(require('source.game.runtime.menu').new)
    elseif self.frame == 134 then
        self:check(#m.stack == 1 and not m.stack[1].world, 'Return to menu releases game scene')
        local name, version, vendor, device = katsa.graphics.getRendererInfo()
        self.report[#self.report + 1] = 'Renderer: '
            .. table.concat({ name, version, vendor, device }, ' / ')
        katsa.filesystem.write('testReport.txt', table.concat(self.report, '\n'))
        print('ALL RUNTIME TESTS PASSED')
        katsa.event.quit(0)
    end
end

function Runtime:draw()
    if self.screenshot then
        self:capture(self.screenshot)
        self.screenshot = nil
    end
end

return Runtime
