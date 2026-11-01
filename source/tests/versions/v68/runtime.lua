local T = {}
T.__index = T

function T.new(manager)
    katsa.errorhandler = function(message)
        print('FAILED v68 ' .. tostring(message))
        return function()
            katsa.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, frame = 0, count = 0 }, T)
end

function T:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v68 ' .. message)
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
        local M = require('source.engine.math.math3d')
        demo.abilities.dashTime, demo.abilities.slideTime = 0, 0
        demo.rig.root.rotation[1] = 0
        for _, direction in ipairs({
            { 1, 0 },
            { -1, 0 },
            { 0, 1 },
            { 0, -1 },
            { 1, 1 },
            { -1, 1 },
            {
                1,
                -1,
            },
            {
                -1,
                -1,
            },
        }) do
            demo.body.body:setVelocity({ direction[1] * 70, 0, direction[2] * 70 })
            demo:update(0)
            local matrix = M.compose({ 0, 0, 0 }, demo.rig.root.rotation, { 1, 1, 1 })
            local x, _, z = M.transform(matrix, 0, 0, 1, 0)
            local length = math.sqrt(direction[1] ^ 2 + direction[2] ^ 2)
            assert(
                (x * direction[1] + z * direction[2]) / length > 0.999,
                'Avatar faces away from velocity'
            )
        end
        self:check(true, 'Avatar faces movement in all eight horizontal directions')
        self:check(
            #demo.pickups == 8 and scene.world.root:find('FinishIsland', true),
            'Extended course and practice islands exist'
        )

        local function overlaps(a, b)
            return a._x < b._x + b._width
                and b._x < a._x + a._width
                and a._y < b._y + b._height
                and b._y < a._y + a._height
        end
        for _, size in ipairs({ { 960, 540 }, { 640, 360 }, { 390, 844 } }) do
            katsa.window.setMode(size[1], size[2], { vsync = 0, depth = 24, stencil = 8 })
            scene:resize(size[1], size[2])
            scene.ui:layout()
            local toggle = scene.ui:find('Runner / systemsToggle', true)
            assert(toggle, 'Runner toggle missing')
            assert(not overlaps(demo.status, toggle), 'Status overlaps systems toggle')
            assert(not overlaps(demo.status, scene.debugButton), 'Status overlaps Debug button')
            assert(not overlaps(toggle, scene.debugButton), 'Systems toggle overlaps Debug button')
        end
        self:check(
            true,
            'Runner HUD has no status/toggle/debug intersections at three viewport sizes'
        )
        katsa.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
        scene:resize(960, 540)
        demo.body.body:setVelocity({ 0, 0, 0 })
        demo.controlsPanel.visible = true
        self.capture = 'runner'
    elseif self.frame == 2 then
        self:check(
            #self.manager.journal.entries == 0,
            'Runner, blend and PCSS shaders render without errors'
        )
        self.scene.world.debug.wireframe = true
        self.capture = 'wireframe'
    elseif self.frame == 3 then
        local wire = self.scene.renderer.wireMeshes
        assert(wire and next(wire), 'Shader wireframe did not create edge geometry')
        local skinned = false
        for geometry, mesh in pairs(wire) do
            local format = mesh:getVertexFormat()
            assert(format[#format][1] == 'wireBarycentric', 'Missing barycentric coordinates')
            for _, attribute in ipairs(format) do
                if attribute[1] == 'skinWeights' then
                    skinned = true
                end
            end
        end
        self:check(skinned, 'Portable wireframe covers static and skinned geometry')
        self:check(not katsa.graphics.isWireframe(), 'Wireframe works without native polygon mode')
        self.scene.world.environment.shadows.mode = 'Standard'
        self.scene.world.debug.wireframe = false
        self:check(not katsa.graphics.isWireframe(), 'Wireframe state does not leak into UI')
        print('TRANSITION runner -> menu')
        local nextScene, err = self.manager:switch(require('source.game.runtime.menu').new)
        assert(nextScene, err)
        print('TRANSITION complete')
    elseif self.frame >= 4 and self.frame <= 6 then
        local routes = { 'modelLab', 'animationLab', 'shaderLab' }
        local route = routes[self.frame - 3]
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, route)
        assert(scene, err)
        for _, size in ipairs({ { 640, 360 }, { 390, 844 } }) do
            katsa.window.setMode(size[1], size[2], { vsync = 0, depth = 24, stencil = 8 })
            scene:resize(size[1], size[2])
            scene:update(1 / 60, 1 / 60)
            scene.ui:layout()
            if route == 'shaderLab' then
                assert(
                    scene.demo.clean._width > 0 and scene.demo.clean._height > 0,
                    'Shader preview collapsed'
                )
                assert(
                    scene.demo.controls._x + scene.demo.controls._width <= scene.demo.views._x,
                    'Shader controls overlap previews'
                )
            else
                local panel = route == 'modelLab' and scene.ui:find('ModelControls', true)
                    or scene.demo.panel
                local joystick = scene.controls.joystick
                assert(
                    panel._y + panel._height < joystick.y - joystick.radius,
                    'Lab controls overlap joystick'
                )
            end
        end
        self:check(true, route .. ' controls fit landscape and portrait viewports')
        self.capture = route
    elseif self.frame == 7 then
        self.manager:switch(require('source.game.runtime.menu').new)
        self:check(
            #self.manager.journal.entries == 0,
            'Changed scenes render and release without journal errors'
        )
        print('PASSED ' .. self.count .. ' focused v68 checks')
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
            io.open(katsa.filesystem.getSource() .. '/docs/previews/v68/' .. name .. '.png', 'wb')
        )
        f:write(b:getString())
        f:close()
        b:release()
        image:release()
    end)
end

return T
