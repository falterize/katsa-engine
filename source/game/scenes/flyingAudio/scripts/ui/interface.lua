local Interface = {}

function Interface.create(self)
    local scene, ui = self.scene, self.scene.ui
    self.toolbar = ui:scroll({
        _viewportAuthored = true,
        name = 'Lab controls',
        position = { 0, 12, 0, 112 },
        size = { 0, 340, 0.45, -24 },
        length = 52,
        backgroundColor = { 0.035, 0.065, 0.105 },
    }, ui.content)
    local row = 0

    local function button(text, x, callback)
        local node = ui:button({
            position = { 0, 8, 0, row * 52 + 6 },
            size = { 1, -16, 0, 44 },
            text = text,
            fontSize = 17,
            backgroundColor = { 0.085, 0.135, 0.19 },
        }, self.toolbar)
        if callback then
            node:connect('press', callback)
        end
        row = row + 1
        self.toolbar.length = row * 52 + 12
        return node
    end
    button('Emitter ON/OFF', 250, function()
        if self.voice.manualPause then
            self.voice:resume()
        else
            self.voice:pause()
        end
    end)
    self.toolbar.automaticLength = true
    self.toolbar.contentPadding = 8
    self.toolbar.size = { 0, math.min(340, ui.width - 24), 0.45, -24 }
    self.toolbarToggle =
        require('source.engine.ui.widgets.collapsible').create(scene, self.toolbar, 'Lab controls')
end

return Interface
