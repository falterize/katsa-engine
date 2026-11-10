local Interface = {}

local function button(ui, parent, y, text, color, onPress)
    local node = ui:button({
        position = { 0, 10, 0, y },
        size = { 1, -20, 0, 40 },
        text = text,
        textScaled = true,
        maxTextSize = 16,
        backgroundColor = color,
    }, parent)
    if onPress then
        node:connect('press', onPress)
    end
    return node
end

function Interface.create(self)
    local ui = self.scene.ui
    local card = ui:container({
        position = { 0, 12, 0, 96 }, -- below the Menu / Pause bar
        size = { 0, 420, 0, 270 },
        backgroundColor = { 0.08, 0.1, 0.16 },
        backgroundTransparency = 0.15,
    }, ui.content)
    button(ui, card, 10, 'Run on the main thread', { 0.35, 0.18, 0.12 }, function()
        self:startMain()
    end)
    button(ui, card, 58, 'Run on workers (Actor)', { 0.1, 0.3, 0.2 }, function()
        self:startWorkers()
    end)
    button(ui, card, 106, 'Send a ping message', { 0.1, 0.25, 0.35 }, function()
        self:ping()
    end)
    self.status = ui:text({
        position = { 0, 14, 0, 158 },
        size = { 1, -28, 0, 104 },
        text = 'Press a button',
        fontSize = 15,
        textColor = { 0.6, 0.9, 0.7 },
        align = 'left',
    }, card)
end

return Interface
