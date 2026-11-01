-- Whole-scene/native regression checks; run with love . --test-v47.
local Runtime = {}
Runtime.__index = Runtime
local Math = require('source.engine.math.math3d')

function Runtime.new(manager)
    print('NATIVE RENDERER', love.graphics.getRendererInfo())
    return setmetatable({ manager = manager, frame = 0, count = 0 }, Runtime)
end

function Runtime:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS ' .. message)
end

function Runtime:capture(name)
    love.graphics.captureScreenshot(function(image)
        image:encode('png', 'v47-' .. name .. '.png')
        image:release()
    end)
end

function Runtime:update()
    self.frame = self.frame + 1
    local manager = self.manager
    local scene = manager.stack[#manager.stack]
    if self.frame == 2 then
        manager:switch(require('source.game.runtime.game').new, 'audioNodes')
    elseif self.frame == 3 then
        scene.renderer.renderDensity = 2
    elseif self.frame == 4 then
        self:check(
            scene.renderer.canvas:getDPIScale() == 2 and scene.renderer.actualMSAA <= 4,
            'Native render targets follow requested density with bounded MSAA'
        )
        self:check(
            scene.zone == 'audioNodes' and scene.demo.status ~= nil,
            'Whole sound scene loads with controls and modifiers'
        )
        scene.demo:choose('Reverb', 'SoundReverb')
        scene.audio:update(scene.camera)
        self:check(scene.demo.sound:isPlaying(), 'Listening preset starts a native source')
        self:capture('audio')
    elseif self.frame == 6 then
        manager:switch(require('source.game.runtime.game').new, 'collisionBox')
    elseif self.frame == 8 then
        local demo = scene.demo
        for i = 1, 9 do
            demo:spawn()
        end
        scene.physics:update(1 / 60)
        self:check(
            scene.renderer.stats.objects >= 5,
            'Collision box walls stay inside camera draw distance'
        )
        self:check(#scene.physics.bodies == 14, 'Collision box spawns three real collider types')
        demo:reset()
        self:check(
            #scene.physics.bodies == 5 and #demo.items == 0,
            'Reset removes spawned geometry and solver bodies'
        )
        demo:spawn()
        self:capture('collisions')
    elseif self.frame == 10 then
        manager:switch(require('source.game.runtime.game').new, 'surfaceGallery')
    elseif self.frame == 12 then
        local panel = scene.demo.panels[1]
        self:check(
            #scene.world.billboards == 8 and #scene.world.decals == 2,
            'Surface gallery creates six faces, attachment, onTop and Decal3D nodes'
        )
        local button
        for _, child in ipairs(panel.children[1].children) do
            if child:isA('Button') then
                button = child
            end
        end
        self:check(button:isA('Button'), 'Surface panel owns actual UI button')
        local wx, wy, wz = Math.transform(panel.matrix, 0, -0.18, 0)
        local x, y = scene.camera:project({ wx, wy, wz })
        local hit = panel:hit(scene.world, scene.camera, x, y)
        self:check(hit == button, 'Surface ray hit transforms to local UI coordinates')
        local entered, hoverY, left = false, nil, false
        button.onEnter = function()
            entered = true
        end
        button.onHover = function(_, _, hy)
            hoverY = hy
        end
        button.onLeave = function()
            left = true
        end
        scene.input:hover(x, y)
        scene.input:hover(10, 700)
        self:check(
            entered and left and math.abs(hoverY - 0.68 * panel.canvasSize[2]) < 0.01,
            'Surface mouse hover uses local coordinates and leave events'
        )
        local released
        button.onRelease = function(_, rx, ry)
            released = { rx, ry }
        end
        scene:pointerpressed('surface-test', x, y)
        scene:pointerreleased('surface-test', x, y)
        self:check(
            scene.demo.clicks == 1
                and released
                and math.abs(released[2] - 0.68 * panel.canvasSize[2]) < 0.01,
            'Surface touch press/release stays in UI coordinates and avoids camera capture'
        )
        local blocker = scene.world:create('Mesh3D', {
            name = 'TestOccluder',
            position = { wx, wy, wz - 30 },
            size = { 30, 60, 8 },
            texture = 'white',
        })
        scene.world:updateObject(blocker)
        self:check(
            panel:hit(scene.world, scene.camera, x, y) == nil,
            'Opaque geometry occludes normal SurfaceUI input'
        )
        panel.onTop = true
        self:check(
            panel:hit(scene.world, scene.camera, x, y) == button,
            'onTop SurfaceUI intentionally ignores world occlusion'
        )
        blocker:destroy()
        panel.onTop = false
        local camera = scene.camera
        local depth = 60
        local dx, dy =
            (125 - camera.width / 2) * depth / camera.focal,
            -(570 - camera.height / 2) * depth / camera.focal
        local p = {}
        for i = 1, 3 do
            p[i] = camera.worldPosition[i]
                + camera.right[i] * dx
                + camera.up[i] * dy
                + camera.forward[i] * depth
        end
        local board = scene.world:create('BillboardUI', {
            name = 'BehindJoystick',
            position = p,
            size = { 0, 100, 0, 100 },
            canvasSize = {
                100,
                100,
            },
            onTop = true,
        })
        board.ui:button({ size = { 1, 0, 1, 0 }, text = 'Behind' }, board)
        board:update(scene.world, camera)
        board:refresh()
        scene.renderer.top[#scene.renderer.top + 1] = board
        scene.input:press('joy-test', 125, 570)
        self:check(
            scene.input.captures['joy-test'].kind == 'joystick',
            'Joystick region takes precedence over a world UI button behind it'
        )
        scene.input:release('joy-test', 125, 570)
        board:destroy()
        self:capture('surfaces')
    elseif self.frame == 14 then
        manager:switch(require('source.game.runtime.game').new, 'uiGallery')
    elseif self.frame == 16 then
        local demo = scene.demo
        scene.ui:layout()
        self:check(demo.button._width > 100, 'UDim2 gallery resolves scale dimensions')
        demo.button.onPress()
        self:check(demo.presses == 1, 'Gallery button remains interactive')
        love.window.setMode(
            1600,
            900,
            { resizable = true, depth = 24, stencil = 8, highdpi = true, vsync = 0 }
        )
        scene:resize(love.graphics.getDimensions())
        scene.ui:layout()
        self:check(
            scene.ui.width == 1600 and scene.ui.height == 900 and scene.ui.scale == 1,
            'Viewport UI follows full logical screen dimensions'
        )
        love.window.setMode(
            1280,
            720,
            { resizable = true, depth = 24, stencil = 8, highdpi = true, vsync = 0 }
        )
        scene:resize(love.graphics.getDimensions())
        scene.ui:layout()
        self:capture('ui')
    elseif self.frame == 18 then
        manager:switch(require('source.game.runtime.game').new, 'combined')
    elseif self.frame == 20 then
        scene.world.lighting.shadows.enabled = true
        scene.world.lighting.shadows.distance = 40
        scene.renderer.shadows.nextUpdate = 0
    elseif self.frame == 22 then
        self:check(
            scene.renderer.stats.shadowFaces == 0
                and scene.renderer.stats.shadowDrawCalls == 0
                and scene.renderer.stats.lights == 32
                and #scene.world.objects == 401,
            '400-cube/32-selected-light scene submits zero shadow passes at empty distance 40'
        )
        scene.camera.rotation[2] = scene.camera.rotation[2] + 15
    elseif self.frame == 23 then
        self:check(
            scene.renderer.stats.shadowFaces == 0 and scene.renderer.stats.shadowDrawCalls == 0,
            'Camera3D motion retains zero shadow work when the distance contains no receivers'
        )
        scene.world.lighting.shadows.distance = 240
        scene.renderer.shadows.nextUpdate = 0
    elseif self.frame >= 24 then
        if scene.renderer.shadows.pendingFaces > 0 then
            assert(self.frame < 90, 'Static shadow queue did not finish within 66 frames')
            return
        end
        if not self.cacheReadyFrame then
            self.cacheReadyFrame = self.frame
            return
        end
        self:check(
            scene.renderer.stats.shadowFaces == 0,
            'Static stress scene reuses completed maps after a full generation'
        )
        require('source.tests.integration.audioUIRuntime')(self)
        love.filesystem.write(
            'v47-report.txt',
            'PASSED ' .. self.count .. ' native v47 assertions\n'
        )
        print('PASSED ' .. self.count .. ' native v47 assertions')
        love.event.quit(0)
    end
end

function Runtime:draw() end
return Runtime
