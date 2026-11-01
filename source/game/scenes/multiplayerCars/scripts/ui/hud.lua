-- In-game overlay: speed, nitro, seat and the buttons for changing car and watching an ad.
local Hud = {}
Hud.__index = Hud

function Hud.create(scene, callbacks)
    local ui = scene.ui
    local self = setmetatable({ ui = ui }, Hud)
    self.root = ui:container({
        name = 'CarsHud',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        backgroundTransparency = 1,
    }, ui.content)
    self.info = ui:text({
        position = { 0, 16, 0, 62 },
        size = { 0.6, 0, 0, 56 },
        text = '',
        fontSize = 17,
        align = 'left',
    }, self.root)
    self.barBack = ui:container({
        position = { 0, 16, 1, -52 },
        size = { 0, 260, 0, 22 },
        backgroundColor = { 0.05, 0.07, 0.1 },
    }, self.root)
    self.bar = ui:container({
        position = { 0, 2, 0, 2 },
        size = { 1, -4, 1, -4 },
        backgroundColor = { 0.2, 0.75, 1 },
    }, self.barBack)
    ui:text({
        position = { 0, 16, 1, -80 },
        size = { 0, 260, 0, 22 },
        text = 'NITRO',
        fontSize = 14,
        align = 'left',
    }, self.root)
    self.speed = ui:text({
        position = { 1, -16, 1, -64 },
        size = { 0, 200, 0, 40 },
        anchorPoint = { 1, 0 },
        text = '0 km/h',
        fontSize = 28,
        align = 'right',
    }, self.root)
    ui:button({
        position = { 1, -16, 0, 62 },
        size = { 0, 170, 0, 40 },
        anchorPoint = { 1, 0 },
        text = 'Change car (E)',
        fontSize = 15,
        backgroundColor = { 0.085, 0.135, 0.19 },
        onPress = callbacks.sit,
    }, self.root)
    self.adButton = ui:button({
        position = { 1, -16, 0, 108 },
        size = { 0, 170, 0, 40 },
        anchorPoint = { 1, 0 },
        text = 'Nitro: watch ad (N)',
        fontSize = 15,
        backgroundColor = { 0.35, 0.2, 0.55 },
        onPress = callbacks.ad,
    }, self.root)
    ui:button({
        position = { 1, -16, 0, 154 },
        size = { 0, 170, 0, 40 },
        anchorPoint = { 1, 0 },
        text = 'Leave game',
        fontSize = 15,
        backgroundColor = { 0.4, 0.15, 0.15 },
        onPress = callbacks.leave,
    }, self.root)
    self.message = ui:text({
        position = { 0.5, 0, 0, 120 },
        size = { 0, 500, 0, 30 },
        anchorPoint = { 0.5, 0 },
        text = '',
        fontSize = 18,
        textColor = { 1, 0.85, 0.4 },
    }, self.root)
    return self
end

function Hud:setVisible(visible)
    self.root.visible = visible
end

function Hud:flash(text)
    self.message.text = text
    self.flashTime = 3
end

function Hud:update(dt, state)
    self.info.text = state.info or ''
    self.speed.text = ('%d km/h'):format(math.abs(state.speed or 0) * 3.6)
    self.bar.size = { math.max(0, math.min(1, state.nitro or 0)), -4, 1, -4 }
    self.adButton.text = state.adText or 'Nitro: watch ad (N)'
    if self.flashTime then
        self.flashTime = self.flashTime - dt
        if self.flashTime <= 0 then
            self.message.text, self.flashTime = '', nil
        end
    end
end

return Hud
