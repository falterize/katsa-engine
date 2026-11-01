local T = {}
T.__index = T

function T.new(manager)
    katsa.errorhandler = function(message)
        print('FAILED v67 ' .. tostring(message))
        return function()
            katsa.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, frame = 0, count = 0 }, T)
end

function T:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v67 ' .. message)
end

function T:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        katsa.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
        local scene, err =
            self.manager:switch(require('source.game.runtime.game').new, 'platformer')
        assert(scene, err)
        self.scene = scene
        local demo = scene.demo
        self:check(
            demo.animator and demo.collider.shape == 'Capsule',
            'Rig, physics and ability scene load'
        )
        self:check(demo.blur.zIndex < 0 and demo.status.zIndex > 0, 'Speed Shader2D is below HUD')
        local mesh = scene.world:create(
            'Mesh3D',
            { name = 'LegacyAlpha', color = { 1, 0, 0, 0.4 }, transparency = 0.5 }
        )
        self:check(
            math.abs(mesh.transparency - 0.8) < 1e-6 and mesh.color[4] == nil and #mesh.color == 3,
            'Legacy alpha folds into Transparency'
        )
        local fields = require('source.engine.editor.inspectors.properties').list(mesh)
        for _, field in ipairs(fields) do
            assert(field.key ~= 'colorAlpha', 'Duplicate colorAlpha remains')
            if field.key == 'color' then
                assert(#field.value == 3)
            end
        end
        self:check(true, 'Inspector exposes RGB and a single mesh transparency')
        local column = scene.world.byName.MaterialMixColumn
        demo.materialA.transparency = 0.5
        demo.materialB.transparency = 0.5
        scene.world:updateObject(column)
        self:check(
            column._surfaceAppearance._composed and #column._activeSurfaces == 2,
            'Multiple appearances compose without extra draw layers'
        )
        local snapshot = column._surfaceBlendCache.snapshots
        scene.world:updateObject(column)
        self:check(
            column._surfaceBlendCache.snapshots == snapshot,
            'Blend buffers and snapshots are reused'
        )
        demo.materialA.transparency = 1
        demo.materialB.transparency = 1
        scene.world:updateObject(column)
        self:check(column._surfaceAppearance == nil, 'Zero weights restore solid mesh color')
        demo.materialA.transparency = 0.5
        demo.materialB.transparency = 0.5
        for i = 1, 50 do
            scene:update(1 / 60, 1 / 60)
        end
        self:check(scene.character.grounded, 'Runner settles above the start platform')
        demo.abilities:jump()
        scene.physics:update(1 / 60)
        self:check(demo.body.body:getVelocity()[2] > 0, 'First jump changes physics velocity')
        scene.character.grounded = false
        scene.character.sinceGrounded = 1
        demo.abilities.jumps = 1
        demo.abilities:jump()
        self:check(demo.abilities.jumps == 2, 'Double jump consumes the second jump')
        demo.abilities:dash()
        scene:update(1 / 60, 1 / 60)
        self:check(
            demo.abilities.dashCooldown > 0 and demo.blur.uniforms.strength > 0,
            'Dash triggers cooldown and speed blur'
        )
        scene.character.grounded = true
        demo.abilities:slide()
        self:check(demo.collider.height == 8, 'Slide changes collision capsule height')
        scene.world.debug = { bones = true, wireframe = false }
        self.capture = 'runner'
    elseif self.frame == 2 then
        self:check(
            #self.manager.journal.entries == 0,
            'Runner, blend and PCSS shaders render without errors'
        )
        self.scene.world.debug.wireframe = true
        self.capture = 'wireframe'
    elseif self.frame == 3 then
        self.scene.world.environment.shadows.mode = 'Standard'
        self.scene.world.debug.wireframe = false
        self:check(not katsa.graphics.isWireframe(), 'Wireframe state does not leak into UI')
        print('TRANSITION runner -> menu')
        local nextScene, err = self.manager:switch(require('source.game.runtime.menu').new)
        assert(nextScene, err)
        print('TRANSITION complete')
    elseif self.frame == 4 then
        self.manager:switch(require('source.game.runtime.menu').new)
        self:check(
            #self.manager.journal.entries == 0,
            'Scene transition releases material buffers cleanly'
        )
        print('PASSED ' .. self.count .. ' focused v67 checks')
        katsa.event.quit()
    end
end

function T:draw()
    if not self.capture then
        return
    end
    local name = self.capture
    self.capture = nil
    katsa.graphics.captureScreenshot(function(image)
        local b = image:encode('png')
        local f = assert(
            io.open(katsa.filesystem.getSource() .. '/docs/previews/v67/' .. name .. '.png', 'wb')
        )
        f:write(b:getString())
        f:close()
        b:release()
        image:release()
    end)
end

return T
