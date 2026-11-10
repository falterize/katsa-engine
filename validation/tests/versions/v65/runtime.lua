local T = {}
T.__index = T

function T.new(manager)
    katsa.errorhandler = function(message)
        print('FAILED v65 ' .. tostring(message))
        return function()
            katsa.event.quit(1)
        end
    end
    return setmetatable({ manager = manager, frame = 0, count = 0 }, T)
end

function T:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v65 ' .. message)
end

function T:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        katsa.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
        local scene, err = self.manager:switch(require('source.game.runtime.game').new, 'original')
        assert(scene, err)
        self.scene = scene
        local sky = scene.world.environment.sky
        local Image = require('source.engine.components.media.image')
        self:check(
            not Image.pixelate({}, { pixelate = true }),
            'Legacy global Pixelate no longer affects nodes'
        )
        self:check(
            scene.world.environment.pixelate == nil,
            'EnvironmentLighting has no Pixelate setting'
        )
        local linear = Image.resolve(scene.resources, {}, sky.texture)
        local nearest = Image.resolve(scene.resources, { pixelate = true }, sky.texture)
        self:check(
            linear:getFilter() == 'linear'
                and nearest:getFilter() == 'nearest'
                and linear ~= nearest,
            'Sky sampler variants are isolated'
        )
        self:check(
            linear:getWidth() == 2048 and linear:getHeight() == 1536,
            'Supplied sky atlas loads unchanged'
        )
        local memory = scene.resources:image('stone')
        local smooth = Image.resolve(scene.resources, {}, memory)
        self:check(
            smooth:getFilter() == 'linear' and memory:getFilter() == 'nearest',
            'Imported image smoothing leaves shared sampler intact'
        )
        local Schema = require('source.engine.editor.inspectors.schema')
        local found = {}
        for _, key in ipairs(Schema.keys(sky, {})) do
            found[key] = true
        end
        self:check(
            found.texture and found.pixelate and found.layout,
            'Sky inspector includes path and Pixelate'
        )
        local Properties = require('source.engine.editor.inspectors.properties')
        local field = { key = 'texture', kind = 'string' }
        self:check(
            not Properties.set(scene, sky, field, 'assets/missing-sky.png')
                and sky.texture == 'assets/textures/sky/dayCross.png',
            'Missing sky path is rejected without changing texture'
        )
        self:check(not Properties.set(scene, sky, field, 'white'), 'Non-cross texture is rejected')
        self:check(
            Properties.set(scene, sky, field, 'assets/textures/sky/dayCross.png'),
            'Valid sky path is editable'
        )
        self.expectedErrors = #self.manager.journal.entries
        scene:update(0.02, 0.02)
        self.capture = true
    elseif self.frame == 2 then
        self.scene.world.environment.sky.pixelate = true
        self.scene:update(0.02, 0.02)
    elseif self.frame == 3 then
        self:check(
            #self.manager.journal.entries == self.expectedErrors,
            'Smooth and pixelated sky render without errors'
        )
        print('PASSED ' .. self.count .. ' focused v65 checks')
        katsa.event.quit()
    end
end

function T:draw()
    if not self.capture then
        return
    end
    self.capture = false
    katsa.graphics.captureScreenshot(function(image)
        local bytes = image:encode('png')
        local f = assert(io.open(katsa.filesystem.getSource() .. '/docs/previews/v65/sky.png', 'wb'))
        f:write(bytes:getString())
        f:close()
        bytes:release()
        image:release()
    end)
end

return T
