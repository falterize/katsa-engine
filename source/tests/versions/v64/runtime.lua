local T = {}
T.__index = T

function T.new(manager)
    katsa.errorhandler = function(message)
        print('FAILED v64 ' .. tostring(message))
        return function()
            katsa.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, frame = 0, count = 0 }, T)
end

function T:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v64 ' .. message)
end

function T:load(zone)
    local start = katsa.timer.getTime()
    local scene, err = self.manager:switch(require('source.game.runtime.game').new, zone)
    assert(scene, err)
    self.scene = scene
    scene:update(0.02, 0.02)
    print('LOAD ' .. zone .. ' ' .. string.format('%.3f seconds', katsa.timer.getTime() - start))
    return scene
end

function T:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        katsa.window.setMode(960, 540, { vsync = 0, stencil = 8, depth = 24 })
        local Resources = require('source.engine.core.resources')
        local r = Resources.new(require('source.game.data.manifest'))
        local start = katsa.timer.getTime()
        local raw = require('source.engine.import.glb').load('assets/models/characters/xbot.glb', r)
        local direct = katsa.timer.getTime() - start
        local triangles = 0
        for _, part in ipairs(raw.parts) do
            triangles = triangles + #part.geometry.vertices / 3
        end
        r:release()
        collectgarbage()
        r = Resources.new(require('source.game.data.manifest'))
        start = katsa.timer.getTime()
        local packed =
            require('source.engine.import.packedModel').try('assets/models/characters/xbot.glb', r)
        local cached = katsa.timer.getTime() - start
        local count = 0
        for _, part in ipairs(packed.parts) do
            count = count + part.geometry.mesh:getVertexCount() / 3
        end
        self:check(
            count == triangles and #packed.skins[1].joints == 65,
            'Packed asset preserves triangle and skin data'
        )
        self:check(
            rawget(packed.parts[1].geometry, 'vertices') == nil,
            'Packed geometry keeps CPU vertex tables lazy'
        )
        print(
            string.format(
                'PROFILE XBot decode direct %.3f ms / packed %.3f ms',
                direct * 1000,
                cached * 1000
            )
        )
        r:release()
        collectgarbage()
        local scene = self:load('modelLab')
        local multi = scene.demo.multi
        self:check(
            multi.animator == nil and multi.controller == nil,
            'Static model creates no Animator or controller'
        )
        self:check(
            multi.byNodeName.Cube.instance:isA('Mesh3D')
                and multi.byNodeName.Cube.instance.parent == multi.root,
            'Single primitive becomes a direct Mesh3D without wrappers'
        )
        self:check(
            multi.byNodeName.FloatingTriangle.instance:isA('Mesh3D'),
            'Imported triangle also preserves its mesh node identity'
        )
        self:check(
            scene.demo.model.packed
                and rawget(scene.demo.model.objects[1].geometry, 'vertices') == nil,
            'Rig scene uses cached palettes/envelopes without CPU geometry expansion'
        )
        local mesh = multi.objects[1]
        multi.root.Transparency = 0.5
        mesh.Transparency = 0.4
        scene.world:updateObject(mesh)
        self:check(
            math.abs(mesh._renderOpacity - 0.3) < 1e-6 and mesh.transparency == 0.4,
            'Node3D transparency multiplies child alpha without overwriting it'
        )
        if scene.demo.appearance then
            scene.demo.appearance:destroy()
        end
        local appearance = scene.world:create('SurfaceAppearance3D', {
            normalMap = 'assets/textures/materials/normal.png',
            roughnessMap = 'assets/textures/materials/roughness.png',
            metalnessMap = 'assets/textures/materials/metal.png',
            emissionMap = 'assets/textures/materials/emission.png',
            emissionStrength = 1.4,
            metalness = 0.6,
            roughness = 0.45,
        }, mesh)
        self:check(
            not pcall(appearance.setParent, appearance, multi.root),
            'SurfaceAppearance enforces Mesh3D parenting'
        )
        scene.world:updateObject(mesh)
        self:check(
            mesh._surfaceAppearance == appearance,
            'Mesh resolves its child surface material'
        )
        appearance.Enabled = false
        scene.world:updateObject(mesh)
        self:check(
            mesh._surfaceAppearance == nil,
            'Disabled surface restores the previous mesh material'
        )
        appearance.Enabled = true
        multi.root.Transparency = 0
        mesh.Transparency = 0
        scene:update(0.02, 0.02)
        self.capture = 'surface'
    elseif self.frame == 2 then
        local mesh = self.scene.demo.multi.objects[1]
        self:check(
            mesh._surfaceAppearance.normalMap ~= '' and self.scene.renderer.stats.objects > 0,
            'Surface normal/roughness/metal/emission shaders render'
        )
        self.scene.demo.multi.root.Transparency = 1
        self.scene:update(0.02, 0.02)
        self.scene.world:updateObject(self.scene.demo.multi.objects[1])
        self:check(
            self.scene.demo.multi.objects[1]._renderOpacity == 0,
            'Fully transparent group removes its visible mesh contribution'
        )
    elseif self.frame == 3 then
        local scene = self:load('models')
        self:check(
            scene.model.animator == nil
                and scene.model.controller
                and scene.model.legacyTrack.Playing,
            'Rigid animation still plays without an Animator node'
        )
    elseif self.frame == 4 then
        self:load('collisionModels')
    elseif self.frame == 5 then
        self:check(
            #self.manager.journal.entries == 0,
            'Hierarchy migration and scene teardown leave no errors'
        )
        print('PASSED ' .. self.count .. ' focused v64 checks')
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
        local bytes = image:encode('png')
        local f = assert(
            io.open(katsa.filesystem.getSource() .. '/docs/previews/v64/' .. name .. '.png', 'wb')
        )
        f:write(bytes:getString())
        f:close()
        bytes:release()
        image:release()
    end)
end

return T
