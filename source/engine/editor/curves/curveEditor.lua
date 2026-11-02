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

local function range(self)
    local low, high = 0, 1
    for _, point in ipairs(self.points) do
        low = math.min(low, value(self, point))
        high = math.max(high, value(self, point))
    end
    return low, math.max(low + 0.001, high)
end

local function xy(self, time, v)
    local low, high = range(self)
    return self._x + time * self._width, self._y + (1 - (v - low) / (high - low)) * self._height
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
        local x = self._x + self._width * i / 4
        local y = self._y + self._height * i / 4
        g.line(x, self._y, x, self._y + self._height)
        g.line(self._x, y, self._x + self._width, y)
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
            local t = math.max(0.001, math.min(0.999, (x - self._x) / self._width))
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
        if self.onChange then
            self.onChange()
        end
        self.drag = { id = id, index = best }
    elseif phase == 'move' and self.drag and self.drag.id == id then
        local index = self.drag.index
        local point = self.points[index]
        local low, high = range(self)
        local t = math.max(0, math.min(1, (x - self._x) / self._width))
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
        self.drag = nil
        if self.onChange then
            self.onChange()
        end
    end
end

return Curve
