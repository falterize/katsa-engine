local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(manager)
    return setmetatable({ manager = manager, count = 0 }, Runtime)
end

function Runtime:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v51 ' .. message)
end

function Runtime:update(dt)
    if not self.started then
        self.started = true
        require('source.tests.versions.v51.native')(self)
        print('PASSED ' .. self.count .. ' focused v51 native assertions')
        self.base = require('source.tests.versions.v48.runtime').new(self.manager, false, true)
    end
    self.base:update(dt)
    local base = self.base
    if
        base.frame % 3 == 0
        and base.scene
        and (base.scene.zone == 'surfaceGallery' or base.scene.zone == 'uiGallery')
    then
        local scene = base.scene
        self.capture = 'v51-' .. scene.zone .. '-' .. scene.ui.width .. 'x' .. scene.ui.height
        if scene.zone == 'uiGallery' then
            local ws = scene.workspace
            ws:select(scene.demo.fitImage)
            local props = require('source.engine.editor.inspectors.properties')
            local field
            for _, f in ipairs(ws.fields) do
                if f.key == 'fitMode' then
                    field = f
                end
            end
            props.set(scene, scene.demo.fitImage, field, 'Tile')
            ws:toggle(true)
            ws:update(0)
            local found = false
            for _, f in ipairs(ws.fields) do
                if f.key == 'tileSize' then
                    found = true
                end
            end
            self:check(
                found,
                'Workspace refreshes conditional fields immediately after changing FitMode'
            )
            props.set(scene, scene.demo.fitImage, field, 'Fit')
            ws:update(0)
            found = false
            for _, f in ipairs(ws.fields) do
                if f.key == 'tileSize' then
                    found = true
                end
            end
            self:check(not found, 'Workspace hides inactive tile controls without erasing values')
            ws:toggle(false)
            ws:update(0.3)
        end
    end
end

function Runtime:draw()
    if self.base then
        self.base:draw()
    end
    if self.capture then
        local name = self.capture
        self.capture = nil
        katsa.graphics.captureScreenshot(function(img)
            img:encode('png', name .. '.png')
            img:release()
        end)
    end
end

return Runtime
