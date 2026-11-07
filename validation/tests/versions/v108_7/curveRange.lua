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
end

return Module
