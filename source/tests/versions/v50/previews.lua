-- Native screenshots of the changed demos and modal property editors.
local Preview = {}
Preview.__index = Preview
local stages = {
    { 'physics', 640, 360 },
    { 'collisionModels', 360, 640 },
    { 'collisionBox', 1280, 720 },
    { 'original', 1280, 720 },
    { 'surfaceGallery', 1280, 720 },
    { 'group', 360, 640 },
    { 'gradient', 360, 640 },
    { 'corner', 320, 480 },
    { 'audioNodes', 360, 640 },
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
        local special = entry[1] == 'group' or entry[1] == 'gradient' or entry[1] == 'corner'
        self.scene = self.manager:switch(
            require('source.game.runtime.game').new,
            special and 'uiGallery' or entry[1]
        )
        if entry[1] == 'gradient' or entry[1] == 'corner' then
            local ws = self.scene.workspace
            ws:toggle(true)
            ws:update(0.3)
            for _, node in ipairs(self.scene.demo.root:getDescendants()) do
                if node:isA(entry[1] == 'gradient' and 'UIGradient' or 'UICorner') then
                    ws:select(node)
                    if entry[1] == 'gradient' then
                        for _, field in ipairs(ws.fields) do
                            if field.key == 'colorStops' then
                                ws:openPopup(field)
                            end
                        end
                    end
                    break
                end
            end
        end
    elseif self.frame % 4 == 3 then
        if stages[self.index][1] == 'group' then
            self.scene.ui:layout()
            self.scene.ui:scrollBy(self.scene.demo.left, 470)
            self.scene.demo.opacityGroup.transparency = 0.001
        end
        self.capture = true
    end
end

function Preview:draw()
    if self.capture then
        self.capture = nil
        local name = stages[self.index][1]
        katsa.graphics.captureScreenshot(function(image)
            image:encode('png', 'v50-preview-' .. name .. '.png')
            image:release()
        end)
    end
end

return Preview
