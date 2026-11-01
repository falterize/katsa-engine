local Preview = {}
Preview.__index = Preview
local stages = {
    { 'surfaceGallery', 1280, 720 },
    { 'surfaceGallery', 360, 640 },
    { 'physics', 1280, 720 },
    { 'shadows', 1280, 720 },
    { 'uiGallery', 640, 360 },
}

function Preview.new(manager)
    return setmetatable({ manager = manager, frame = 0, index = 0 }, Preview)
end

function Preview:update()
    self.frame = self.frame + 1
    if self.frame % 5 == 1 then
        self.index = self.index + 1
        local stage = stages[self.index]
        if not stage then
            print('v52 visual previews complete')
            katsa.event.quit()
            return
        end
        katsa.window.setMode(stage[2], stage[3], { depth = 24, stencil = 8, vsync = 0 })
        self.scene = self.manager:switch(require('source.game.runtime.game').new, stage[1])
        if stage[1] == 'physics' then
            self.scene.workspace:toggle(true)
            self.scene.workspace:update(0.3)
            self.scene.workspace:select(self.scene.demo.independentBody)
        elseif stage[1] == 'shadows' then
            self.scene.demo.directionalShadow.enabled = true
        elseif stage[1] == 'uiGallery' then
            for _, node in ipairs(self.scene.demo.root:getDescendants()) do
                if node:isA('UIGradient') and node.target == 'Text' then
                    for _, stop in ipairs(node.colorStops) do
                        stop.transparency = 1
                    end
                elseif node:isA('UIStroke') and node.target == 'Text' then
                    node.color = { 1, 0.5, 0.1 }
                    node.thickness = { 0, 3 }
                end
            end
            self.scene.ui:layout()
            self.scene.ui:scrollBy(self.scene.demo.left, 115)
        end
    elseif self.frame % 5 == 4 then
        self.capture = true
    end
end

function Preview:draw()
    if self.capture then
        self.capture = nil
        local stage = stages[self.index]
        local name = 'v52-' .. stage[1] .. '-' .. stage[2] .. 'x' .. stage[3]
        katsa.graphics.captureScreenshot(function(image)
            image:encode('png', name .. '.png')
            image:release()
        end)
    end
end

return Preview
