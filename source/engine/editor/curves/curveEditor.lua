local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
-- A reusable graph widget edits serializable sequences, not executable callbacks.
local Node = require('../../nodes')
local Sequence = require('../../animation.sequence')

local Curve = Node.define('CurveEditor2D', 'Frame')
Curve.interactive = true
Curve.editorOnly = true

function Curve.initialize(self)
    self.channel = self.channel or 1
    self.dragCapture = true
    self.selected = 1
end

local function value(self, point)
    return Array.is(point.value) and point.value[self.channel] or point.value
end

-- Visible value range. It always contains 0..1 and every point, with a little padding once the
-- values leave 0..1. While a point is being dragged the range is frozen (`_rangeLock`), otherwise
-- the axis would rescale under the pointer.
local function range(self)
    if self._rangeLock then
        return self._rangeLock[1], self._rangeLock[2]
    end
    local low, high = 0, 1
    for _, point in ipairs(self.points) do
        local v = value(self, point)
        low, high = math.min(low, v), math.max(high, v)
    end
    local pad = (high - low > 1) and (high - low) * 0.05 or 0
    low, high = low - pad, high + pad
    return low, math.max(low + 0.001, high)
end

local UNITS_PER_VIEW = 40 -- value units one viewport height shows before the graph scrolls
local MAX_VIEWS = 8

-- Height of the graph for a viewport of `viewHeight` pixels: 0..1 curves fit it exactly, wider
-- value ranges (-50..140) grow taller and are scrolled by the ScrollFrame that holds the graph.
function Curve:fitHeight(viewHeight)
    local low, high = range(self)
    return viewHeight * math.max(1, math.min(MAX_VIEWS, (high - low) / UNITS_PER_VIEW))
end

-- A round grid step (1, 2, 5 x 10^n) that gives roughly `count` lines over the range.
local function niceStep(extent, count)
    local raw = extent / count
    local power = 10 ^ math.floor(math.log(raw) / math.log(10))
    local fraction = raw / power
    return (fraction <= 1 and 1 or fraction <= 2 and 2 or fraction <= 5 and 5 or 10) * power
end

-- Horizontal padding inside the widget: the end points sit clear of its edge and of the scroll bar.
local PAD = 14

local function timeX(self, time)
    return self._x + PAD + time * (self._width - 2 * PAD)
end

local function xyTime(self, x)
    return (x - self._x - PAD) / (self._width - 2 * PAD)
end

local function xy(self, time, v)
    local low, high = range(self)
    return timeX(self, time), self._y + (1 - (v - low) / (high - low)) * self._height
end

local function handle(self, index, kind)
    local point = self.points[index]
    local a, b
    if kind == 'outgoing' then
        a, b = point, self.points[index + 1]
    else
        a, b = self.points[index - 1], point
    end
    if not a or not b then
        return
    end
    local h = point[kind]
        or {
            kind == 'outgoing' and a.time + (b.time - a.time) / 3 or b.time - (b.time - a.time) / 3,
            kind == 'outgoing' and 1 / 3 or 2 / 3,
        }
    return xy(self, h[1], value(self, a) + (value(self, b) - value(self, a)) * h[2])
end

function Curve:drawSelf(ui)
    Curve.base.drawSelf(self, ui)
    local g = katsa.graphics
    g.push('all')
    g.setLineWidth(1)
    g.setColor(0.15, 0.24, 0.31, 1)
    for i = 0, 4 do
        local x = timeX(self, i / 4)
        g.line(x, self._y, x, self._y + self._height)
    end
    local low, high = range(self)
    local step = niceStep(high - low, math.max(4, self._height / 42))
    for v = math.ceil(low / step) * step, high, step do
        local _, y = xy(self, 0, v)
        g.setColor(v == 0 and 0.28 or 0.15, v == 0 and 0.42 or 0.24, v == 0 and 0.52 or 0.31, 1)
        g.line(self._x, y, self._x + self._width, y)
        g.setColor(0.5, 0.62, 0.72, 1)
        g.print(string.format('%g', v), self._x + 3, y - 14)
    end
    g.setColor(0.2, 0.75, 1, 1)
    local px, py
    for i = 0, 96 do
        local t = i / 96
        local v = Sequence.evaluate(self.points, t, self.interpolation)
        if Array.is(v) then
            v = v[self.channel]
        end
        local x, y = xy(self, t, v)
        if px then
            g.line(px, py, x, y)
        end
        px, py = x, y
    end
    for i, point in ipairs(self.points) do
        local x, y = xy(self, point.time, value(self, point))
        if i == self.selected and self.interpolation == 'Curve' then
            for _, kind in ipairs({ 'incoming', 'outgoing' }) do
                local hx, hy = handle(self, i, kind)
                if hx then
                    g.setColor(1, 0.65, 0.2, 1)
                    g.line(x, y, hx, hy)
                    g.circle('line', hx, hy, 5)
                end
            end
        end
        g.setColor(i == self.selected and 1 or 0.4, 0.8, 1, 1)
        g.circle('fill', x, y, 5)
    end
    g.pop()
end

function Curve:pointer(ui, phase, x, y, id)
    x, y = (x - ui.offsetX) / ui.scale, (y - ui.offsetY) / ui.scale
    if phase == 'press' then
        if self.beforePointer and not self.beforePointer() then
            return
        end
        if self.interpolation == 'Curve' then
            for _, kind in ipairs({ 'incoming', 'outgoing' }) do
                local hx, hy = handle(self, self.selected, kind)
                if hx and (x - hx) ^ 2 + (y - hy) ^ 2 < 100 then
                    self.drag = { id = id, kind = kind, index = self.selected }
                    return
                end
            end
        end
        local best, distance = nil, 100
        for i, point in ipairs(self.points) do
            local px, py = xy(self, point.time, value(self, point))
            local d = (x - px) ^ 2 + (y - py) ^ 2
            if d < distance then
                best, distance = i, d
            end
        end
        if not best then
            local t = math.max(0.001, math.min(0.999, xyTime(self, x)))
            for _, point in ipairs(self.points) do
                if math.abs(point.time - t) < 0.005 then
                    return
                end
            end
            best = require('source.engine.editor.curves.sequenceModel').insert(
                self.points,
                t,
                self.interpolation
            )
        end
        self.selected = best
        self._rangeLock = { range(self) }
        if self.onChange then
            self.onChange()
        end
        self.drag = { id = id, index = best }
    elseif phase == 'move' and self.drag and self.drag.id == id then
        local index = self.drag.index
        local point = self.points[index]
        local low, high = range(self)
        local t = math.max(0, math.min(1, xyTime(self, x)))
        local v = low + (1 - (y - self._y) / self._height) * (high - low)
        if self.drag.kind then
            local a, b =
                self.drag.kind == 'outgoing' and point or self.points[index - 1],
                self.drag.kind == 'outgoing' and self.points[index + 1] or point
            local denom = value(self, b) - value(self, a)
            local outgoing, incoming = Sequence.handleTimes(a, b)
            local min = self.drag.kind == 'outgoing' and a.time or outgoing
            local max = self.drag.kind == 'outgoing' and incoming or b.time
            point[self.drag.kind] = {
                math.max(min, math.min(max, t)),
                math.abs(denom) < 0.00001 and 0.5 or (v - value(self, a)) / denom,
            }
        else
            if index > 1 and index < #self.points then
                local previous, nextPoint = self.points[index - 1], self.points[index + 1]
                local epsilon = math.min(0.001, (nextPoint.time - previous.time) * 0.1)
                point.time =
                    math.max(previous.time + epsilon, math.min(nextPoint.time - epsilon, t))
            end
            if Array.is(point.value) then
                point.value[self.channel] = v
            else
                point.value = v
            end
            point.incoming, point.outgoing = nil, nil
            if self.points[index - 1] then
                self.points[index - 1].outgoing = nil
            end
            if self.points[index + 1] then
                self.points[index + 1].incoming = nil
            end
        end
        if self.onChange then
            self.onChange()
        end
    elseif phase == 'release' or phase == 'cancel' then
        self.drag, self._rangeLock = nil, nil
        if self.onChange then
            self.onChange()
        end
    end
end

return Curve
