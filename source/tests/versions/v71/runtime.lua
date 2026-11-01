local T = {}
T.__index = T

function T.new(manager)
    katsa.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    katsa.errorhandler = function(err)
        print('FAILED v71 ' .. tostring(err))
        return function()
            return 1
        end
    end
    return setmetatable({ manager = manager, frame = 0, count = 0 }, T)
end

function T:check(ok, name)
    assert(ok, name)
    self.count = self.count + 1
    print('PASS v71 ' .. name)
end

function T:image(scene, general)
    scene.renderer.forceGeneralShader = general
    scene.renderer:draw(scene.world, scene.camera, scene.time)
    return scene.renderer.canvas:newImageData()
end

function T:equivalent(scene, label)
    local a, b = self:image(scene, true), self:image(scene, false)
    local maximum = 0
    for y = 0, a:getHeight() - 1 do
        for x = 0, a:getWidth() - 1 do
            local ar, ag, ab, aa = a:getPixel(x, y)
            local br, bg, bb, ba = b:getPixel(x, y)
            maximum = math.max(
                maximum,
                math.abs(ar - br),
                math.abs(ag - bg),
                math.abs(ab - bb),
                math.abs(aa - ba)
            )
        end
    end
    a:release()
    b:release()
    print('IMAGE MAX DIFFERENCE', label, maximum)
    self:check(maximum < 0.005, label)
end

function T:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        local scene =
            assert(self.manager:switch(require('source.game.runtime.game').new, 'combined'))
        self.scene = scene
        scene.world.environment.render.lightLoop = 'Masked'
        scene.world.environment.shadows.enabled = false
        scene.world.environment.gizmos.enabled = false
        scene:update(1 / 60, 1 / 60)
        self:equivalent(scene, 'Rigid mapless variant matches complete shader')
        self:check(
            #scene.world.objects == 401 and scene.renderer.lights.count == 32,
            'Stress retains 401 objects and 32 selected lights'
        )
        self:check(#scene.renderer.batches.groups == 3, 'Stress retains three instanced batches')
        local masks = require('source.engine.graphics.pipeline.lightMasks')
        local filtered = self:image(scene, false)
        masks.forceAll = true
        local full = self:image(scene, false)
        masks.forceAll = false
        local maximum = 0
        for y = 0, full:getHeight() - 1, 3 do
            for x = 0, full:getWidth() - 1, 3 do
                local a, b, c = full:getPixel(x, y)
                local d, e, f = filtered:getPixel(x, y)
                maximum = math.max(maximum, math.abs(a - d), math.abs(b - e), math.abs(c - f))
            end
        end
        full:release()
        filtered:release()
        self:check(maximum < 0.005, '32-bit light mask preserves every affecting light')
        self:check(
            masks.all[1] == 65535 and masks.all[2] == 65535,
            'Both light-mask halves are exact'
        )
        local mesh = scene.world.objects[2]
        local surface = mesh._surfaceAppearance
        surface.normalMap = 'stone'
        self:equivalent(scene, 'Adding a normal map switches variant without changing output')
        surface.normalMap = ''
        surface.emissionStrength = 0.7
        surface.emissionColor[1] = 0.2
        self:equivalent(scene, 'In-place material edits remain live')
        mesh.position[1] = mesh.position[1] + 7
        self:equivalent(scene, 'In-place transform edits remain live')
        local parent = scene.world:create('Node3D', { transparency = 0.4 })
        mesh.parent = parent
        local visible, opacity = mesh:getVisibilityState()
        self:check(
            visible and math.abs(opacity - 0.6) < 0.00001,
            'Single traversal preserves inherited opacity'
        )
        parent.visible = false
        scene.renderer:prepare(scene.world, scene.camera, scene.time)
        self:check(
            not mesh._renderVisible and not mesh._surfaceAppearance,
            'Hidden ancestor excludes material work immediately'
        )
        parent.visible = true
        self:equivalent(scene, 'Reparenting and visibility changes remain live')
        scene.world.environment.shadows.enabled = true
        local shader =
            require('source.engine.graphics.pipeline.shaderVariants').get(scene.renderer, mesh)
        self:check(
            shader:hasUniform('receiveShadow'),
            'Enabling shadows restores full shadow sampling'
        )
        scene.world.environment.shadows.enabled = false
        self:check(
            not require('source.engine.graphics.pipeline.shaderVariants')
                .get(scene.renderer, mesh)
                :hasUniform('receiveShadow'),
            'Disabled shadows are removed from compiled variant'
        )
        self:check(
            mesh:isA('Node3D') and mesh:isA('Node') and not mesh:isA('Camera3D'),
            'Cached class membership preserves inheritance'
        )
        local ui = scene.ui:create('Frame', { size = { 1, 5, 0, 20 } }, scene.ui.content)
        ui.size = { 0.5, 10, 0, 30 }
        self:check(
            ui.size[1] == 0.5 and ui.size[2] == 10 and ui.size.ScaleX == 0.5,
            'Typed property assignment retains conversion'
        )
    elseif self.frame == 2 then
        local scene = assert(
            self.manager:switch(require('source.game.runtime.game').new, 'animationPhysicsLab')
        )
        self.scene = scene
        scene.world.environment.shadows.enabled = false
        scene.world.environment.gizmos.enabled = false
        scene:update(1 / 60, 1 / 60)
        self:equivalent(scene, 'Skinned scene variants preserve deformed rendering')
        self:check(
            #self.manager.journal.entries == 0,
            'Optimized scenes render without journal errors'
        )
        self.manager:switch(require('source.game.runtime.menu').new)
        print('PASSED ' .. self.count .. ' focused v71 checks')
        katsa.event.quit()
    end
end

function T:draw() end
return T
