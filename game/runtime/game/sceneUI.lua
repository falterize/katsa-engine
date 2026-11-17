local ipairs = require('source.engine.math.array').ipairs

local Methods = {}

-- Touch camera buttons (UP / DOWN) of the free camera.
function Methods:buildUI()
    self.cameraButtons = {}
    for i, label in ipairs({ 'UP', 'DOWN' }) do
        local node = self._ui:button({
            position = { 0, 1120, 0, 490 + (i - 1) * 80 },
            size = { 0, 130, 0, 62 },

            backgroundColor = { 0.1, 0.2, 0.3 },
            backgroundTransparency = 1 - 0.8,
            text = label,
            visible = not self.character
                and self.settings.cameraButtons ~= false
                and self.zone ~= 'uiGallery'
                and self.zone ~= 'audioNodes'
                and self.zone ~= 'surfaceGallery',
            fontSize = 24,
        }, self._ui.content)
        node:connect('press', function()
            if i == 1 then
                self.input.up = 1
            else
                self.input.down = 1
            end
        end)
        local function releaseButton()
            if i == 1 then
                self.input.up = 0
            else
                self.input.down = 0
            end
        end
        node:connect('release', releaseButton)
        node:connect('cancel', releaseButton)
        node._cameraControlEligible = node.visible
        node.visible = node.visible and self.world.activeCamera ~= nil
        self.cameraButtons[#self.cameraButtons + 1] = node
    end
    self:syncCameraButtons()
end

function Methods:syncCameraButtons()
    for _, node in ipairs(self.cameraButtons or {}) do
        node.visible = self.world.activeCamera ~= nil and node._cameraControlEligible
    end
end

return Methods
