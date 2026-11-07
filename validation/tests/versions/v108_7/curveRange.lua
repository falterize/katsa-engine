-- Curve editor: 0..1 curves fit the viewport, wide value ranges (-50..140) grow the graph so the
-- surrounding ScrollFrame can scroll it.
local Curve = require('source.engine.editor.curves.curveEditor')

local Module = {}

local function graph(a, b)
    return { channel = 1, points = { { time = 0, value = a }, { time = 1, value = b } } }
end

function Module.run(self)
    self:check(Curve.fitHeight(graph(0, 1), 170) == 170, 'a 0..1 curve fits the viewport exactly')
    local tall = Curve.fitHeight(graph(-50, 140), 170)
    self:check(tall > 170 * 4 and tall <= 170 * 8, 'a -50..140 curve is several viewports tall')
    self:check(Curve.fitHeight(graph(0, 1e6), 170) == 170 * 8, 'the graph height is capped')
    local locked = graph(0, 1)
    locked._rangeLock = { -5, 5 }
    locked.points[2].value = 1000
    self:check(Curve.fitHeight(locked, 170) == 170, 'a dragged point does not rescale a locked range')

    -- Dragging the last point past the end lengthens the animation once, on release; the axis
    -- stays frozen meanwhile (it used to rescale on every move and grow without bound).
    local lengthened = {}
    local g = {
        channel = 1,
        interpolation = 'Linear',
        selected = 1,
        points = { { time = 0, value = 0 }, { time = 1, value = 1 } },
        _x = 0,
        _y = 0,
        _width = 400,
        _height = 170,
        _endMargin = 100,
        onExtend = function(time)
            lengthened[#lengthened + 1] = time
        end,
    }
    local ui = { offsetX = 0, offsetY = 0, scale = 1 }
    Curve.pointer(g, ui, 'press', 286, 0, 'p')
    for i = 1, 20 do
        Curve.pointer(g, ui, 'move', 286 + i * 5, 0, 'p')
    end
    self:check(#lengthened == 0 and math.abs(g.points[2].time - 1.3676) < 0.01, 'dragging past the end keeps a fixed axis')
    Curve.pointer(g, ui, 'release', 386, 0, 'p')
    self:check(#lengthened == 1 and lengthened[1] < 1.4, 'releasing past the end lengthens the animation once')
    local Timeline = require('source.engine.animation.rampTimeline')
    local ramp = { mode = 'Animated', playbackTime = 1, isLifetime = function() return false end, bindings = {} }
    self:check(not pcall(Timeline.setDuration, ramp, 369395535809), 'an absurd duration is rejected')
    local Model = require('source.engine.editor.curves.sequenceModel')
    local points = { { time = 0, value = 0 }, { time = 0.5, value = 2 } }
    self:check(Model.append(points) == 3 and points[3].time == 1 and points[3].value == 2, 'a point can be appended at the end')
end

return Module
