-- ScrollFrame: touch swipe glide, elastic ends, mouse swipe only when enabled.
local UI = require('source.engine.ui')

local Module = {}

local function make(self, settings)
    local ui = UI.new(200, 200, self.manager.resources:scope())
    settings.size = { 0, 200, 0, 200 }
    settings.canvasSize = { 0, 0, 0, 1000 }
    local frame = ui:create('ScrollFrame', settings, ui.content)
    ui:layout()
    return ui, frame
end

local function swipe(ui, frame, id, from, to, steps)
    ui:pointer(frame, 'press', 100, from, id)
    for i = 1, steps do
        ui.time = ui.time + 0.016
        ui:pointer(frame, 'move', 100, from + (to - from) * i / steps, id)
    end
    ui:pointer(frame, 'release', 100, to, id)
end

function Module.run(self)
    local ui, frame = make(self, { inertia = 0.8, overscroll = 0.25 })
    swipe(ui, frame, 'touch1', 150, 50, 6)
    local released = frame.scrollY
    for _ = 1, 20 do
        ui:update(0.016)
    end
    self:check(released > 90 and frame.scrollY > released + 20, 'touch swipe keeps gliding after release')

    local ui2, top = make(self, { overscroll = 0.25, bounceSpeed = 14 })
    ui2:pointer(top, 'press', 100, 50, 'touch1')
    ui2.time = ui2.time + 0.016
    ui2:pointer(top, 'move', 100, 150, 'touch1')
    self:check(top.scrollY == 0 and top._overY < 0 and top._overY > -50, 'dragging past the start stretches elastically')
    ui2:pointer(top, 'release', 100, 150, 'touch1')
    for _ = 1, 120 do
        ui2:update(0.016)
    end
    self:check(top._overY == 0 and top.scrollY == 0, 'the stretch springs back to the limit')

    local ui3, mouse = make(self, {})
    swipe(ui3, mouse, 'mouse', 150, 50, 6)
    self:check(mouse.scrollY == 0, 'mouse swipe is ignored while dragWithMouse is off')
    mouse.dragWithMouse = true
    swipe(ui3, mouse, 'mouse', 150, 50, 6)
    self:check(mouse.scrollY > 90, 'mouse swipe scrolls once dragWithMouse is on')

    local ui4, hard = make(self, { overscroll = 0, inertia = 0 })
    swipe(ui4, hard, 'touch1', 50, 150, 6)
    self:check(hard.scrollY == 0 and hard._overY == 0, 'overscroll 0 is a hard stop')
end

return Module
