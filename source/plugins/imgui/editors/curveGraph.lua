local Model = require('source.engine.editor.curves.sequenceModel')
local Sequence = require('source.engine.animation.sequence')

-- An interactive curve view for a point sequence: drag points (time and value), and in Curve
-- interpolation the Bezier handles of the selected point. Times are normalized 0..1 (`duration`
-- only scales the axis label). One value channel is plotted at a time.
local CurveGraph = {}

local BACKGROUND = { 0.03, 0.045, 0.07, 1 }
local GRID = { 1, 1, 1, 0.09 }
local CURVE = { 0.35, 0.8, 1, 1 }
local POINT = { 0.9, 0.92, 0.95, 1 }
local PICKED = { 1, 0.75, 0.2, 1 }
local HANDLE = { 0.45, 1, 0.6, 1 }
local HIT = 10
local EPSILON = 0.0001

local function component(value, channel)
    return type(value) == 'number' and value or value[channel]
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- Handle positions {time, value} of the segment a -> b, defaults included.
local function handles(a, b, channel)
    local va, vb = component(a.value, channel), component(b.value, channel)
    local span = b.time - a.time
    local out = a.outgoing or { a.time + span / 3, 1 / 3 }
    local into = b.incoming or { b.time - span / 3, 2 / 3 }
    return { out[1], va + (vb - va) * out[2] }, { into[1], va + (vb - va) * into[2] }
end

local function range(points, channel, curve)
    local low, high = math.huge, -math.huge
    for index, point in ipairs(points) do
        local v = component(point.value, channel)
        low, high = math.min(low, v), math.max(high, v)
        if curve and points[index + 1] then
            local out, into = handles(point, points[index + 1], channel)
            low, high = math.min(low, out[2], into[2]), math.max(high, out[2], into[2])
        end
    end
    if high - low < 1e-6 then
        low, high = low - 1, high + 1
    end
    local pad = (high - low) * 0.12
    return low - pad, high + pad
end

-- Draws the graph and applies drags. Returns the selected index and whether data changed.
-- `state` keeps { drag } between frames.
function CurveGraph.draw(ig, state, points, interpolation, channel, selected, width, height, duration)
    local curve = interpolation == 'Curve'
    local x0, y0 = ig.cursorScreen()
    ig.invisibleButton('##curve', width, height)
    local active = ig.itemActive()
    local low, high = range(points, channel, curve)
    local function px(time)
        return x0 + time * width
    end
    local function py(value)
        return y0 + (1 - (value - low) / (high - low)) * height
    end
    local mx, my = ig.mouse()
    local changed = false

    -- Pick on press: nearest point, else a handle of the selected point.
    if active and not state.drag then
        local best, bestDistance = nil, HIT * HIT
        for index, point in ipairs(points) do
            local dx = px(point.time) - mx
            local dy = py(component(point.value, channel)) - my
            if dx * dx + dy * dy < bestDistance then
                best, bestDistance = { kind = 'point', index = index }, dx * dx + dy * dy
            end
        end
        if curve and not best then
            local point, nextPoint, previous = points[selected], points[selected + 1], points[selected - 1]
            if nextPoint then
                local out = handles(point, nextPoint, channel)
                local dx, dy = px(out[1]) - mx, py(out[2]) - my
                if dx * dx + dy * dy < bestDistance then
                    best, bestDistance = { kind = 'outgoing', index = selected }, dx * dx + dy * dy
                end
            end
            if previous then
                local _, into = handles(previous, point, channel)
                local dx, dy = px(into[1]) - mx, py(into[2]) - my
                if dx * dx + dy * dy < bestDistance then
                    best = { kind = 'incoming', index = selected }
                end
            end
        end
        state.drag = best
        if best then
            selected = best.index
        end
    end
    if state.drag and not ig.mouseDown(0) then
        state.drag = nil
    end
    local drag = state.drag
    if drag and active then
        local time = clamp((mx - x0) / width, 0, 1)
        local value = high - (my - y0) / height * (high - low)
        local point = points[drag.index]
        if drag.kind == 'point' then
            local previous, nextPoint = points[drag.index - 1], points[drag.index + 1]
            if previous and nextPoint then
                local lower, upper = previous.time + EPSILON, nextPoint.time - EPSILON
                if lower < upper then
                    Model.time(points, drag.index, clamp(time, lower, upper))
                end
            end
            if type(point.value) == 'number' then
                point.value = value
            else
                point.value[channel] = value
            end
            changed = true
        else
            local a = drag.kind == 'outgoing' and point or points[drag.index - 1]
            local b = drag.kind == 'outgoing' and points[drag.index + 1] or point
            local out, into = Sequence.handleTimes(a, b)
            local lower = drag.kind == 'outgoing' and a.time or out
            local upper = drag.kind == 'outgoing' and into or b.time
            local va, vb = component(a.value, channel), component(b.value, channel)
            local normalized = vb ~= va and (value - va) / (vb - va) or 0
            local handle = { clamp(time, lower, upper), normalized }
            if drag.kind == 'outgoing' then
                a.outgoing = handle
            else
                b.incoming = handle
            end
            changed = true
        end
    end

    -- Drawing
    local canvas = ig.canvas()
    canvas.fill(x0, y0, x0 + width, y0 + height, BACKGROUND, 4)
    for step = 1, 3 do
        canvas.line(x0 + width * step / 4, y0, x0 + width * step / 4, y0 + height, GRID, 1)
        canvas.line(x0, y0 + height * step / 4, x0 + width, y0 + height * step / 4, GRID, 1)
    end
    local line, count = {}, 160
    for i = 0, count do
        local time = i / count
        line[#line + 1] = px(time)
        line[#line + 1] = py(component(Sequence.evaluate(points, time, interpolation), channel))
    end
    canvas.polyline(line, CURVE, 2)
    if curve and points[selected] then
        local point = points[selected]
        local px_, py_ = px(point.time), py(component(point.value, channel))
        if points[selected + 1] then
            local out = handles(point, points[selected + 1], channel)
            canvas.line(px_, py_, px(out[1]), py(out[2]), HANDLE, 1)
            canvas.circle(px(out[1]), py(out[2]), 4, HANDLE)
        end
        if points[selected - 1] then
            local _, into = handles(points[selected - 1], point, channel)
            canvas.line(px_, py_, px(into[1]), py(into[2]), HANDLE, 1)
            canvas.circle(px(into[1]), py(into[2]), 4, HANDLE)
        end
    end
    for index, point in ipairs(points) do
        canvas.circle(px(point.time), py(component(point.value, channel)), index == selected and 6 or 4.5, index == selected and PICKED or POINT)
    end
    canvas.text(x0 + 4, y0 + 2, { 1, 1, 1, 0.5 }, ('%.3g'):format(high))
    canvas.text(x0 + 4, y0 + height - 16, { 1, 1, 1, 0.5 }, ('%.3g'):format(low))
    canvas.text(x0 + width - 44, y0 + height - 16, { 1, 1, 1, 0.5 }, ('%.3g s'):format(duration or 1))
    return selected, changed
end

return CurveGraph
