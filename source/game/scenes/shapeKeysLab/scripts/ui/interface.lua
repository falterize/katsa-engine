local ipairs = require('source.engine.math.array').ipairs

local Interface = {}

function Interface.create(self)
    local ui = self.scene.ui
    local count = #self.names
    local card = ui:container({
        position = { 0, 12, 0, 96 }, -- below the Menu / Pause bar
        size = { 0, 380, 0, 70 + count * 58 },
        backgroundColor = { 0.08, 0.1, 0.16 },
        backgroundTransparency = 0.15,
    }, ui.content)
    self.sliders = {}
    for index, name in ipairs(self.names) do
        local y = 10 + (index - 1) * 58
        ui:text({
            position = { 0, 14, 0, y },
            size = { 1, -28, 0, 22 },
            text = name,
            fontSize = 16,
            align = 'left',
        }, card)
        self.sliders[name] = ui:slider({
            position = { 0, 14, 0, y + 26 },
            size = { 1, -28, 0, 22 },
            min = 0,
            max = 1,
            value = 0,
        }, card)
        self.sliders[name]:connect('changed', function(value)
            if not self.wave then
                self:setShape(name, value)
            end
        end)
    end
    do
        local node = ui:button({
            position = { 0, 14, 0, 18 + count * 58 },
            size = { 1, -28, 0, 40 },
            text = 'Wave (animate from code)',
            textScaled = true,
            maxTextSize = 16,
            backgroundColor = { 0.1, 0.3, 0.2 },
        }, card)
        node:connect('press', function()
            self.wave = not self.wave
        end)
    end
end

return Interface
