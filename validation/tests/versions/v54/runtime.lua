local R = {}
R.__index = R

function R.new(manager)
    return setmetatable({ manager = manager, count = 0, index = 0, frame = 0 }, R)
end

function R:check(ok, msg)
    assert(ok, msg)
    self.count = self.count + 1
    print('PASS v54 ' .. msg)
end

function R:update(dt)
    if not self.started then
        self.started = true
        require('validation.tests.versions.v54.native')(self)
        print('PASSED ' .. self.count .. ' targeted v54 assertions')
    end
    self.frame = self.frame + 1
    if self.frame % 4 == 1 then
        self.index = self.index + 1
        local scenes = { 'combined', 'nightPlayer', 'models', 'physics', 'surfaceGallery' }
        local name = scenes[self.index]
        if not name then
            print('PASSED five scene smoke transitions')
            katsa.event.quit()
            return
        end
        self.scene = self.manager:switch(require('source.game.runtime.game').new, name)
        if name == 'physics' then
            self.scene.workspace:toggle(true)
            self.scene.workspace:update(0.3)
            local popup =
                require('source.engine.editor.panels.groupEditor').open(self.scene.workspace)
            for _, button in ipairs(popup.body.children) do
                if button.text == 'Table view' then
                    button:press()
                    break
                end
            end
            self:check(popup.body.length > 0, 'Group editor switches to a populated table view')
        elseif name == 'nightPlayer' then
            self.scene.camera = self.scene.world:setCamera(self.scene.demo.third, 0.2)
            local old = self.scene.camera
            local p = { unpack(old.position) }
            local debug = require('source.engine.cameras.debugCamera')
            debug.toggle(self.scene)
            self.scene.input:update(0.01)
            debug.toggle(self.scene)
            self:check(
                self.scene.camera == old and old.position[1] == p[1],
                'Debug camera restores active gameplay camera without editing its pose'
            )
        end
    elseif self.frame % 4 == 3 then
        self.capture = true
    end
end

function R:draw()
    if self.capture then
        self.capture = nil
        local name = self.scene.zone
        katsa.graphics.captureScreenshot(function(image)
            image:encode('png', 'v54-' .. name .. '.png')
            image:release()
        end)
    end
end

return R
