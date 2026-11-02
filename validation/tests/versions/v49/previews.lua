-- Native visual QA capture; use --preview-v49. Captures are internal diagnostics.
local Preview = {}
Preview.__index = Preview
local stages = {
    { 'menu', 360, 640 },
    { 'audioNodes', 360, 640 },
    { 'uiGallery', 360, 640 },
    { 'workspace', 320, 480 },
    { 'palette', 360, 640 },
}

function Preview.new(manager)
    return setmetatable({ manager = manager, index = 0, frame = 0 }, Preview)
end

function Preview:update()
    self.frame = self.frame + 1
    if self.frame % 4 == 1 then
        self.index = self.index + 1
        local entry = stages[self.index]
        if not entry then
            print('PREVIEWS COMPLETE')
            katsa.event.quit()
            return
        end
        katsa.window.setMode(entry[2], entry[3], { depth = 24, stencil = 8, vsync = 0 })
        if entry[1] == 'menu' then
            self.scene = self.manager:switch(require('source.game.scenes.' .. entry[1]).new)
        else
            self.scene = self.manager:switch(
                require('source.game.runtime.game').new,
                entry[1] == 'workspace' and 'audioNodes'
                    or entry[1] == 'palette' and 'uiGallery'
                    or entry[1]
            )
            if entry[1] == 'workspace' or entry[1] == 'palette' then
                local ws = self.scene.workspace
                ws:toggle(true)
                ws:update(0.3)
                local target = entry[1] == 'palette' and self.scene.demo.button
                    or self.scene.demo.sound
                ws:select(target)
                if entry[1] == 'palette' then
                    for _, field in ipairs(ws.fields) do
                        if field.key == 'backgroundColor' then
                            ws:openPopup(field)
                        end
                    end
                end
            end
        end
    elseif self.frame % 4 == 3 then
        self.capture = true
    end
end

function Preview:draw()
    if self.capture then
        self.capture = nil
        local name = stages[self.index][1]
        katsa.graphics.captureScreenshot(function(image)
            image:encode('png', 'v49-preview-' .. name .. '.png')
            image:release()
        end)
    end
end

return Preview
