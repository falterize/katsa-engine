local T = {}
T.__index = T
local zones = {
    'original',
    'models',
    'objects',
    'lights',
    'combined',
    'lights32',
    'physics',
    'collisionModels',
    'flyingAudio',
    'nightPlayer',
    'shadows',
    'modelLab',
    'nodes',
    'collisionBox',
    'surfaceGallery',
    'uiGallery',
    'audioNodes',
    'particles',
    'viewports',
    'animationLab',
    'shaderLab',
}

function T.new(manager)
    love.errorhandler = function(message)
        print('FAILED v66 ' .. tostring(message))
        return function()
            love.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, frame = 0, count = 0 }, T)
end

function T:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v66 ' .. message)
end

function T:update()
    self.frame = self.frame + 1
    if self.frame == 2 then
        for _, entry in ipairs(self.manager.journal.entries) do
            assert(entry.script == 'assets/missing-sky.png', entry.message)
        end
        self.manager.journal:clear()
    end
    local zone = zones[self.frame]
    if zone then
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, zone)
        assert(scene, err)
        self.scene = scene
        scene:update(0.02, 0.02)
        self:check(#self.manager.journal.entries == 0, 'Scene loads and updates: ' .. zone)
        if zone == 'modelLab' then
            local mesh = scene.demo.multi.objects[1]
            local a = scene.demo.appearance
            self:check(
                mesh._imageSource == nil and mesh.texture == nil,
                'Mesh has no direct image source'
            )
            a.colorMap = 'assets/textures/ui/absent.png'
            scene.world:updateObject(mesh)
            self:check(
                scene.resources:isMissingImage(a.colorMap),
                'Missing material uses checker fallback'
            )
            self.capture = true
            self.manager.journal.entries = {}
        elseif zone == 'original' then
            local mesh =
                scene.world:create('Mesh3D', { name = 'SolidColorTest', color = { 1, 0, 0, 1 } })
            self:check(mesh._surfaceAppearance == nil, 'Untextured mesh remains solid color')
            self:check(
                not pcall(
                    scene.world.create,
                    scene.world,
                    'Mesh3D',
                    { name = 'ForbiddenTexture', texture = 'bricks' }
                ),
                'Direct mesh texture is rejected'
            )
            local broken = 'assets/textures/internal/broken-test.png'
            -- This existing text file deliberately tests the corrupt-image fallback without adding an asset.
            scene.resources:image('README.md')
            self:check(
                scene.resources:isMissingImage('README.md'),
                'Corrupt image uses checker fallback'
            )
            scene.world.environment.sky.texture = 'assets/missing-sky.png'
            self.manager.journal.entries = {}
        end
    else
        self:check(
            #self.manager.journal.entries == 0,
            'Rendering after folder/API migration adds no errors'
        )
        self.manager:switch(require('source.game.runtime.menu').new)
        print('PASSED ' .. self.count .. ' focused v66 checks')
        love.event.quit()
    end
end

function T:draw()
    if not self.capture then
        return
    end
    self.capture = false
    love.graphics.captureScreenshot(function(image)
        local bytes = image:encode('png')
        local f = assert(
            io.open(love.filesystem.getSource() .. '/docs/previews/v66/material-fallback.png', 'wb')
        )
        f:write(bytes:getString())
        f:close()
        bytes:release()
        image:release()
    end)
end

return T
